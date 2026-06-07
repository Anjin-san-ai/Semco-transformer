# Deploying the Semco Digital Twin to Azure Static Web Apps

This app is structured for a one-click deploy to **Azure Static Web Apps (SWA)** with a managed Azure Function backing the chat API. Local development still works as-is with `python3 -m http.server` — the app auto-detects `localhost` and falls back to the direct Azure OpenAI call.

## Architecture in production

```
Browser (HTTPS via *.azurestaticapps.net)
  ├── index.html  (static, no API key in bundle)
  └── POST /api/chat
       └── Azure Function (Node 20, managed by SWA)
            └── POST {Azure OpenAI Foundry endpoint}/chat/completions
                 (api-key from AZURE_OPENAI_KEY app setting)
```

The Web Speech API (mic button) runs entirely in the browser — no backend.

## One-time prerequisites

1. **Git LFS** installed locally:
   ```bash
   brew install git-lfs
   git lfs install
   ```
   This repo's `.gitattributes` already tracks `*.glb` with LFS, so `transformer.glb` (183 MB) will be pushed via LFS automatically.

2. **Azure subscription** with permission to create Static Web Apps.

3. **GitHub repository** (private is fine).

## Deploy steps

### 1. Create the GitHub repo and push

```bash
cd "/Users/541388/Library/CloudStorage/OneDrive-Cognizant/Documents/Projects/Digital Twin Transformer"
git init
git add .gitattributes
git lfs track "*.glb"
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<your-org>/<your-repo>.git
git push -u origin main
```

GitHub LFS is free up to 1 GB storage / 1 GB bandwidth per month. Our GLB is 183 MB — well within the free tier.

### 2. Create the Static Web App in Azure

Easiest path is the **Azure Portal**:

1. Portal → "Static Web Apps" → **Create**.
2. **Subscription** / **Resource group**: your choice.
3. **Name**: e.g. `semco-digital-twin`.
4. **Plan type**: **Free** is fine for a demo (250 GB bandwidth, 100 GB storage).
5. **Region**: pick the closest to your users (e.g. `East US 2` to match the OpenAI deployment).
6. **Deployment details**:
   - Source: **GitHub**
   - Sign in & pick your org / repo / branch (`main`).
   - **Build presets**: **Custom**.
   - **App location**: `/`
   - **Api location**: `api`
   - **Output location**: leave blank.
7. **Review + create**.

Azure will:
- Add a deployment key to GitHub repo secrets as `AZURE_STATIC_WEB_APPS_API_TOKEN`.
- Create `.github/workflows/azure-static-web-apps-<random>.yml` (you can delete the one I shipped if Azure's generated one conflicts).
- Kick off the first deployment.

### 3. Set the chat API key as an Application Setting

The Function needs `AZURE_OPENAI_KEY` to call Azure OpenAI. Set it server-side so it never lives in the bundle:

**Portal:** open the Static Web App → **Configuration** → **Application settings** → **Add**:

| Name | Value |
|---|---|
| `AZURE_OPENAI_KEY` | _the api-key value of your gpt-5.5 deployment (paste at deploy time, do not check in)_ |
| `AZURE_OPENAI_ENDPOINT` | `https://<your-resource>-<region>.services.ai.azure.com/openai/v1` (optional) |
| `AZURE_OPENAI_MODEL` | `gpt-5.5` (optional — default) |

Save. The Function picks it up on the next request — no redeploy needed.

**CLI alternative:**
```bash
az staticwebapp appsettings set \
  --name semco-digital-twin \
  --setting-names \
    AZURE_OPENAI_KEY="<paste-your-key>" \
    AZURE_OPENAI_MODEL="gpt-5.5"
```

### 4. Hit the URL

Azure gives you a default URL like `https://semco-digital-twin.azurestaticapps.net`. Open it. The app should:

- Load the 3D model (via Git LFS from the deployment).
- Stream chat responses through `/api/chat`.
- Accept voice input via the mic button (HTTPS is required for Web Speech — SWA gives it for free).

## Verifying the deployment

Open the SWA URL and:

1. Wait for the substation model to load (progress bar visible).
2. Click a hotspot or type "What is wrong with Bushing B?". The response should stream in just like locally.
3. Open DevTools → Network → confirm the chat POST goes to `/api/chat` (not directly to Azure OpenAI).
4. Open DevTools → Console → no errors.
5. Mic button → grants permission once → speak a question → it auto-sends.

## Local development against the Function (optional)

If you want to test `/api/chat` locally before deploying, install the SWA CLI and Functions Core Tools:

```bash
npm install -g @azure/static-web-apps-cli azure-functions-core-tools@4
cd "/path/to/Digital Twin Transformer"
cp api/local.settings.json.example api/local.settings.json
# Edit api/local.settings.json — paste the key you got from the test-keys folder.
cd api && npm install && cd ..
swa start ./ --api-location ./api
```

Open `http://localhost:4280`. The SWA CLI proxies `/api/*` to a local Functions host.

Or — keep using `python3 -m http.server 8081`. The frontend auto-detects `localhost` and calls Azure OpenAI directly with the inline key, so you don't need the Function locally.

## Costs (rough)

- **SWA Free tier**: $0/mo. 100 GB storage, 250 GB bandwidth, custom domains, managed Functions included.
- **Azure OpenAI**: pay per token. gpt-5.5 is ~$2.50 / 1M input tokens, ~$10 / 1M output tokens. A typical demo chat is well under a cent.
- **GitHub LFS**: free up to 1 GB storage + 1 GB bandwidth / month. Each model load is 183 MB, so heavy usage may exceed the free tier — switch to Azure Blob Storage if that happens.

## Things to know

- **The hardcoded key in `index.html` is for localhost-only**. The dual-mode logic in `streamChat()` short-circuits the direct call on any non-localhost origin, so it can't be reached from the deployed site. Still, if you'd rather not have the key in the repo at all, replace `AZURE_API_KEY` with a placeholder and run a local-only `.env` setup.
- **Streaming**: the Function pipes the upstream SSE straight back to the browser. The frontend parser is byte-identical to the localhost path, so streaming UX is the same in prod.
- **CORS**: not an issue. `/api/chat` is same-origin with `index.html` on the SWA URL.
- **CSP**: not set. The app uses inline scripts/styles and a CDN (jsdelivr for Three.js) — adding a strict CSP would require either hashing the inline blocks or moving them out. Skip unless you have a hardening requirement.
