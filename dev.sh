#!/usr/bin/env bash
# Modo desarrollo de Chroma: sirve el repo y regenera pkg/ (chroma.js incluido)
# ante cada cambio en src/, Cargo.toml o build.sh. Sin dependencias externas.
#
# Uso: ./dev.sh [puerto]   (default: 8123)
set -euo pipefail
cd "$(dirname "$0")"

PORT="${1:-8123}"

python3 -m http.server "$PORT" >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null' EXIT

echo "▶ http://localhost:$PORT/example/index.html"
echo "▶ Observando src/, Cargo.toml y build.sh (Ctrl+C para salir)"

fingerprint() {
    find src Cargo.toml build.sh -type f -print0 2>/dev/null \
        | sort -z \
        | xargs -0 md5sum 2>/dev/null \
        | md5sum
}

LAST=""
while true; do
    CURRENT="$(fingerprint)"
    if [[ "$CURRENT" != "$LAST" ]]; then
        if [[ -n "$LAST" ]]; then
            echo "⟳ Cambio detectado, rebuildeando…"
        fi
        if ./build.sh >/dev/null 2>&1; then
            echo "✔ pkg/ regenerado ($(date +%H:%M:%S)) — refrescá el navegador"
        else
            echo "✖ Build falló — corré ./build.sh para ver el error"
        fi
        LAST="$CURRENT"
    fi
    sleep 1
done
