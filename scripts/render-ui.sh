#!/bin/bash
# Genera capturas offscreen de las pantallas de Pik en dist/ui (datos de muestra aislados, sin permisos).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist/ui}"
DATA="$(mktemp -d)"
scripts/build-app.sh --debug >/dev/null
PIK_DATA_DIR="$DATA" PIK_DEFAULTS_SUITE="com.pik.render" dist/Pik.app/Contents/MacOS/Pik --render-ui "$OUT"
defaults delete com.pik.render 2>/dev/null || true
rm -rf "$DATA"
