const { app } = require('@azure/functions');

// Configurable via SWA Application Settings. Defaults match the local-dev
// Azure OpenAI deployment so the function works out of the box if the key
// is the only secret you set.
const AZURE_ENDPOINT = process.env.AZURE_OPENAI_ENDPOINT
  || 'https://54138-molqi33i-eastus2.services.ai.azure.com/openai/v1';
const MODEL_ID = process.env.AZURE_OPENAI_MODEL || 'gpt-5.5';

// Spec §6.3 system prompt — kept server-side so it isn't shipped in the bundle.
const SYSTEM_PROMPT = [
  "You are a digital twin AI assistant for a Semco offshore substation transformer.",
  "You have access to live sensor data from 5 components. Respond concisely in 2-4 sentences.",
  "When asked about causes, explain likely engineering reasons for the sensor readings.",
  "When asked about fixes, give 3-5 numbered steps a maintenance engineer can follow on-site.",
  "When asked for predictions, give a timeframe and a confidence level (e.g. '85% confidence').",
  "Always reference specific component names and sensor values in your answers.",
  "",
  "Current sensor data:",
  "- Bushing A:    vibration 2.1 mm/s, temp 68 C  — healthy",
  "- Bushing B:    vibration 7.8 mm/s, temp 91 C  — WARNING",
  "- Bushing C:    vibration 3.2 mm/s, temp 72 C  — healthy",
  "- Main Coil:    vibration 5.4 mm/s, temp 84 C  — WARNING",
  "- Cooling Tank: vibration 1.2 mm/s, temp 55 C  — healthy",
].join('\n');

app.http('chat', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'chat',
  handler: async (request, context) => {
    if (!process.env.AZURE_OPENAI_KEY) {
      context.log.error('AZURE_OPENAI_KEY application setting is missing.');
      return {
        status: 500,
        jsonBody: { error: 'Server is not configured: AZURE_OPENAI_KEY missing.' },
      };
    }

    let payload;
    try {
      payload = await request.json();
    } catch (_) {
      return { status: 400, jsonBody: { error: 'Invalid JSON body.' } };
    }

    const userMessages = Array.isArray(payload?.messages) ? payload.messages : null;
    if (!userMessages || userMessages.length === 0) {
      return { status: 400, jsonBody: { error: '`messages` array is required.' } };
    }

    const maxTokens = Number.isFinite(payload?.max_completion_tokens)
      ? Math.min(payload.max_completion_tokens, 2048)
      : 1024;

    const body = JSON.stringify({
      model: MODEL_ID,
      max_completion_tokens: maxTokens,
      stream: true,
      messages: [{ role: 'system', content: SYSTEM_PROMPT }, ...userMessages],
    });

    let upstream;
    try {
      upstream = await fetch(AZURE_ENDPOINT.replace(/\/$/, '') + '/chat/completions', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'api-key': process.env.AZURE_OPENAI_KEY,
        },
        body,
      });
    } catch (err) {
      context.log.error('Upstream fetch failed:', err);
      return { status: 502, jsonBody: { error: 'Upstream Azure OpenAI request failed.' } };
    }

    if (!upstream.ok) {
      const errText = await upstream.text().catch(() => '');
      context.log.error(`Azure OpenAI HTTP ${upstream.status}: ${errText.slice(0, 500)}`);
      return {
        status: upstream.status,
        jsonBody: { error: `Azure OpenAI returned ${upstream.status}.`, detail: errText.slice(0, 500) },
      };
    }

    // Stream the SSE response straight back to the browser. The frontend
    // parser (in index.html) already understands OpenAI SSE chunks.
    return {
      status: 200,
      headers: {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache, no-transform',
        'x-accel-buffering': 'no',
      },
      body: upstream.body,
    };
  },
});
