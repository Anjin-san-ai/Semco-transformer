#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PORT="${PORT:-8080}"

if [[ ! -f "$ROOT/transformer.glb" ]]; then
  echo "Warning: transformer.glb not found in repo root."
  echo "Place the 183 MB model at: $ROOT/transformer.glb"
  echo "Production loads it from Azure Blob Storage; local dev needs the file."
fi

echo "Starting Semco Digital Twin at http://localhost:${PORT}"
echo "Press Ctrl+C to stop."
python3 -m http.server "$PORT"
