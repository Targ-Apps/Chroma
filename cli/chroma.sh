#!/usr/bin/env bash
# Chroma CLI (macOS/Linux) — provisions the toolchain and scaffolds/builds
# Chroma apps. Run `./chroma.sh install` once from a checkout of the repo;
# afterwards the `chroma` command is available system-wide.
set -euo pipefail

# ── Path resolution ──────────────────────────────────────────────────────────
# Follows symlinks so the copy installed at ~/.chroma/bin/chroma behaves the
# same as running cli/chroma.sh straight from the cloned repo.
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$DIR/$SCRIPT_SOURCE"
done
CLI_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
REPO_DIR="$(cd -P "$CLI_DIR/.." >/dev/null 2>&1 && pwd)"

CHROMA_HOME="${CHROMA_HOME:-$HOME/.chroma}"
CHROMA_BIN="$CHROMA_HOME/bin"
CHROMA_TEMPLATES="$CHROMA_HOME/templates"
CHROMA_PLUGINS="$CHROMA_HOME/plugins"
CHROMA_ENGINE_SRC="$CHROMA_HOME/engine-src"
CHROMA_ENGINE_BIN="$CHROMA_BIN/engine"
CHROMA_DESKTOP_BIN="$CHROMA_BIN/chroma-desktop"
WORKSPACE_ROOT="$(cd -P "$CLI_DIR/.." >/dev/null 2>&1 && pwd)"
# PID of background engine during `chroma dev` + desktop; must be global so EXIT trap can read it after launch_dev_with_desktop returns.
CHROMA_DEV_ENGINE_PID=0

# ── Logger (NestJS ConsoleLogger layout) ─────────────────────────────────────
# [Chroma] {pid}  - {timestamp} {LEVEL pad 7} [{Context}] {message}
# Timestamp matches Date#toLocaleString() en-US (e.g. 08/29/2026, 12:35:00 AM).
# Colors (TTY only): LOG green, ERROR red, WARN yellow, DEBUG magenta,
# VERBOSE cyan; dim timestamp; yellow context. ERROR/WARN → stderr.
c_reset=$'\033[0m'
c_green=$'\033[32m'
c_yellow=$'\033[33m'
c_red=$'\033[31m'
c_magenta=$'\033[95m'
c_cyan=$'\033[96m'
c_dim=$'\033[2m'

LOG_CTX=Cli

# Max verbosity (0=error … 4=verbose). Default `log` matches engine `CHROMA_LOG_LEVEL`.
_chroma_max_verbosity() {
    case "${CHROMA_LOG_LEVEL:-log}" in
        error|ERROR) echo 0 ;;
        warn|WARN) echo 1 ;;
        log|LOG) echo 2 ;;
        debug|DEBUG) echo 3 ;;
        verbose|VERBOSE) echo 4 ;;
        *) echo 2 ;;
    esac
}

_chroma_level_verbosity() {
    case "$1" in
        ERROR) echo 0 ;;
        WARN) echo 1 ;;
        LOG) echo 2 ;;
        DEBUG) echo 3 ;;
        VERBOSE) echo 4 ;;
        *) echo 2 ;;
    esac
}

chroma_timestamp() {
    LC_ALL=C date '+%m/%d/%Y, %I:%M:%S %p'
}

_chroma_level_color() {
    case "$1" in
        LOG) printf '%s' "$c_green" ;;
        ERROR) printf '%s' "$c_red" ;;
        WARN) printf '%s' "$c_yellow" ;;
        DEBUG) printf '%s' "$c_magenta" ;;
        VERBOSE) printf '%s' "$c_cyan" ;;
        *) printf '%s' "$c_green" ;;
    esac
}

# _chroma_log LEVEL CONTEXT MESSAGE
_chroma_log() {
    local level="$1" context="$2" message="$3"
    local max min
    max="$(_chroma_max_verbosity)"
    min="$(_chroma_level_verbosity "$level")"
    if [ "$min" -gt "$max" ]; then
        return 0
    fi

    local fd=1
    case "$level" in
        ERROR|WARN) fd=2 ;;
    esac

    local colorize=0
    if [ "$fd" -eq 2 ]; then
        [ -t 2 ] && colorize=1
    else
        [ -t 1 ] && colorize=1
    fi

    local ts padded prefix ts_out level_out ctx_out msg_out lc
    ts="$(chroma_timestamp)"
    padded="$(printf '%7s' "$level")"
    prefix="[Chroma] $$  - "

    if [ "$colorize" -eq 1 ]; then
        lc="$(_chroma_level_color "$level")"
        ts_out="${c_dim}${ts}${c_reset}"
        level_out="${lc}${padded}${c_reset}"
        ctx_out="${c_yellow}[${context}]${c_reset}"
        msg_out="${lc}${message}${c_reset}"
    else
        ts_out="$ts"
        level_out="$padded"
        ctx_out="[${context}]"
        msg_out="$message"
    fi

    if [ "$fd" -eq 2 ]; then
        printf '%s%s %s %s %s\n' "$prefix" "$ts_out" "$level_out" "$ctx_out" "$msg_out" >&2
    else
        printf '%s%s %s %s %s\n' "$prefix" "$ts_out" "$level_out" "$ctx_out" "$msg_out"
    fi
}

log_log()     { _chroma_log LOG     "${1:-$LOG_CTX}" "${2-}"; }
log_error()   { _chroma_log ERROR   "${1:-$LOG_CTX}" "${2-}"; }
log_warn()    { _chroma_log WARN    "${1:-$LOG_CTX}" "${2-}"; }
log_debug()   { _chroma_log DEBUG   "${1:-$LOG_CTX}" "${2-}"; }
log_verbose() { _chroma_log VERBOSE "${1:-$LOG_CTX}" "${2-}"; }

info() { log_log  "$LOG_CTX" "$1"; }
ok()   { log_log  "$LOG_CTX" "$1"; }
warn() { log_warn "$LOG_CTX" "$1"; }
err()  { log_error "$LOG_CTX" "$1"; }
die()  { log_error "$LOG_CTX" "$1"; exit 1; }

# Canonical version: Chroma/VERSION (monorepo), CLI_DIR/VERSION (standalone
# package), or $CHROMA_HOME/VERSION after `chroma install`.
chroma_version_raw() {
    local vf
    for vf in \
        "$REPO_DIR/VERSION" \
        "$CLI_DIR/VERSION" \
        "$CHROMA_HOME/VERSION"; do
        if [ -f "$vf" ]; then
            tr -d '[:space:]' < "$vf"
            return 0
        fi
    done
    echo "unknown"
}

chroma_version() {
    echo "Chroma v$(chroma_version_raw)"
}

chroma_show_startup() {
    printf '%s\n' "$(chroma_version)"
}

install_version_file() {
    local version_src=""
    if [ -f "$REPO_DIR/VERSION" ]; then
        version_src="$REPO_DIR/VERSION"
    elif [ -f "$CLI_DIR/VERSION" ]; then
        version_src="$CLI_DIR/VERSION"
    fi
    if [ -n "$version_src" ]; then
        cp "$version_src" "$CHROMA_HOME/VERSION"
    fi
}

usage() {
    cat <<'EOF'
NAME
    chroma - CLI for the Chroma WASM engine

USAGE
    chroma <command> [options]

COMMANDS
    install [--no-rebase-root]
        Provisions the local toolchain (Rust, wasm32-unknown-unknown target,
        wasm-pack, dev-server binary) and installs the `chroma` command on
        the user's PATH. Run from a checkout of the repo (cli/chroma.sh).

        By default, every run wipes $CHROMA_HOME and rebuilds it from
        scratch (a clean reinstall). Pass --no-rebase-root to update in
        place instead, without deleting $CHROMA_HOME first.

    new <name> [--template static|dynamic|standard]
        Scaffolds a new app into ./<name>.
        --template   static (default) | dynamic | standard

    dev [--port <n>] [--no-desktop]
        Serves the current app at http://localhost:<port>. Requires
        chroma.json in the working directory. Default port: chroma.json's
        dev.port, or 4173.

        Browser dev enables hot-reload (full page refresh on .chr and
        related source changes). Chroma Desktop develop mode disables
        reload (CHROMA_DEV_RELOAD=0, engine --no-reload).

        Dynamic apps with dev.desktop=true (the dynamic template default)
        also launch Chroma Desktop in develop mode — the project opens
        directly for testing, without the import library menu. Pass
        --no-desktop to serve in the browser only.

    build
        Compiles and packages the current app per chroma.json. Output goes
        to chroma.json's outDir (default: dist/).

    validate [--strict] [--no-schema]
        Checks chroma.json (and optional chroma-fs.json / plugin manifests)
        for schema and on-disk consistency before dev or build. Uses JSON
        Schema from $CHROMA_SCHEMAS, the CLI schemas/ bundle, the monorepo
        targ-apps-docs catalog, or structural checks only when no schema
        catalog is found.

    fs init
        Create chroma-fs.json for the current app (backend defaults depend
        on static vs dynamic mode in chroma.json).

    fs link
        Build Chroma-Fs from the workspace and link @chroma/fs into the
        current project (npm install file:...).

    add <lib-id> [--list] [--force] [--dry-run] [--registry <path>]
        Vendor a registry entry (Chroma/cli/legacy-libs/registry.json) into the
        current app. First-party plugins: prefer install + new/copy; add is for
        monorepo workspace packages. CDN/UMD libs use registry files[], not
        plugins/. Run chroma add --help for details.

    help, --help, -h
        Show this message.

    --version, -v
        Print the CLI version.

TEMPLATES
    static
        Flat HTML/JS files, no bundler, no module graph. `build` minifies
        the source files as written; the engine runtime (pkg/) is vendored,
        never recompiled, and its .wasm is inlined as base64 into a single
        minified chroma.js — no .wasm file ships in the output.

    dynamic
        ES modules across multiple files. `build` bundles the module graph
        with esbuild and, when engine.rebuildWasm is true in chroma.json,
        recompiles the engine to WASM before packaging the output.

    standard
        Like dynamic, but includes a full Chroma-Fs file explorer demo,
        chroma-fs.json, plugins/loader.js, and npm scripts fs:init / fs:link.
        Opens Chroma Desktop in develop mode by default (dev.desktop: true).

    All templates only vendor a `pkg/` directory (the compiled engine:
    chroma.js + chroma_bg.wasm) at the project root — that's all a project
    needs at runtime. `dev` and `build` serve files through the `engine`
    binary installed at $CHROMA_HOME/bin; no server binary is copied into
    the project.

ENVIRONMENT
    CHROMA_DEV_RELOAD
        1 (default for browser `chroma dev`) enables engine hot-reload.
        Set to 0 to disable (used automatically for Chroma Desktop develop).

    CHROMA_HOME
        Install root (default: ~/.chroma). Holds bin/ (chroma, engine),
        engine-src/ (the compiled engine — plus its Rust source, when
        installed from a full Chroma checkout, for recompiling) and
        templates/ (static, dynamic, standard), and plugins/ (chroma-fs).

EXIT STATUS
    0 on success, 1 on usage error (missing chroma.json, invalid template,
    missing dependency, existing directory, etc.).
EOF
}

# ── JSON helpers (chroma.json is a small, fixed schema we control: jq is
# used when available, falling back to a grep/sed extraction otherwise) ──────
json_field() {
    local file="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -er --arg k "$key" '.. | objects | select(has($k)) | .[$k]' "$file" 2>/dev/null | head -1
        return 0
    fi
    grep -oE '"'"$key"'" *: *("[^"]*"|[0-9.]+|true|false)' "$file" 2>/dev/null | head -1 \
        | sed -E 's/.*: *"?([^"]*)"?$/\1/'
}

json_array() {
    local file="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -er --arg k "$key" '.. | objects | select(has($k)) | .[$k][]' "$file" 2>/dev/null
        return 0
    fi
    grep -oE '"'"$key"'" *: *\[[^]]*\]' "$file" 2>/dev/null | grep -oE '"[^"]*"' | tail -n +2 | tr -d '"'
}

require_node() {
    command -v node >/dev/null 2>&1 || die "Node.js is required for this step (bundling/minifying). Install it from https://nodejs.org and try again."
    command -v npx >/dev/null 2>&1 || die "npx not found (ships with npm). Install/update Node.js."
}

# Chroma app source uses .chr (ESM JavaScript). esbuild has no default loader for it.
readonly ESBUILD_CHR_LOADER=( --loader:.chr=js )

run_esbuild() {
    npx --yes esbuild "${ESBUILD_CHR_LOADER[@]}" "$@"
}

warn_legacy_js_in_src() {
    [ -d src ] || return 0
    local f
    while IFS= read -r -d '' f; do
        warn "Legacy .js under src/: $f — use .chr for Chroma app source (see docs/chroma/chr-format)"
    done < <(find src -name '*.js' -type f -print0 2>/dev/null)
}

# Generates jsconfig.json if the project doesn't already have one, so
# VSCode-family editors resolve types from pkg/chroma.d.ts (hover docs,
# autocomplete) without any manual setup. Never overwrites an existing file.
ensure_jsconfig() {
    [ -f "jsconfig.json" ] && return 0
    info "jsconfig.json not found, generating one for editor IntelliSense..."
    cat > jsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "allowJs": true,
    "checkJs": false
  },
  "include": ["**/*.js", "**/*.chr"],
  "exclude": ["node_modules", "dist"]
}
EOF
}

# Minifies HTML (strips comments and whitespace) and, optionally, replaces a
# literal text reference (used to point <script src> at the bundle output).
minify_html() {
    local src="$1" dst="$2" from="${3:-}" to="${4:-}"
    require_node
    mkdir -p "$(dirname "$dst")"
    node -e '
        const fs = require("fs");
        const [src, dst, from, to] = process.argv.slice(1);
        let html = fs.readFileSync(src, "utf8");
        if (from) html = html.split(from).join(to);
        html = html.replace(/<!--[\s\S]*?-->/g, "");
        html = html.replace(/>\s+</g, "><");
        html = html.replace(/[ \t]+/g, " ");
        html = html.replace(/\n\s*/g, "");
        fs.writeFileSync(dst, html.trim());
    ' "$src" "$dst" "$from" "$to"
}

# Inlines chroma_bg.wasm as base64 directly into chroma.js (replacing the
# `new URL('chroma_bg.wasm', import.meta.url)` + fetch path with an embedded
# byte array) and minifies the result. Used by static builds so the shipped
# engine is a single JS file — no .wasm request, no separate artifact.
inline_wasm_js() {
    local vendor_dir="$1" outdir="$2"
    require_node
    mkdir -p "$outdir"
    local inline_script; inline_script="$(mktemp --suffix=.js)"
    local inlined; inlined="$(mktemp --suffix=.js)"
    cat > "$inline_script" << 'NODE_EOF'
const fs = require("fs");
const path = require("path");
const [vendorDir, outFile] = process.argv.slice(2);
const jsSrc = path.join(vendorDir, "chroma.js");
const wasmSrc = path.join(vendorDir, "chroma_bg.wasm");
let js = fs.readFileSync(jsSrc, "utf8");
const wasmB64 = fs.readFileSync(wasmSrc).toString("base64");
const marker = "new URL('chroma_bg.wasm', import.meta.url)";
if (!js.includes(marker)) {
    throw new Error("chroma.js: wasm URL marker not found, cannot inline wasm");
}
const inline = "Uint8Array.from(atob('" + wasmB64 + "'), c => c.charCodeAt(0))";
js = js.split(marker).join(inline);
fs.writeFileSync(outFile, js);
NODE_EOF
    node "$inline_script" "$vendor_dir" "$inlined"
    rm -f "$inline_script"
    npx --yes esbuild "$inlined" --minify --outfile="$outdir/chroma.js"
    rm -f "$inlined"
}

# VCS, ignore files, and secrets must never ship in dist/ or release archives.
readonly -a DIST_ARCHIVE_EXCLUDES=(
    ".git" ".git/*" "*/.git" "*/.git/*"
    ".gitignore" "*/.gitignore"
    ".env" ".env.*" "*/.env" "*/.env.*"
)

strip_dist_metadata() {
    local dir="$1"
    find "$dir" -name '.git' -type d -prune -exec rm -rf {} + 2>/dev/null || true
    find "$dir" -name '.gitignore' -type f -delete 2>/dev/null || true
    find "$dir" -name '.env' -o -name '.env.*' -type f -delete 2>/dev/null || true
}

package_dir() {
    local dir="$1" out="$2"
    strip_dist_metadata "$dir"
    if command -v zip >/dev/null 2>&1; then
        local -a zip_x=()
        local pat
        for pat in "${DIST_ARCHIVE_EXCLUDES[@]}"; do
            zip_x+=( -x "$pat" )
        done
        ( cd "$dir" && zip -qr "../$(basename "$out").zip" . "${zip_x[@]}" )
        echo "$out.zip"
    else
        tar --exclude='.git' --exclude='.gitignore' --exclude='.env' --exclude='.env.*' \
            -czf "$out.tar.gz" -C "$dir" .
        echo "$out.tar.gz"
    fi
}

resolve_chroma_fs_src() {
    local candidate
    for candidate in \
        "$WORKSPACE_ROOT/Chroma-Fs" \
        "$REPO_DIR/../Chroma-Fs" \
        "$CLI_DIR/../Chroma-Fs"; do
        if [ -f "$candidate/package.json" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

resolve_chroma_style_src() {
    local candidate
    for candidate in \
        "$WORKSPACE_ROOT/Chroma-Style" \
        "$REPO_DIR/../Chroma-Style" \
        "$CLI_DIR/../../Chroma-Style"; do
        if [ -f "$candidate/chroma.plugin.json" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

resolve_plugin_src() {
    local plugin="$1"
    local top_level=""
    case "$plugin" in
        chroma-style) top_level="$WORKSPACE_ROOT/Chroma-Style" ;;
        chroma-router) top_level="$WORKSPACE_ROOT/Chroma-Router" ;;
        chroma-t2t) top_level="$WORKSPACE_ROOT/Chroma-t2t" ;;
    esac
    if [ -n "$top_level" ] && [ -f "$top_level/chroma.plugin.json" ]; then
        echo "$top_level"
        return 0
    fi
    if [ -d "$CLI_DIR/plugins/$plugin" ]; then
        echo "$CLI_DIR/plugins/$plugin"
        return 0
    fi
    return 1
}

install_plugins() {
    mkdir -p "$CHROMA_PLUGINS"
    local saved="$LOG_CTX"
    local fs_src
    if fs_src="$(resolve_chroma_fs_src)"; then
        LOG_CTX=Fs
        info "Building Chroma-Fs plugin from $fs_src..."
        if ( cd "$fs_src" && npm install --silent && npm run build ); then
            rm -rf "$CHROMA_PLUGINS/chroma-fs"
            mkdir -p "$CHROMA_PLUGINS/chroma-fs"
            cp "$fs_src/package.json" "$CHROMA_PLUGINS/chroma-fs/"
            cp -R "$fs_src/dist/." "$CHROMA_PLUGINS/chroma-fs/"
            [ -f "$fs_src/chroma.plugin.json" ] && cp "$fs_src/chroma.plugin.json" "$CHROMA_PLUGINS/chroma-fs/"
            ok "Chroma-Fs plugin ready at $CHROMA_PLUGINS/chroma-fs"
        else
            warn "Chroma-Fs build failed — plugin install skipped."
        fi
    elif [ -d "$CLI_DIR/plugins/chroma-fs" ]; then
        LOG_CTX=Fs
        rm -rf "$CHROMA_PLUGINS/chroma-fs"
        cp -R "$CLI_DIR/plugins/chroma-fs" "$CHROMA_PLUGINS/"
        ok "Chroma-Fs plugin copied from $CLI_DIR/plugins/chroma-fs"
    else
        LOG_CTX=Fs
        warn "Chroma-Fs source not found — plugin install skipped."
    fi

    LOG_CTX=Install
    for plugin in chroma-style chroma-router chroma-t2t; do
        local src
        if src="$(resolve_plugin_src "$plugin")"; then
            rm -rf "$CHROMA_PLUGINS/$plugin"
            cp -R "$src" "$CHROMA_PLUGINS/$plugin"
            ok "$plugin copied from $src"
        fi
    done
    LOG_CTX="$saved"
}

install_desktop() {
    local saved="$LOG_CTX"
    LOG_CTX=Desktop
    local desktop_dir candidate
    for candidate in \
        "$WORKSPACE_ROOT/Chroma-Desktop" \
        "$REPO_DIR/../Chroma-Desktop" \
        "$CLI_DIR/../Chroma-Desktop"; do
        if [ -f "$candidate/Cargo.toml" ]; then
            desktop_dir="$candidate"
            break
        fi
    done

    if [ -n "${desktop_dir:-}" ]; then
        info "Building Chroma Desktop for develop mode..."
        if ( cd "$desktop_dir" && cargo build -q 2>/dev/null ); then
            if [ -x "$desktop_dir/target/debug/chroma-desktop" ]; then
                cp "$desktop_dir/target/debug/chroma-desktop" "$CHROMA_DESKTOP_BIN"
                chmod +x "$CHROMA_DESKTOP_BIN"
                ok "chroma-desktop ready at $CHROMA_DESKTOP_BIN"
                LOG_CTX="$saved"
                return 0
            fi
        fi
        warn "Chroma Desktop build failed — develop mode will require a manual build."
    elif [ -x "$CLI_DIR/desktop/chroma-desktop" ]; then
        cp "$CLI_DIR/desktop/chroma-desktop" "$CHROMA_DESKTOP_BIN"
        chmod +x "$CHROMA_DESKTOP_BIN"
        ok "chroma-desktop ready at $CHROMA_DESKTOP_BIN"
    fi
    LOG_CTX="$saved"
}

resolve_desktop_bin() {
    if [ -x "$CHROMA_DESKTOP_BIN" ]; then
        echo "$CHROMA_DESKTOP_BIN"
        return 0
    fi
    local desktop_dir
    for desktop_dir in \
        "$WORKSPACE_ROOT/Chroma-Desktop" \
        "$REPO_DIR/../Chroma-Desktop" \
        "$CLI_DIR/../Chroma-Desktop"; do
        if [ -x "$desktop_dir/target/debug/chroma-desktop" ]; then
            echo "$desktop_dir/target/debug/chroma-desktop"
            return 0
        fi
        if [ -x "$desktop_dir/target/release/chroma-desktop" ]; then
            echo "$desktop_dir/target/release/chroma-desktop"
            return 0
        fi
    done
    if command -v chroma-desktop >/dev/null 2>&1; then
        command -v chroma-desktop
        return 0
    fi
    return 1
}

vendor_plugins() {
    local project="$1"
    local plugins plugin
    plugins="$(json_array "$project/chroma.json" plugins)"
    [ -n "$plugins" ] || return 0

    for plugin in $plugins; do
        [ -d "$CHROMA_PLUGINS/$plugin" ] || die "Plugin '$plugin' not found at $CHROMA_PLUGINS/$plugin. Run 'chroma install'."
        mkdir -p "$project/plugins"
        cp -R "$CHROMA_PLUGINS/$plugin" "$project/plugins/$plugin"
    done
}

# ── install ──────────────────────────────────────────────────────────────────
cmd_install() {
    LOG_CTX=Install
    local no_rebase_root=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-rebase-root) no_rebase_root=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    # Two ways to run this script: from a Chroma checkout (cli/chroma.sh,
    # with Cargo.toml/src/ next to cli/ — can build and rebuild from source)
    # or from a standalone Chroma-CLI package (chroma.sh at the package
    # root, with a prebuilt pkg/ next to it and no Rust source at all).
    local monorepo_mode=false
    [ -f "$REPO_DIR/Cargo.toml" ] && monorepo_mode=true
    if [ "$monorepo_mode" = false ] && [ ! -d "$CLI_DIR/pkg" ]; then
        die "Neither a Chroma checkout (Cargo.toml next to cli/) nor a prebuilt pkg/ next to this script was found."
    fi

    if [ "$no_rebase_root" = false ] && [ -d "$CHROMA_HOME" ]; then
        info "Wiping $CHROMA_HOME for a clean reinstall (use --no-rebase-root to update in place)..."
        rm -rf "$CHROMA_HOME"
    fi

    if command -v node >/dev/null 2>&1; then
        ok "Node.js detected ($(node --version))"
    else
        warn "Node.js not found. Required for 'chroma build' (bundling/minifying via esbuild). Install it from https://nodejs.org."
    fi

    rm -rf "$CHROMA_ENGINE_SRC"
    mkdir -p "$CHROMA_ENGINE_SRC/pkg"

    if [ "$monorepo_mode" = true ]; then
        info "Checking Rust..."
        if ! command -v cargo >/dev/null 2>&1; then
            info "Installing Rust (rustup)..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            # shellcheck disable=SC1090
            source "$HOME/.cargo/env"
        else
            ok "Rust already installed ($(rustc --version))"
        fi

        info "Checking wasm32-unknown-unknown target..."
        if ! rustup target list --installed 2>/dev/null | grep -q wasm32-unknown-unknown; then
            rustup target add wasm32-unknown-unknown
        fi
        ok "wasm32-unknown-unknown target ready"

        info "Checking wasm-pack..."
        if ! command -v wasm-pack >/dev/null 2>&1; then
            info "Installing wasm-pack..."
            curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh -s -- -y
        else
            ok "wasm-pack already installed ($(wasm-pack --version))"
        fi

        info "Vendoring the engine source into $CHROMA_ENGINE_SRC..."
        mkdir -p "$CHROMA_ENGINE_SRC/src"
        cp -R "$REPO_DIR/src/." "$CHROMA_ENGINE_SRC/src/"
        cp "$REPO_DIR/Cargo.toml" "$CHROMA_ENGINE_SRC/Cargo.toml"
        cp "$REPO_DIR/build.sh" "$CHROMA_ENGINE_SRC/build.sh"
        chmod +x "$CHROMA_ENGINE_SRC/build.sh"
        [ -f "$REPO_DIR/Cargo.lock" ] && cp "$REPO_DIR/Cargo.lock" "$CHROMA_ENGINE_SRC/Cargo.lock"

        if [ ! -d "$REPO_DIR/pkg" ]; then
            info "pkg/ not built yet, building it (./build.sh)..."
            ( cd "$REPO_DIR" && ./build.sh )
        fi
        cp -R "$REPO_DIR/pkg/." "$CHROMA_ENGINE_SRC/pkg/"
        ok "Engine source + compiled pkg ready at $CHROMA_ENGINE_SRC"
    else
        info "Installing the prebuilt engine into $CHROMA_ENGINE_SRC..."
        cp -R "$CLI_DIR/pkg/." "$CHROMA_ENGINE_SRC/pkg/"
        ok "Prebuilt engine ready at $CHROMA_ENGINE_SRC (no Rust source shipped — dynamic apps' rebuildWasm is unavailable)"
    fi

    info "Installing the dev-server binary (engine)..."
    [ -f "$CLI_DIR/engine-server/engine" ] || die "Prebuilt binary not found at $CLI_DIR/engine-server/engine."
    mkdir -p "$CHROMA_BIN"
    cp "$CLI_DIR/engine-server/engine" "$CHROMA_ENGINE_BIN"
    chmod +x "$CHROMA_ENGINE_BIN"
    ok "engine binary ready at $CHROMA_ENGINE_BIN"

    info "Copying templates..."
    mkdir -p "$CHROMA_TEMPLATES"
    cp -R "$CLI_DIR/examples/." "$CHROMA_TEMPLATES/"
    ok "Templates ready at $CHROMA_TEMPLATES (static, dynamic, standard)"

    if [ -d "$CLI_DIR/schemas" ]; then
        mkdir -p "$CHROMA_HOME/schemas"
        cp -R "$CLI_DIR/schemas/." "$CHROMA_HOME/schemas/"
        ok "JSON Schemas installed at $CHROMA_HOME/schemas (for chroma validate)"
    fi

    if [ -f "$CLI_DIR/legacy-libs/registry.json" ]; then
        mkdir -p "$CHROMA_HOME/legacy-libs"
        cp "$CLI_DIR/legacy-libs/registry.json" "$CHROMA_HOME/legacy-libs/registry.json"
        [ -f "$CLI_DIR/legacy-libs/registry.schema.json" ] && \
            cp "$CLI_DIR/legacy-libs/registry.schema.json" "$CHROMA_HOME/legacy-libs/registry.schema.json"
        ok "Legacy library registry installed at $CHROMA_HOME/legacy-libs/registry.json"
    fi

    install_plugins
    install_desktop

    info "Installing the 'chroma' command..."
    cp "$SCRIPT_SOURCE" "$CHROMA_BIN/chroma"
    chmod +x "$CHROMA_BIN/chroma"
    ok "chroma installed at $CHROMA_BIN/chroma"

    install_version_file

    add_to_path

    echo
    ok "Chroma environment ready ($(chroma_version))."
    echo "  Open a new terminal (or source your shell profile) and try:"
    echo "    chroma new my-app --template static"
    echo "    cd my-app && chroma dev"
}

add_to_path() {
    case "$PATH" in
        *"$CHROMA_BIN"*) ok "PATH already includes $CHROMA_BIN"; return ;;
    esac

    local profile
    case "${SHELL:-}" in
        */zsh) profile="$HOME/.zshrc" ;;
        */bash) profile="$HOME/.bashrc" ;;
        *) profile="$HOME/.profile" ;;
    esac

    if [ -f "$profile" ] && grep -q "CHROMA_HOME/bin" "$profile" 2>/dev/null; then
        warn "A Chroma entry already exists in $profile — open a new terminal for it to take effect."
        return
    fi

    {
        echo ''
        echo '# Chroma CLI'
        echo 'export CHROMA_HOME="$HOME/.chroma"'
        echo 'export PATH="$CHROMA_HOME/bin:$PATH"'
    } >> "$profile"
    warn "Added $CHROMA_BIN to PATH in $profile — open a new terminal or run: source $profile"
}

# ── new ──────────────────────────────────────────────────────────────────────
cmd_new() {
    LOG_CTX=New
    local name="" template="static"
    while [ $# -gt 0 ]; do
        case "$1" in
            --template) template="$2"; shift 2 ;;
            --template=*) template="${1#*=}"; shift ;;
            -*) die "Unknown option: $1" ;;
            *) name="$1"; shift ;;
        esac
    done

    [ -n "$name" ] || die "Usage: chroma new <name> [--template static|dynamic|standard]"
    [ "$template" = "static" ] || [ "$template" = "dynamic" ] || [ "$template" = "standard" ] || die "Invalid template: '$template' (use 'static', 'dynamic', or 'standard')"
    [ -d "$CHROMA_TEMPLATES/$template" ] || die "Chroma environment not found at $CHROMA_HOME. Run 'chroma install' first (from the repo)."
    [ -e "$name" ] && die "'$name' already exists in the current directory."

    [ -d "$CHROMA_ENGINE_SRC/pkg" ] || die "Compiled engine not found at $CHROMA_ENGINE_SRC/pkg. Run 'chroma install' first."

    info "Creating app '$name' (template: $template)..."
    mkdir -p "$name"
    cp -R "$CHROMA_TEMPLATES/$template/." "$name/"

    mkdir -p "$name/pkg"
    cp -R "$CHROMA_ENGINE_SRC/pkg/." "$name/pkg/"

    replace_json_name "$name/package.json" "$name"
    replace_json_name "$name/chroma.json" "$name"
    vendor_plugins "$name"

    ok "App created at ./$name"
    echo "  cd $name && chroma validate && chroma dev"
}

replace_json_name() {
    local file="$1" name="$2"
    [ -f "$file" ] || return 0
    local tmp; tmp="$(mktemp)"
    sed -E 's/^( *"name": *)"[^"]*"/\1"'"$name"'"/' "$file" > "$tmp" && mv "$tmp" "$file"
}

chroma_dev_reload_enabled() {
    local hr
    if [ -f chroma.json ]; then
        hr="$(json_field chroma.json hotReload)"
        case "$hr" in
            false|0) return 1 ;;
            true|1) return 0 ;;
        esac
    fi
    case "${CHROMA_DEV_RELOAD:-1}" in
        0|false|FALSE|no|NO) return 1 ;;
        *) return 0 ;;
    esac
}

engine_dev_args() {
    if chroma_dev_reload_enabled; then
        printf '%s' '--reload'
    else
        printf '%s' '--no-reload'
    fi
}

append_query_param() {
    local url="$1" key="$2" value="$3"
    if [[ "$url" == *'?'* ]]; then
        printf '%s&%s=%s' "$url" "$key" "$value"
    else
        printf '%s?%s=%s' "$url" "$key" "$value"
    fi
}

# ── dev ──────────────────────────────────────────────────────────────────────
# Both templates are served the same way in development: they're ES modules
# the browser already understands without transforms. `build` is where
# static/dynamic actually diverge (plain minification vs. bundle + wasm).
# Serving uses the engine binary installed at $CHROMA_HOME/bin — nothing is
# vendored into the project for this, having the CLI installed is enough.
cmd_dev() {
    LOG_CTX=Dev
    [ -f "chroma.json" ] || die "chroma.json not found in the current directory. Run this inside an app created with 'chroma new'."
    [ -x "$CHROMA_ENGINE_BIN" ] || die "engine binary not found at $CHROMA_ENGINE_BIN. Run 'chroma install'."

    local port mode desktop no_desktop=false
    port="$(json_field chroma.json port)"; port="${port:-4173}"
    mode="$(json_field chroma.json mode)"
    desktop="$(json_field chroma.json desktop)"
    while [ $# -gt 0 ]; do
        case "$1" in
            --port) port="$2"; shift 2 ;;
            --port=*) port="${1#*=}"; shift ;;
            --no-desktop) no_desktop=true; shift ;;
            --no-hot-reload|--no-reload) CHROMA_DEV_RELOAD=0; shift ;;
            --hot-reload|--reload) CHROMA_DEV_RELOAD=1; shift ;;
            *) shift ;;
        esac
    done

    if [ "$mode" = "dynamic" ] && [ "$desktop" = "true" ] && [ "$no_desktop" = false ]; then
        launch_dev_with_desktop "$port"
        return
    fi

    local reload_arg
    reload_arg="$(engine_dev_args)"
    exec "$CHROMA_ENGINE_BIN" --port "$port" --dir . "$reload_arg"
}

launch_dev_with_desktop() {
    local port="$1"
    local entry name url desktop_bin
    entry="$(json_field chroma.json entry)"; entry="${entry:-index.html}"
    name="$(json_field chroma.json name)"; name="${name:-Chroma app}"
    url="http://127.0.0.1:${port}/${entry}"
    url="$(append_query_param "$url" chroma_no_reload 1)"

    desktop_bin="$(resolve_desktop_bin)" || die "chroma-desktop not found. Run 'chroma install' from a full workspace checkout, or pass --no-desktop."

    info "Starting dev server on port $port (hot-reload disabled for Desktop)..."
    CHROMA_DEV_ENGINE_PID=0
    CHROMA_DEV_RELOAD=0 "$CHROMA_ENGINE_BIN" --port "$port" --dir . --no-reload &
    CHROMA_DEV_ENGINE_PID=$!
    cleanup_dev() {
        if [ "$CHROMA_DEV_ENGINE_PID" -gt 0 ]; then
            kill "$CHROMA_DEV_ENGINE_PID" 2>/dev/null || true
            CHROMA_DEV_ENGINE_PID=0
        fi
        trap - EXIT INT TERM
    }
    trap cleanup_dev EXIT INT TERM

    sleep 0.4

    info "Opening Chroma Desktop in develop mode..."
    "$desktop_bin" --develop --url "$url" --title "$name"
}

# ── build ────────────────────────────────────────────────────────────────────
cmd_build() {
    LOG_CTX=Build
    [ -f "chroma.json" ] || die "chroma.json not found in the current directory."
    local mode outdir
    mode="$(json_field chroma.json mode)"
    outdir="$(json_field chroma.json outDir)"; outdir="${outdir:-dist}"

    ensure_jsconfig

    rm -rf "$outdir"
    mkdir -p "$outdir"

    case "$mode" in
        static) build_static "$outdir" ;;
        dynamic) build_dynamic "$outdir" ;;
        *) die "Unknown mode in chroma.json: '$mode'" ;;
    esac
}

build_static() {
    local outdir="$1"
    require_node
    local entry vendor_dir
    entry="$(json_field chroma.json entry)"
    vendor_dir="$(json_field chroma.json vendorDir)"

    info "Building static → $outdir/ (source files minified as written)"

    minify_html "$entry" "$outdir/$entry"

    local f
    for f in $(json_array chroma.json scripts); do
        mkdir -p "$outdir/$(dirname "$f")"
        run_esbuild "$f" --minify --outfile="$outdir/$f"
    done
    for f in $(json_array chroma.json styles); do
        mkdir -p "$outdir/$(dirname "$f")"
        run_esbuild "$f" --minify --outfile="$outdir/$f"
    done

    inline_wasm_js "$vendor_dir" "$outdir/$vendor_dir"

    if [ -d "plugins" ]; then
        mkdir -p "$outdir/plugins"
        cp -R plugins/. "$outdir/plugins/"
    fi
    [ -f "chroma-fs.json" ] && cp "chroma-fs.json" "$outdir/chroma-fs.json"
    cp "chroma.json" "$outdir/chroma.json"
    strip_dist_metadata "$outdir"

    ok "Static build ready: $outdir/ (engine wasm inlined into minified chroma.js, no .wasm file, not recompiled)"
}

build_dynamic() {
    local outdir="$1"
    require_node
    command -v wasm-pack >/dev/null 2>&1 || die "wasm-pack not found. Run 'chroma install'."

    local vendor_dir rebuild js_entry outfile do_zip name entry
    vendor_dir="$(json_field chroma.json vendorDir)"
    rebuild="$(json_field chroma.json rebuildWasm)"
    js_entry="$(json_field chroma.json jsEntry)"
    outfile="$(json_field chroma.json outfile)"; outfile="${outfile:-bundle.js}"
    do_zip="$(json_field chroma.json zip)"
    name="$(json_field chroma.json name)"
    entry="$(json_field chroma.json entry)"

    if [ "$rebuild" = "true" ]; then
        [ -d "$CHROMA_ENGINE_SRC" ] || die "Engine source not found at $CHROMA_ENGINE_SRC. Run 'chroma install'."
        info "Recompiling the engine to WASM ($CHROMA_ENGINE_SRC)..."
        ( cd "$CHROMA_ENGINE_SRC" && ./build.sh )
        rm -rf "$vendor_dir"
        mkdir -p "$vendor_dir"
        cp -R "$CHROMA_ENGINE_SRC/pkg/." "$vendor_dir/"
    else
        warn "engine.rebuildWasm=false: using the engine already compiled at $vendor_dir/"
    fi

    info "Bundling $js_entry → $outdir/$outfile (esbuild, .chr→js loader, minified)"
    run_esbuild "$js_entry" --bundle --format=esm --minify --outfile="$outdir/$outfile"

    # wasm-bindgen resolves the .wasm with `new URL(..., import.meta.url)`,
    # so it must sit next to the packaged bundle.
    cp "$vendor_dir/chroma_bg.wasm" "$outdir/chroma_bg.wasm"

    minify_html "$entry" "$outdir/$entry" "$js_entry" "$outfile"

    if [ -d "plugins" ]; then
        mkdir -p "$outdir/plugins"
        cp -R plugins/. "$outdir/plugins/"
    fi
    [ -f "chroma-fs.json" ] && cp "chroma-fs.json" "$outdir/chroma-fs.json"
    cp "chroma.json" "$outdir/chroma.json"
    strip_dist_metadata "$outdir"

    ok "Dynamic build ready: $outdir/"

    if [ "$do_zip" = "true" ]; then
        info "Packaging $outdir/ ..."
        local pkg_path; pkg_path="$(package_dir "$outdir" "$name")"
        ok "Package ready: $pkg_path"
    fi
}

# ── add (legacy libraries) ───────────────────────────────────────────────────
cmd_add() {
    LOG_CTX=Add
    require_node
    local add_script="$CLI_DIR/lib/chroma-add.mjs"
    [ -f "$add_script" ] || die "chroma add helper not found at $add_script (reinstall CLI from repo)."
    CHROMA_HOME="$CHROMA_HOME" node "$add_script" "$@"
}

# ── fs init / link ───────────────────────────────────────────────────────────
cmd_fs() {
    LOG_CTX=Fs
    local sub="${1:-}"
    shift || true
    case "$sub" in
        init) cmd_fs_init "$@" ;;
        link) cmd_fs_link "$@" ;;
        *) die "Usage: chroma fs <init|link>" ;;
    esac
}

cmd_fs_init() {
    [ -f "chroma.json" ] || die "chroma.json not found in the current directory."
    [ -f "chroma-fs.json" ] && die "chroma-fs.json already exists."

    local mode
    mode="$(json_field chroma.json mode)"

    if [ "$mode" = "dynamic" ]; then
        cat > chroma-fs.json <<'EOF'
{
  "storage": {
    "backend": "filesystem",
    "basePath": "./data"
  }
}
EOF
    else
        cat > chroma-fs.json <<'EOF'
{
  "storage": {
    "backend": "indexeddb",
    "indexedDb": {
      "dbName": "chroma-fs",
      "storeName": "files"
    }
  }
}
EOF
    fi

    ok "Created chroma-fs.json (backend: $([ "$mode" = "dynamic" ] && echo filesystem || echo indexeddb))"
}

cmd_fs_link() {
    require_node
    local fs_src
    fs_src="$(resolve_chroma_fs_src)" || die "Chroma-Fs source not found. Run from the TargApps workspace."

    info "Building Chroma-Fs..."
    ( cd "$fs_src" && npm install --silent && npm run build )

    if [ ! -f "package.json" ]; then
        die "package.json not found in the current directory."
    fi

    local abs_src
    abs_src="$(cd "$fs_src" && pwd)"

    node -e '
        const fs = require("fs");
        const path = require("path");
        const pkgPath = "package.json";
        const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
        pkg.dependencies = pkg.dependencies || {};
        pkg.dependencies["@chroma/fs"] = "file:" + process.argv[1];
        fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");
    ' "$abs_src"

    npm install --silent
    ok "@chroma/fs linked from $abs_src"
}

# ── validate ─────────────────────────────────────────────────────────────────
resolve_schemas_dir() {
    if [ -n "${CHROMA_SCHEMAS:-}" ] && [ -f "${CHROMA_SCHEMAS}/chroma/chroma.schema.json" ]; then
        (cd "${CHROMA_SCHEMAS}" && pwd)
        return 0
    fi
    if [ -f "$CHROMA_HOME/schemas/chroma/chroma.schema.json" ]; then
        (cd "$CHROMA_HOME/schemas" && pwd)
        return 0
    fi
    if [ -f "$CLI_DIR/schemas/chroma/chroma.schema.json" ]; then
        (cd "$CLI_DIR/schemas" && pwd)
        return 0
    fi
    local mono="$REPO_DIR/../targ-apps-docs/public/schemas"
    if [ -f "$mono/chroma/chroma.schema.json" ]; then
        (cd "$mono" && pwd)
        return 0
    fi
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/targ-apps-docs/public/schemas/chroma/chroma.schema.json" ]; then
            (cd "$dir/targ-apps-docs/public/schemas" && pwd)
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

validate_manifest_structural() {
    local file="${1:-chroma.json}"
    local mode name entry vendor js fail=0
    mode="$(json_field "$file" mode)"
    name="$(json_field "$file" name)"

    [ -n "$name" ] || die "$file: missing required field \"name\""
    if [ "$mode" != "static" ] && [ "$mode" != "dynamic" ]; then
        die "$file: \"mode\" must be \"static\" or \"dynamic\" (got: ${mode:-<empty>}). Templates named standard use mode \"dynamic\"."
    fi

    entry="$(json_field "$file" entry)"; entry="${entry:-index.html}"
    if [ ! -f "$entry" ]; then err "$file: entry file not found: $entry"; fail=1; fi

    vendor="$(json_field "$file" vendorDir)"; vendor="${vendor:-pkg}"
    if [ ! -f "$vendor/chroma.js" ] && [ ! -f "$vendor/chroma.d.ts" ]; then
        err "$file: engine vendor dir missing WASM pkg at $vendor/ (expected chroma.js). Run chroma install or copy pkg/."
        fail=1
    fi

    if [ "$mode" = "dynamic" ]; then
        js="$(json_field "$file" jsEntry)"
        if [ -z "$js" ]; then
            die "$file: dynamic mode requires build.jsEntry (e.g. \"src/main.chr\")"
        fi
        if [ ! -f "$js" ]; then err "$file: build.jsEntry not found: $js"; fail=1; fi
    fi

    warn_legacy_js_in_src

    if [ "$mode" = "static" ]; then
        local scripts_found=0
        while read -r s; do
            [ -z "$s" ] && continue
            scripts_found=1
            if [ ! -f "$s" ]; then err "$file: build.scripts entry not found: $s"; fail=1; fi
        done <<< "$(json_array "$file" scripts)"
        if [ "$scripts_found" -eq 0 ]; then
            warn "$file: static mode has no build.scripts — ensure index scripts are listed for chroma build"
        fi
    fi

    while read -r pid; do
        [ -z "$pid" ] && continue
        if [ ! -d "plugins/$pid" ]; then
            err "$file: plugin \"$pid\" missing at plugins/$pid/"
            fail=1
            continue
        fi
        if [ ! -f "plugins/$pid/chroma.plugin.json" ]; then
            warn "$file: plugins/$pid/ has no chroma.plugin.json"
        fi
    done <<< "$(json_array "$file" plugins)"

    return "$fail"
}

validate_json_schema_file() {
    local schema_rel="$1" data_file="$2"
    local schemas_root="$3"
    local schema_path="$schemas_root/$schema_rel"
    schema_path="$(cd "$(dirname "$schema_path")" && pwd)/$(basename "$schema_path")"
    data_file="$(cd "$(dirname "$data_file")" && pwd)/$(basename "$data_file")"
    [ -f "$schema_path" ] || die "Schema not found: $schema_path"
    [ -f "$data_file" ] || die "Data file not found: $data_file"
    require_node
    local work; work="$(mktemp -d)"
    (
        cd "$work"
        npm init -y >/dev/null 2>&1
        npm install ajv@8 ajv-formats@3 --silent >/dev/null 2>&1
        node - "$schema_path" "$data_file" <<'NODE'
const fs = require("fs");
const Ajv2020 = require("ajv/dist/2020");
const addFormats = require("ajv-formats");
const [schemaPath, dataPath] = process.argv.slice(2);
const ajv = new Ajv2020({ allErrors: true, strict: false });
addFormats(ajv);
const schema = JSON.parse(fs.readFileSync(schemaPath, "utf8"));
const validate = ajv.compile(schema);
const data = JSON.parse(fs.readFileSync(dataPath, "utf8"));
if (!validate(data)) {
  for (const e of validate.errors || []) {
    const where = e.instancePath || "/";
    process.stderr.write(`${where}: ${e.message}\n`);
  }
  process.exit(1);
}
NODE
    ) || { rm -rf "$work"; return 1; }
    rm -rf "$work"
}

cmd_validate() {
    LOG_CTX=Validate
    local strict=false schema_off=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --strict) strict=true; shift ;;
            --no-schema) schema_off=true; shift ;;
            -h|--help)
                cat <<'EOF'
Usage: chroma validate [--strict] [--no-schema]

  --strict     Treat warnings (missing plugin manifest, empty static scripts) as errors
  --no-schema  Skip JSON Schema validation; only run structural checks
EOF
                return 0
                ;;
            *) die "Unknown option: $1 (try: chroma validate --help)" ;;
        esac
    done

    [ -f "chroma.json" ] || die "chroma.json not found in the current directory."

    local schemas_dir="" schema_ok=0
    if [ "$schema_off" = false ]; then
        if schemas_dir="$(resolve_schemas_dir)"; then
            info "JSON Schema catalog: $schemas_dir"
            if validate_json_schema_file "chroma/chroma.schema.json" "chroma.json" "$schemas_dir"; then
                ok "chroma.json matches chroma.schema.json"
                schema_ok=1
            else
                err "chroma.json failed JSON Schema validation (see errors above)"
                exit 1
            fi
        else
            warn "JSON Schema catalog not found — running structural checks only. Set CHROMA_SCHEMAS or run from the TargApps monorepo for full validation."
        fi
    fi

    local had_err=0
    validate_manifest_structural chroma.json || had_err=1

    if [ -f "chroma-fs.json" ]; then
        if [ -n "$schemas_dir" ] && [ "$schema_off" = false ]; then
            if validate_json_schema_file "chroma/chroma-fs.schema.json" "chroma-fs.json" "$schemas_dir"; then
                ok "chroma-fs.json matches chroma-fs.schema.json"
            else
                err "chroma-fs.json failed JSON Schema validation"
                had_err=1
            fi
        else
            ok "chroma-fs.json present (schema skipped)"
        fi
    fi

    if [ "$had_err" -ne 0 ]; then
        die "Validation failed — fix chroma.json (and related files) then run chroma validate again."
    fi

    if [ "$schema_ok" -eq 1 ]; then
        ok "Validation passed (schema + structure)"
    else
        ok "Validation passed (structure)"
    fi
}

# ── dispatch ─────────────────────────────────────────────────────────────────
_cmd="${1:-help}"
case "$_cmd" in
    help|--help|-h|--version|-v) ;;
    *) chroma_show_startup ;;
esac

case "$_cmd" in
    install) shift; cmd_install "$@" ;;
    new|init) shift; cmd_new "$@" ;;
    dev) shift; cmd_dev "$@" ;;
    build) shift; cmd_build "$@" ;;
    validate) shift; cmd_validate "$@" ;;
    add) shift; cmd_add "$@" ;;
    fs) shift; cmd_fs "$@" ;;
    help|--help|-h) usage ;;
    --version|-v) chroma_version ;;
    *) err "Unknown command: $_cmd"; echo; usage; exit 1 ;;
esac
