#!/usr/bin/env bash
# Chroma build: generates pkg/ and leaves the module auto-initialized,
# so it can be imported directly without calling init():
#   import { hookState, render, h, Fragment } from "./pkg/chroma.js";
#
# Also syncs pkg/ -> Chroma-CLI/pkg/ (sibling repo) for the standalone CLI bundle.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHROMA_CLI_PKG="$ROOT_DIR/Chroma-CLI/pkg"

cd "$SCRIPT_DIR"

wasm-pack build --target web --release "$@"

# Auto-init: importing the module loads and instantiates the .wasm by itself.
# Append before the minify step so __wbg_init is renamed consistently.
cat >> pkg/chroma.js << 'EOF'

await __wbg_init();
EOF

# Minify with the engine binary of the Chroma CLI (no Node, no npm): CHROMA_ENGINE_BIN, the release build of
# Chroma-Server in this workspace, or ~/.chroma/bin/engine (must be a version that has `engine minify`).
ENGINE_BIN="${CHROMA_ENGINE_BIN:-}"
if [ -z "$ENGINE_BIN" ] || [ ! -x "$ENGINE_BIN" ]; then
    for candidate in \
        "$ROOT_DIR/Chroma-Server/target/release/engine" \
        "${CHROMA_HOME:-$HOME/.chroma}/bin/engine"; do
        if [ -x "$candidate" ]; then ENGINE_BIN="$candidate"; break; fi
    done
fi
[ -x "$ENGINE_BIN" ] || { echo "engine binary not found: run 'chroma install' or build Chroma-Server (cargo build --release)" >&2; exit 1; }
"$ENGINE_BIN" minify pkg/chroma.js --out pkg/chroma.js

mkdir -p "$CHROMA_CLI_PKG"
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
        --exclude '.git' \
        --exclude '.gitignore' \
        --exclude '.env' \
        --exclude '.env.*' \
        "$SCRIPT_DIR/pkg/" "$CHROMA_CLI_PKG/"
else
    rm -rf "$CHROMA_CLI_PKG"
    mkdir -p "$CHROMA_CLI_PKG"
    cp -a "$SCRIPT_DIR/pkg/." "$CHROMA_CLI_PKG/"
fi

echo "OK: pkg/ listo (auto-init incluido)"
echo "OK: Chroma-CLI/pkg/ sincronizado"
