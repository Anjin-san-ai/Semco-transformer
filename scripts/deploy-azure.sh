#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

: "${AZURE_STORAGE_ACCOUNT:=transformersemco}"
: "${AZURE_STORAGE_CONTAINER:=models}"
: "${AZURE_STORAGE_RESOURCE_GROUP:=DSEI_DEV}"
: "${SWA_NAME:=Semcotransformer}"
: "${SWA_RESOURCE_GROUP:=DSEI_DEV}"
: "${AZURE_OPENAI_ENDPOINT:=https://54138-molqi33i-eastus2.services.ai.azure.com/openai/v1}"
: "${AZURE_OPENAI_MODEL:=gpt-5.5}"
: "${SWA_URL:=https://calm-smoke-050fb9a0f.7.azurestaticapps.net}"

echo "==> Semco Digital Twin — Azure deploy helper"
echo

if [[ -f "$ROOT/transformer.glb" ]]; then
  echo "==> Uploading transformer.glb to blob storage (${AZURE_STORAGE_ACCOUNT}/${AZURE_STORAGE_CONTAINER})..."
  ACCOUNT_KEY="$(az storage account keys list \
    --account-name "$AZURE_STORAGE_ACCOUNT" \
    --resource-group "$AZURE_STORAGE_RESOURCE_GROUP" \
    --query "[0].value" -o tsv)"
  az storage blob upload \
    --account-name "$AZURE_STORAGE_ACCOUNT" \
    --container-name "$AZURE_STORAGE_CONTAINER" \
    --name transformer.glb \
    --file "$ROOT/transformer.glb" \
    --auth-mode key \
    --account-key "$ACCOUNT_KEY" \
    --overwrite
  echo "    Blob URL: https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/${AZURE_STORAGE_CONTAINER}/transformer.glb"
else
  echo "==> Skipping GLB upload (transformer.glb not found locally)."
fi

echo
if [[ -z "${AZURE_OPENAI_KEY:-}" ]]; then
  echo "==> Skipping SWA app settings (AZURE_OPENAI_KEY not set)."
  echo "    Add AZURE_OPENAI_KEY to .env or export it, then re-run."
else
  echo "==> Setting Static Web App secrets on ${SWA_NAME}..."
  az staticwebapp appsettings set \
    --name "$SWA_NAME" \
    --resource-group "$SWA_RESOURCE_GROUP" \
    --setting-names \
      "AZURE_OPENAI_KEY=${AZURE_OPENAI_KEY}" \
      "AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}" \
      "AZURE_OPENAI_MODEL=${AZURE_OPENAI_MODEL}" \
    -o none
  echo "    App settings updated."
fi

echo
echo "==> Code deploy"
if git -C "$ROOT" diff --quiet && git -C "$ROOT" diff --cached --quiet; then
  echo "    No local code changes to push."
else
  echo "    You have uncommitted changes. Commit and push to main to trigger GitHub Actions:"
  echo "      cd \"$ROOT\""
  echo "      git add -A && git commit -m \"your message\""
  echo "      git push origin main"
fi

echo
echo "==> Live URL: ${SWA_URL}"
echo "    Verify: model loads from blob, chat uses POST /api/chat, mic works over HTTPS."
