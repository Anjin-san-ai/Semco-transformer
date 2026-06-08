# Semco Digital Twin — Quick Deploy

Public URL: **https://calm-smoke-050fb9a0f.7.azurestaticapps.net**

## 1. Clone and add the model

```bash
git clone https://github.com/Anjin-san-ai/Semco-transformer.git
cd Semco-transformer
cp /path/to/transformer.glb ./transformer.glb   # 183 MB, gitignored
```

## 2. Run locally

```bash
./scripts/local.sh
# open http://localhost:8080 in Chrome
```

On first chat message, paste your Azure OpenAI key when prompted (stored in `sessionStorage` for that tab only).

## 3. Configure secrets (one time)

```bash
cp scripts/setup-env.example .env
# edit .env — set AZURE_OPENAI_KEY
```

## 4. Deploy to Azure

```bash
./scripts/deploy-azure.sh
```

This uploads `transformer.glb` to blob storage and refreshes SWA app settings. Then push code changes:

```bash
git add -A && git commit -m "Update production config"
git push origin main
```

GitHub Actions deploys the Static Web App automatically on push to `main`.

## 5. Verify production

Open the live URL and check:

1. 3D model loads from `transformersemco.blob.core.windows.net`
2. Chat streams via `POST /api/chat`
3. Mic button works (HTTPS required)

## Prerequisites

- **Azure CLI** logged in (`az login`) — already configured on this machine
- **Git push access** to `Anjin-san-ai/Semco-transformer`
- **transformer.glb** locally for dev; production serves from Azure Blob Storage

See [README-DEPLOY.md](README-DEPLOY.md) for full architecture notes.
