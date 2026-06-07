# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current state

Phases 1–6 of the original build plan are in. The app is a single `index.html` (~1.5k lines, ~54 KB) holding all CSS and JS inline, plus an importmap that pulls Three.js from jsdelivr. Phase 7 (hotspot calibration against the real BIM model) is the main outstanding work; Phase 8 (end-to-end smoke) has not been confirmed with a valid API key.

| File | Size | Purpose |
|---|---|---|
| `index.html` | ~54 KB | The entire app. Inline CSS + two `<script type="module">` blocks. |
| `Semco_DigitalTwin_BuildSpec.docx` | 17 KB | Authoritative spec. Convert with `textutil -convert txt -output /tmp/spec.txt Semco_DigitalTwin_BuildSpec.docx`. |
| `transformer.glb` | **183 MB** | glTF 2.0 binary (originally `substation_bimfra.glb`, renamed per spec). BIM/IFC export of the **whole substation**, not a standalone transformer — see "Asset reality check" below. |
| `Cognizantlogo.png` | 23 KB | Cognizant brandmark (cube + wordmark). Renders top-left of the header inside a white rounded chip. |
| `.playwright-mcp/` | — | Console logs and page snapshots from MCP Playwright runs (gitignore candidate). Latest run is clean; an earlier run captured a TDZ error that has since been fixed. |

`README.md` is referenced in the eventual file layout but has not been created yet.

## What we're built (one paragraph)

A single-file `index.html` browser app — no bundler, no `npm install`, no backend — that renders a three-panel demo: (1) left, an SVG flow diagram of five "agents" that animate based on keyword matches against the user's chat input; (2) centre, a Three.js scene loaded via importmap CDN showing the substation/transformer with `THREE.Sprite` hotspots driven by hardcoded sensor data; (3) right, a chat panel that streams responses from the Anthropic Messages API directly from the browser, with Web Speech API voice input. The API key is prompted on first load and held in `sessionStorage` only. Acceptance criteria live in spec §1.2.

## Asset reality check (still applies)

The spec (§5.2) assumes a small `transformer.glb` and gives hotspot coordinates against a procedural fallback that's a `2 × 3 × 1.5` box (§5.3). The actual asset is **a 183MB full-substation BIM model**. What's handled in the code, and what isn't:

1. **Camera/scale** — handled. `fitCameraToObject()` computes a bounding box, recentres the model on origin, and fits the camera at a `dir.normalize() * fitDist * 1.6` offset (`index.html` ~line 960). Model dimensions are exposed via `window.__modelBounds` for later phases.
2. **Hotspot positions** — **NOT calibrated**. `components[].position` (~line 716) still holds the spec §5.3 values calibrated for the procedural fallback (`[0.5, 1.8, 0]`, etc.). On the real BIM model these float somewhere near the origin after recentering and don't track any specific component. Re-anchoring is Phase 7.
3. **Hotspot sizing** — handled smarter than the spec. Sprite scale is computed relative to `maxSize` of the model bounds (`baseHealthy = maxSize * 0.020`, `baseWarning = maxSize * 0.033`), so hotspots stay readable whether the model is the small procedural box or the BIM-scale GLB.
4. **Load time** — handled. A loading overlay shows during `GLTFLoader.load` with a percent counter (or MB counter when the response isn't length-computable). The overlay fades out on success.
5. **Performance** — partially handled. `setPixelRatio(Math.min(devicePixelRatio, 1.5))` is set; shadows are disabled by default. If FPS becomes poor on the real BIM, the contingency is procedural fallback as a demo crutch and treat the real GLB as Phase 2 polish.
6. **OneDrive sync** — building in the synced directory is acceptable. Large reads may stall if OneDrive is paging the GLB in/out.

## Build location (confirmed)

**Building in this OneDrive directory** (not `~/semco-twin/` as spec §7 Step 1 suggests). GLB has been renamed to `transformer.glb` per spec.

## Build status (by phase)

### Phase 0 — Locked decisions ✅
- Build location: this directory.
- GLB filename: `transformer.glb`.
- Logo placement: top-left of header, in a white rounded chip — implemented.
- API-key flow: per spec §6.5 (first-load modal, `sessionStorage` only) — implemented.
- Model ID: code hardcodes `claude-sonnet-4-6` (constant `MODEL_ID`, ~line 1227). The spec's stale `claude-sonnet-4-20250514` was discarded.

### Phase 1 — Skeleton & layout ✅
- 56px header bar + three-panel grid (25 / 50 / 25 columns).
- Background `#0a0f1e`, panel backgrounds match spec §3 table.
- Cognizant logo + "Semco Digital Twin — Offshore Substation Transformer" title in the header.

### Phase 2 — Three.js scene + GLB loader with fallback ✅
- WebGL renderer with sRGB output, ambient + 2 directional lights.
- `OrbitControls` with damping, autorotate at speed 0.3, pause-on-interact, 5s resume timer.
- `GLTFLoader` → `./transformer.glb` → bounding-box recentre + fit-camera helper (`fitCameraToObject`).
- On 404 or load error: `buildProceduralTransformer()` builds the box body + 3 bushings + radiator + plinth from spec §5.2 verbatim.
- Loading overlay with percent/MB progress.

### Phase 3 — Hotspots ✅
- `components` object hardcoded from spec §5.3 (~line 716).
- Hotspots rendered as `THREE.Sprite` with **canvas-drawn radial-gradient textures** (green = healthy, amber = warning). Sized relative to model bounds (see Asset Reality Check item 3 above). `depthTest: false` + `renderOrder: 999` so they float over the mesh.
- Hover: HTML tooltip with name, vibration (mm/s), temp (°C), and a HEALTHY/WARNING badge. Positioned via 3D→2D projection through `Vector3.project(camera)`.
- Click: invokes `window.sendChatMessage('Tell me about ${label}')`.
- Subtle animation: warnings have a continuous gentle scale pulse; any hotspot can be force-pulsed for 2s via `window.pulseHotspot(key)` (used by Phase 5 mention detection).
- **Known limitation**: positions still match the procedural fallback. Re-anchor against the real BIM tree in Phase 7.

### Phase 4 — Agent network panel ✅
- Static SVG (`viewBox="0 0 220 360"`) with 5 vertically stacked nodes connected by arrows.
- Active state = `--accent` fill + white text + 800ms `agent-pulse` CSS keyframe (scale 1.0→1.04).
- `fireAgentSequence(agentList)` exposes the helper on `window`: 600ms inter-step gap, 4s hold, then fade. Cancels any prior in-flight sequence.

### Phase 5 — Chat UI + Anthropic streaming ✅
- Pre-seeded welcome bubble (spec §6.2, verbatim) — **UI-only**, not added to `conversationHistory` so the model never thinks it said something it didn't.
- API-key modal: shown on first load if `sessionStorage['anthropic_api_key']` is missing, validates `sk-ant-` prefix, on submit stores in `sessionStorage` only.
- `sendChatMessage(text)` flow (~line 1422):
  1. API-key check first (bails before rendering a user bubble if missing, preserving the typed text).
  2. Render user bubble + push to `conversationHistory`.
  3. Keyword routing (`AGENT_ROUTES` table — spec §4.3 verbatim) → `fireAgentSequence(...)`.
  4. Component-mention detection (`COMPONENT_LABELS`) → `pulseHotspot(key)` per match.
  5. POST to `https://api.anthropic.com/v1/messages` with `stream: true`. **Note the `anthropic-dangerous-direct-browser-access: 'true'` header — required for browser-origin requests, not in the spec.**
  6. Manual SSE parser: splits on `\n\n` frames, ignores everything except `content_block_delta` text deltas, appends to a streaming bubble.
- Error handling:
  - HTTP 401 → clear `sessionStorage` key + re-open the modal with "That key was rejected."
  - Any error → drop the dangling user turn so `conversationHistory` stays alternating-role-valid for the next send.
  - Empty completion → soft error, don't push an empty assistant turn (the API rejects them).
- Single-flight: a second send while a response is streaming is silently rejected.

### Phase 6 — Voice input ✅
- `webkitSpeechRecognition` wired to the mic button. Interim results populate the input field; final result is auto-sent via `sendChatMessage`.
- Recording state: red pulsing dot + amber border on the button.
- Silent degrade if the API is unavailable: button is disabled, no scolding banner. Friendly error messages for `no-speech`, `audio-capture`, `not-allowed`, etc.
- Dev hook: `window.__voiceInput = { recognition, start, stop }`.

### Phase 7 — Hotspot calibration on real BIM model ❌ (outstanding)
- `components[].position` values are still calibrated to the procedural fallback. On the real BIM, sprites render somewhere near the model's recentered origin and don't track any specific component.
- Approaches: either traverse `scene.traverse(o => o.name)` and anchor sprites to named meshes via `getWorldPosition`, or build a one-off dev-mode raycast picker to pick five points by hand.
- Spec §5.3 explicitly calls this out as expected.

### Phase 8 — End-to-end smoke test 🟡 (partial)
- Playwright snapshots confirm the page boots, layout is correct, the API-key modal appears, and the model starts loading.
- An end-to-end run with a valid API key (model loaded → "What is causing the vibration spike on Bushing B?" → agent sequence fires → hotspot pulses → AI response streams) has not yet been captured in `.playwright-mcp/`.

## Run / dev workflow

```bash
cd "/Users/541388/Library/CloudStorage/OneDrive-Cognizant/Documents/Projects/Digital Twin Transformer"
python3 -m http.server 8080
# open http://localhost:8080 in Chrome
```

No tests, lint, or build commands — single static file. The only verification loop is the smoke test in Phase 8 / spec §7 Step 6.

For console-driven smoke testing without typing:
- `window.fireAgentSequence(['orchestrator', 'sensor_query', 'anomaly_detection'])`
- `window.pulseHotspot('bushing_B')`
- `window.sendChatMessage('Tell me about Bushing B')`
- `window.__voiceInput.start()` / `.stop()`
- `window.__modelBounds` (after GLB load)
- `window.__transformerRoot`, `window.__isProcedural`

## Implementation details that aren't obvious from reading the code

- **`anthropic-dangerous-direct-browser-access: 'true'`** is mandatory for browser-origin calls to the Messages API. Without it the preflight fails CORS. This is not in the spec.
- **Welcome bubble is UI-only**, never sent to the API. Don't "fix" this by adding it to `conversationHistory` — the assistant will hallucinate continuity from a message it didn't author.
- **Dangling user-turn drop on error** preserves the Messages-API alternating-role invariant. If a request fails after the user bubble is pushed, the user turn is popped from `conversationHistory` so the next send doesn't double up.
- **Hotspot listeners are bound after `canvas` is declared** (`bindHotspotEvents(canvas)`, ~line 910) to avoid a temporal-dead-zone error — there was a previous run that hit this; the fix is intentional.
- **`MODEL_ID = 'claude-sonnet-4-6'`**, not the spec's stale `claude-sonnet-4-20250514`.

## Things easy to get wrong

- **No build step.** Three.js via `<script type="importmap">` from `cdn.jsdelivr.net` only. The acceptance criterion "runs from index.html" is non-negotiable.
- **The 5 agents are a keyword-routed visualization, not real orchestration.** One Anthropic call underneath. The `AGENT_ROUTES` table in `index.html` (and spec §4.3) is the single source of truth — do not let an LLM "decide" which agents fire.
- **Browser-side Anthropic key is intentional for this demo only.** Never persist beyond `sessionStorage`; never log. Cognizant SSO is explicitly Phase 2 in the spec (§9).
- **Stale model ID in spec.** §6.4 says `claude-sonnet-4-20250514`. The code uses `claude-sonnet-4-6`. Don't regress this.
- **Spec-vs-asset mismatch on the GLB.** Spec assumes a small transformer; we have a 183MB substation BIM. Fit-to-bounding-box camera is in; **hotspot positions are still procedural-fallback coords** until Phase 7.
- **Cognizant branding is mandatory** on this client-facing UI (`cognizant-branding` skill). `Cognizantlogo.png` is rendered in the header chip — do not invert, recolor, or replace it.

## File structure (current)

```
./
  CLAUDE.md                          (this file)
  Semco_DigitalTwin_BuildSpec.docx   (spec — authoritative)
  Cognizantlogo.png                  (header brandmark, top-left)
  transformer.glb                    (183MB BIM model)
  index.html                         (the entire app — Phases 1–6 done)
  .playwright-mcp/                   (test artifacts from MCP Playwright)
  README.md                          (not yet created)
```
