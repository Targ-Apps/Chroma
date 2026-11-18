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

# ── Help output (colors on TTY; plain when piped or NO_COLOR) ────────────────
c_bold=$'\033[1m'
c_accent=$'\033[96m'

_chroma_help_color() {
    [ -n "${CHROMA_NO_COLOR:-}" ] && return 1
    [ -n "${NO_COLOR:-}" ] && return 1
    [ -t 1 ]
}

_help_rule() {
    if _chroma_help_color; then
        printf '%s%s%s\n' "$c_dim" '────────────────────────────────────────────────────────' "$c_reset"
    else
        printf '%s\n' '----------------------------------------'
    fi
}

_help_section() {
    local title="$1"
    if _chroma_help_color; then
        printf '\n%s│ %s%s%s%s\n' "$c_dim" "$c_bold" "$title" "$c_reset" "$c_dim│$c_reset"
    else
        printf '\n[%s]\n' "$title"
    fi
}

_help_cmd() {
    if _chroma_help_color; then
        printf '\n  %s%s%s\n' "$c_accent" "$1" "$c_reset"
    else
        printf '\n  %s\n' "$1"
    fi
}

_help_body() {
    if _chroma_help_color; then
        printf '      %s%s%s\n' "$c_dim" "$1" "$c_reset"
    else
        printf '      %s\n' "$1"
    fi
}

_help_kv() {
    if _chroma_help_color; then
        printf '      %s%s:%s %s\n' "$c_bold" "$1" "$c_reset" "$2"
    else
        printf '      %s: %s\n' "$1" "$2"
    fi
}

usage() {
    local ver; ver="$(chroma_version_raw)"
    if _chroma_help_color; then
        printf '%s%schroma%s %s— CLI for the Chroma WASM engine%s  %s(v%s)%s\n' \
            "$c_bold" "$c_accent" "$c_reset" "$c_bold" "$c_reset" "$c_dim" "$ver" "$c_reset"
    else
        printf 'chroma — CLI for the Chroma WASM engine (v%s)\n' "$ver"
    fi
    _help_body 'Run chroma <command> [options] inside an app directory unless noted.'
  _help_rule

    _help_section 'USAGE'
    _help_cmd 'chroma <command> [options]'
    _help_kv 'Tip' 'chroma help | less — colors are omitted when stdout is not a terminal'

    _help_section 'COMMANDS'

    _help_cmd 'install [--no-rebase-root]'
    _help_body 'Provision ~/.chroma: engine binary, templates, pkg/, plugins, and chroma on PATH.'
    _help_kv 'When' 'First setup, after pulling a newer Chroma checkout, or to fix a broken install'
    _help_kv 'Why' 'new, dev, preview, and build all expect $CHROMA_HOME/bin (run from repo: ./cli/chroma.sh install)'
    _help_kv 'Default' 'Wipes $CHROMA_HOME and reinstalls (clean slate)'
    _help_kv 'Flag' '--no-rebase-root — update in place without deleting $CHROMA_HOME first'
    _help_kv 'Example' 'chroma install --no-rebase-root'

    _help_cmd 'new <name> [--template static|dynamic|standard]'
    _help_body 'Scaffold ./<name> from a template (default: static). Alias: init.'
    _help_kv 'When' 'Starting a project; templates set mode, plugins, and desktop dev defaults'
    _help_kv 'Why' 'Copies pkg/, rewrites name fields, vendors template plugins'
    _help_kv 'Example' 'chroma new my-app --template dynamic'

    _help_cmd 'recreate [path] [--template static|dynamic|standard] [--dry-run]'
    _help_body 'Restore the Chroma files a project is missing: pkg/, chroma.json, jsconfig.json, chroma-fs.json and listed runtime plugins.'
    _help_kv 'When' 'A project has no pkg/ or chroma.json (fresh clone, deploy target, copied sources)'
    _help_kv 'Why' 'Copies only what is absent from the installed templates; never overwrites or deletes anything'
    _help_kv 'Flag' '--dry-run — list what would be created without writing'
    _help_kv 'Example' 'chroma recreate ../my-site --dry-run'

    _help_cmd 'dev [--port <n>] [--no-desktop] [--static] [--no-reload | --reload]'
    _help_body 'Serve the project root with the engine dev server (needs chroma.json).'
    _help_kv 'When' 'Day-to-day editing; default port from chroma.json dev.port or 4173'
    _help_kv 'Why' 'Serves sources as native ES modules (.chr as JavaScript); browser dev uses live reload'
    _help_kv 'Plugins' 'Build plugins listed in chroma.json (chroma-mdx, chroma-blog, ...) compile .mdx on request and regenerate their files on change'
    _help_kv 'Live reload' 'Full page refresh on .chr and related changes; off for Chroma Desktop develop'
    _help_kv '--no-desktop' 'Browser only, even when dev.desktop is true (dynamic/standard default)'
    _help_kv '--static' 'Same as chroma preview — run chroma build first'
    _help_kv 'Example' 'chroma dev --port 5173'

    _help_cmd 'preview [--port <n>] [--dir <path>] [--host <ip>]'
    _help_body 'Serve the build output (outDir) over HTTP like a static host — no hot reload, no injection.'
    _help_kv 'When' 'After chroma build; smoke-test dist/ before upload or handoff'
    _help_kv 'Why' 'Correct MIME types (.wasm, .chr, .xml); same files a static host would serve'
    _help_kv 'Alias' 'serve'
    _help_kv 'Example' 'chroma build && chroma preview --port 4173'

    _help_cmd 'build'
    _help_body 'Compile and package into chroma.json outDir (default dist/; folder wiped each run).'
    _help_kv 'When' 'Before deploy, chroma preview, zip import into Chroma Desktop, or CI artifacts'
    _help_kv 'Why' 'static: minify + inline WASM into chroma.js; dynamic: Chroma compiler bundle + minify + optional zip'
    _help_kv 'Needs' 'Only the chroma CLI: no Node, no npm, no node_modules'

    _help_cmd 'validate [--strict] [--no-schema]'
    _help_body 'Validate chroma.json (and chroma-fs.json when present) before dev or build.'
    _help_kv 'When' 'Locally or in CI'
    _help_kv 'Why' 'Catches schema errors, missing entry/pkg/plugins/jsEntry early; warns about node_modules, package.json dependencies and compile scripts/'
    _help_kv 'Catalog' '$CHROMA_SCHEMAS, $CHROMA_HOME/schemas, cli/schemas, or monorepo docs catalog'

    _help_cmd 'fs init'
    _help_body 'Create chroma-fs.json (indexeddb for static, filesystem for dynamic).'
    _help_kv 'When' 'Adding Chroma-Fs storage to an app that lacks chroma-fs.json'

    _help_cmd 'add <lib-id> [--list] [--force] [--dry-run] [--registry <path>]'
    _help_body 'Vendor a legacy UMD/CDN library from the registry into the current app.'
    _help_kv 'When' 'Globals/CDN scripts — not for first-party plugins (use install + new)'
    _help_kv 'More' 'chroma add --help'

    _help_cmd 'help | --help | -h'
    _help_body 'Show this help (also when the command is omitted on error).'

    _help_cmd '--version | -v'
    _help_body 'Print CLI version only (no startup banner).'

    _help_section 'TEMPLATES'

    _help_cmd 'static'
    _help_body 'Flat HTML/JS; no bundler. build minifies as written; WASM inlined into chroma.js.'
    _help_kv 'When' 'Simple pages, minimal toolchain, single-file engine output'

    _help_cmd 'dynamic'
    _help_body 'ES modules; build bundles with the Chroma compiler; optional engine.rebuildWasm.'
    _help_kv 'When' 'Component-style apps under src/**/*.chr'

    _help_cmd 'standard'
    _help_body 'Dynamic plus Chroma-Fs demo and chroma-fs.json; dev.desktop default on.'
    _help_kv 'When' 'Explore filesystem UI and Desktop develop out of the box'

    _help_body 'All templates vendor pkg/ (chroma.js + chroma_bg.wasm). dev/preview/build use $CHROMA_HOME/bin/engine — no package.json, no node_modules, no build scripts in the project.'

    _help_section 'ENVIRONMENT'

    _help_cmd 'CHROMA_HOME'
    _help_body 'Install root (default ~/.chroma): bin/, engine-src/, templates/, plugins/, schemas/.'

    _help_cmd 'CHROMA_DEV_RELOAD'
    _help_body '1 (default) enables live reload for browser chroma dev; 0 disables (Desktop develop sets this automatically).'

    _help_cmd 'CHROMA_SCHEMAS'
    _help_body 'Directory containing chroma/chroma.schema.json for validate.'

    _help_cmd 'CHROMA_LOG_LEVEL'
    _help_body 'CLI log verbosity: error | warn | log (default) | debug | verbose.'

    _help_cmd 'NO_COLOR | CHROMA_NO_COLOR'
    _help_body 'Any non-empty value disables ANSI colors in help and log output.'

    _help_section 'EXIT STATUS'
    _help_body '0 on success.'
    _help_body '1 on usage errors: missing chroma.json, invalid template, missing engine/pkg, name collision, validation failure, etc.'
    printf '\n'
}

# ── JSON helpers (chroma.json is a small, fixed schema we control: jq is
# used when available, falling back to a grep/sed extraction otherwise) ──────
json_field() {
    local file="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -er --arg k "$key" '.. | objects | select(has($k)) | .[$k]' "$file" 2>/dev/null | head -1
        return 0
    fi
    { grep -oE '"'"$key"'" *: *("[^"]*"|[0-9.]+|true|false)' "$file" 2>/dev/null | head -1 \
        | sed -E 's/.*: *"?([^"]*)"?$/\1/'; } || true
}

json_array() {
    local file="$1" key="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -er --arg k "$key" '.. | objects | select(has($k)) | .[$k][]' "$file" 2>/dev/null
        return 0
    fi
    # Without jq: join lines first so a multi-line array is found; an absent key is not an error (set -e + pipefail).
    { tr '\n\r\t' '   ' < "$file" 2>/dev/null | grep -oE '"'"$key"'" *: *\[[^]]*\]' | grep -oE '"[^"]*"' | tail -n +2 | tr -d '"'; } || true
}

warn_legacy_js_in_src() {
    [ -d src ] || return 0
    local f
    while IFS= read -r -d '' f; do
        warn "Legacy .js under src/: $f — use .chr for Chroma app source (see docs/chroma/chr-format)"
    done < <(find src -name '*.js' -type f -print0 2>/dev/null)
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
    if fs_src="$(resolve_chroma_fs_src)" && [ -d "$fs_src/dist" ]; then
        LOG_CTX=Fs
        rm -rf "$CHROMA_PLUGINS/chroma-fs"
        mkdir -p "$CHROMA_PLUGINS/chroma-fs"
        cp "$fs_src/package.json" "$CHROMA_PLUGINS/chroma-fs/"
        cp -R "$fs_src/dist/." "$CHROMA_PLUGINS/chroma-fs/"
        [ -f "$fs_src/chroma.plugin.json" ] && cp "$fs_src/chroma.plugin.json" "$CHROMA_PLUGINS/chroma-fs/"
        ok "Chroma-Fs plugin ready at $CHROMA_PLUGINS/chroma-fs"
    elif [ -d "$CLI_DIR/plugins/chroma-fs" ]; then
        LOG_CTX=Fs
        rm -rf "$CHROMA_PLUGINS/chroma-fs"
        cp -R "$CLI_DIR/plugins/chroma-fs" "$CHROMA_PLUGINS/"
        ok "Chroma-Fs plugin copied from $CLI_DIR/plugins/chroma-fs"
    else
        LOG_CTX=Fs
        warn "Chroma-Fs build not found — plugin install skipped."
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

# Global build plugins that ship inside the engine binary (chroma.json "plugins" may list them).
readonly BUILD_PLUGINS=(chroma-mdx chroma-blog chroma-seo chroma-icons chroma-style)

is_build_plugin() {
    local p
    for p in "${BUILD_PLUGINS[@]}"; do
        [ "$p" = "$1" ] && return 0
    done
    return 1
}

vendor_plugins() {
    local project="$1"
    local plugins plugin
    plugins="$(json_array "$project/chroma.json" plugins)"
    [ -n "$plugins" ] || return 0

    for plugin in $plugins; do
        if [ ! -d "$CHROMA_PLUGINS/$plugin" ]; then
            # Global build plugins (chroma-mdx, chroma-blog, ...) live inside the engine: nothing to copy.
            is_build_plugin "$plugin" && continue
            die "Plugin '$plugin' not found at $CHROMA_PLUGINS/$plugin. Run 'chroma install'."
        fi
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
    cp "$CLI_DIR/engine-server/engine" "$CHROMA_ENGINE_BIN.new"
    chmod +x "$CHROMA_ENGINE_BIN.new"
    mv -f "$CHROMA_ENGINE_BIN.new" "$CHROMA_ENGINE_BIN"
    ok "engine binary ready at $CHROMA_ENGINE_BIN"

    info "Copying templates..."
    rm -rf "$CHROMA_TEMPLATES"
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
        [ -f "$CLI_DIR/legacy-libs/plugins-registry.json" ] && \
            cp "$CLI_DIR/legacy-libs/plugins-registry.json" "$CHROMA_HOME/legacy-libs/plugins-registry.json"
        if [ -d "$CLI_DIR/legacy-libs/vendor" ]; then
            mkdir -p "$CHROMA_HOME/legacy-libs/vendor"
            cp -R "$CLI_DIR/legacy-libs/vendor/." "$CHROMA_HOME/legacy-libs/vendor/"
        fi
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

# ── recreate ─────────────────────────────────────────────────────────────────
# Restores the Chroma files a project is missing (pkg/, chroma.json, jsconfig.json, chroma-fs.json and the runtime
# plugins listed in chroma.json) from the installed templates. It ONLY adds what is absent: it never overwrites an
# existing file and never deletes anything, so project source (src/, index.html, assets, ...) is left exactly as it is.
RECREATE_CREATED=0
RECREATE_SKIPPED=0
RECREATE_DRY=false
RECREATE_ROOT=""

# recreate_copy_missing <src_dir> <dest_dir>  — copy every file of src_dir that does not exist yet in dest_dir.
recreate_copy_missing() {
    local src="$1" dest="$2" f rel shown
    [ -d "$src" ] || return 0
    while IFS= read -r -d '' f; do
        rel="${f#"$src"/}"
        shown="${dest#"$RECREATE_ROOT"/}"
        [ "$dest" = "$RECREATE_ROOT" ] && shown=""
        shown="${shown:+$shown/}$rel"
        if [ -e "$dest/$rel" ] || [ -L "$dest/$rel" ]; then
            RECREATE_SKIPPED=$((RECREATE_SKIPPED + 1))
            continue
        fi
        RECREATE_CREATED=$((RECREATE_CREATED + 1))
        if [ "$RECREATE_DRY" = true ]; then
            echo "  would create $shown"
            continue
        fi
        mkdir -p "$(dirname "$dest/$rel")"
        cp -p "$f" "$dest/$rel"
        echo "  + $shown"
    done < <(find "$src" -type f -print0 | sort -z)
}

# recreate_copy_file <src_file> <dest_file> — same, for a single file.
recreate_copy_file() {
    local src="$1" dest="$2" shown
    [ -f "$src" ] || return 0
    shown="${dest#"$RECREATE_ROOT"/}"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        RECREATE_SKIPPED=$((RECREATE_SKIPPED + 1))
        return 0
    fi
    RECREATE_CREATED=$((RECREATE_CREATED + 1))
    if [ "$RECREATE_DRY" = true ]; then
        echo "  would create $shown"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    cp -p "$src" "$dest"
    echo "  + $shown"
}

# Which template a project without chroma.json looks like: dynamic when it has .chr sources, otherwise static.
recreate_guess_template() {
    local root="$1"
    if [ -d "$root/src" ] && [ -n "$(find "$root/src" -name '*.chr' -type f -print -quit 2>/dev/null)" ]; then
        echo dynamic
    else
        echo static
    fi
}

cmd_recreate() {
    LOG_CTX=Recreate
    local target="." template="" arg
    RECREATE_CREATED=0; RECREATE_SKIPPED=0; RECREATE_DRY=false
    while [ $# -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --template) template="${2:-}"; shift 2 ;;
            --template=*) template="${arg#*=}"; shift ;;
            --dry-run|-n) RECREATE_DRY=true; shift ;;
            -*) die "Unknown option: $arg" ;;
            *) target="$arg"; shift ;;
        esac
    done

    [ -d "$target" ] || die "Usage: chroma recreate [path] [--template static|dynamic|standard] [--dry-run] — '$target' is not a directory."
    RECREATE_ROOT="$(cd "$target" && pwd)"
    [ -d "$CHROMA_TEMPLATES" ] || die "Chroma environment not found at $CHROMA_HOME. Run 'chroma install' first (from the repo)."
    [ -d "$CHROMA_ENGINE_SRC/pkg" ] || die "Compiled engine not found at $CHROMA_ENGINE_SRC/pkg. Run 'chroma install' first."

    local manifest="$RECREATE_ROOT/chroma.json" had_manifest=true
    [ -f "$manifest" ] || had_manifest=false

    # Template: --template wins, then the project's own "mode", then a guess from its sources.
    if [ -z "$template" ]; then
        if [ "$had_manifest" = true ]; then template="$(json_field "$manifest" mode)"; fi
        [ -n "$template" ] || template="$(recreate_guess_template "$RECREATE_ROOT")"
    fi
    case "$template" in static|dynamic|standard) ;; *) die "Invalid template: '$template' (use 'static', 'dynamic', or 'standard')" ;; esac
    local tdir="$CHROMA_TEMPLATES/$template"
    [ -d "$tdir" ] || die "Template '$template' not found at $tdir. Run 'chroma install' first."

    if [ "$RECREATE_DRY" = true ]; then
        info "Dry run: nothing is written. Checking $RECREATE_ROOT (template: $template)..."
    else
        info "Restoring missing Chroma files in $RECREATE_ROOT (template: $template). Existing files are never touched."
    fi

    # 1. chroma.json (from the template, named after the folder).
    if [ "$had_manifest" = false ]; then
        recreate_copy_file "$tdir/chroma.json" "$manifest"
        if [ "$RECREATE_DRY" = false ] && [ -f "$manifest" ]; then
            replace_json_name "$manifest" "$(basename "$RECREATE_ROOT")"
        fi
    fi
    # The manifest that decides vendorDir and plugins: the project's, or the template's when it has none (dry run).
    local source_manifest="$manifest"
    [ -f "$source_manifest" ] || source_manifest="$tdir/chroma.json"

    # 2. pkg/ (engine glue + WASM), at engine.vendorDir.
    local vendor
    vendor="$(json_field "$source_manifest" vendorDir)"; vendor="${vendor:-pkg}"
    case "$vendor" in /*|*..*) die "engine.vendorDir '$vendor' must be a relative path inside the project." ;; esac
    recreate_copy_missing "$CHROMA_ENGINE_SRC/pkg" "$RECREATE_ROOT/$vendor"
    if [ -f "$RECREATE_ROOT/$vendor/package.json" ] && [ -f "$CHROMA_ENGINE_SRC/pkg/package.json" ]; then
        local have want
        have="$(json_field "$RECREATE_ROOT/$vendor/package.json" version)"
        want="$(json_field "$CHROMA_ENGINE_SRC/pkg/package.json" version)"
        if [ -n "$have" ] && [ -n "$want" ] && [ "$have" != "$want" ]; then
            warn "$vendor/ is engine $have; the installed engine is $want. recreate never replaces existing files: copy $CHROMA_ENGINE_SRC/pkg over it yourself if you want to update."
        fi
    fi

    # 3. Editor config and the Chroma-Fs config, only when the project uses them.
    recreate_copy_file "$tdir/jsconfig.json" "$RECREATE_ROOT/jsconfig.json"
    local plugins plugin has_runtime=false
    plugins="$(json_array "$source_manifest" plugins)"
    for plugin in $plugins; do
        [ "$plugin" = "chroma-fs" ] && recreate_copy_file "$tdir/chroma-fs.json" "$RECREATE_ROOT/chroma-fs.json"
    done

    # 4. Runtime plugins listed in chroma.json (build plugins live inside the engine and need no files).
    for plugin in $plugins; do
        if [ -d "$CHROMA_PLUGINS/$plugin" ]; then
            # plugins/loader.js only matters for plugins loaded at runtime; chroma-style & co. are imported directly.
            is_build_plugin "$plugin" || has_runtime=true
            recreate_copy_missing "$CHROMA_PLUGINS/$plugin" "$RECREATE_ROOT/plugins/$plugin"
        elif ! is_build_plugin "$plugin"; then
            warn "Plugin '$plugin' is listed in chroma.json but not installed at $CHROMA_PLUGINS/$plugin; skipped."
        fi
    done
    if [ "$has_runtime" = true ]; then
        recreate_copy_file "$tdir/plugins/loader.js" "$RECREATE_ROOT/plugins/loader.js"
    fi

    if [ "$RECREATE_CREATED" -eq 0 ]; then
        ok "Nothing to restore: all Chroma files are already there ($RECREATE_SKIPPED checked, none changed)."
    elif [ "$RECREATE_DRY" = true ]; then
        ok "Dry run: $RECREATE_CREATED file(s) would be created, $RECREATE_SKIPPED existing file(s) left alone."
    else
        ok "Restored $RECREATE_CREATED file(s); $RECREATE_SKIPPED existing file(s) left untouched."
        echo "  cd $target && chroma validate"
    fi
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

# ── preview / serve (production-like static preview) ─────────────────────────
# Serves chroma.json outDir with the engine binary: MIME table matches nginx,
# no hot-reload, no HTML injection — same as deploying dist/ to a static host.
# `chroma serve` is the older name of `chroma preview` and stays as an alias.
cmd_preview() {
    LOG_CTX=Serve
    [ -f "chroma.json" ] || die "chroma.json not found in the current directory. Run this inside an app created with 'chroma new'."
    [ -x "$CHROMA_ENGINE_BIN" ] || die "engine binary not found at $CHROMA_ENGINE_BIN. Run 'chroma install'."

    local engine_args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --port) [ $# -ge 2 ] || die "--port needs a value"; engine_args+=(--port "$2"); shift 2 ;;
            --port=*) engine_args+=(--port "${1#*=}"); shift ;;
            --dir) [ $# -ge 2 ] || die "--dir needs a value"; engine_args+=(--dir "$2"); shift 2 ;;
            --dir=*) engine_args+=(--dir "${1#*=}"); shift ;;
            --host) [ $# -ge 2 ] || die "--host needs a value"; engine_args+=(--host "$2"); shift 2 ;;
            --host=*) engine_args+=(--host "${1#*=}"); shift ;;
            --static) shift ;;
            --no-desktop|--no-hot-reload|--no-reload|--hot-reload|--reload) shift ;;
            *)
                die "Unknown option for 'chroma preview': $1 (use --port <n>, --dir <path> or --host <ip>)"
                ;;
        esac
    done

    CHROMA_DEV_RELOAD=0 exec "$CHROMA_ENGINE_BIN" preview "${engine_args[@]}"
}

cmd_serve() {
    cmd_preview "$@"
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

    local a
    for a in "$@"; do
        if [ "$a" = "--static" ]; then
            local filtered=()
            local x
            for x in "$@"; do
                [ "$x" = "--static" ] && continue
                filtered+=("$x")
            done
            cmd_preview "${filtered[@]}"
            return
        fi
    done

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
    exec "$CHROMA_ENGINE_BIN" dev --port "$port" --dir . "$reload_arg"
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
    CHROMA_DEV_RELOAD=0 "$CHROMA_ENGINE_BIN" dev --port "$port" --dir . --no-reload &
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
# The whole build (bundle, minify, HTML, assets, build plugins, zip) is done by
# the engine binary: no Node, no npm, no esbuild.
cmd_build() {
    LOG_CTX=Build
    [ -f "chroma.json" ] || die "chroma.json not found in the current directory."
    [ -x "$CHROMA_ENGINE_BIN" ] || die "engine binary not found at $CHROMA_ENGINE_BIN. Run 'chroma install'."
    CHROMA_HOME="$CHROMA_HOME" "$CHROMA_ENGINE_BIN" build "$@"
}

# ── add (legacy libraries) ───────────────────────────────────────────────────
cmd_add() {
    LOG_CTX=Add
    [ -x "$CHROMA_ENGINE_BIN" ] || die "engine binary not found at $CHROMA_ENGINE_BIN. Run 'chroma install'."
    CHROMA_HOME="$CHROMA_HOME" exec "$CHROMA_ENGINE_BIN" add "$@"
}

# ── fs init / link ───────────────────────────────────────────────────────────
cmd_fs() {
    LOG_CTX=Fs
    local sub="${1:-}"
    shift || true
    case "$sub" in
        init) cmd_fs_init "$@" ;;
        link) die "'chroma fs link' was removed: Chroma projects have no npm. Use the chroma-fs plugin (plugins/chroma-fs, copied by 'chroma new')." ;;
        *) die "Usage: chroma fs init" ;;
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
            # Global build plugins (chroma-mdx, chroma-blog, chroma-seo, chroma-icons, chroma-style) need no folder.
            is_build_plugin "$pid" && continue
            err "$file: plugin \"$pid\" missing at plugins/$pid/ (global build plugins: ${BUILD_PLUGINS[*]})"
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
    [ -x "$CHROMA_ENGINE_BIN" ] || die "engine binary not found at $CHROMA_ENGINE_BIN. Run 'chroma install'."
    "$CHROMA_ENGINE_BIN" validate-schema "$schema_path" "$data_file"
}

# Chroma projects have no Node, no npm and no node_modules: flag leftovers of the old toolchain.
# Prints one warning per finding and returns the number of findings.
warn_node_leftovers() {
    local n=0
    if [ -d node_modules ]; then
        warn "node_modules/ found: Chroma projects have no node_modules. Delete it; import with relative paths or URLs (see docs/chroma/reference/chr-format)."
        n=$((n + 1))
    fi
    if [ -f package.json ]; then
        local flat; flat="$(tr -d '\n\r' < package.json 2>/dev/null)"
        if printf '%s' "$flat" | grep -Eq '"(dependencies|devDependencies|optionalDependencies|peerDependencies)"[[:space:]]*:[[:space:]]*\{[[:space:]]*"'; then
            warn "package.json declares dependencies: Chroma has no npm. Delete package.json (chroma dev|preview|build need nothing else)."
            n=$((n + 1))
        elif printf '%s' "$flat" | grep -Eq '"scripts"[[:space:]]*:[[:space:]]*\{[^}]*(npm |npx |node |esbuild|vite|webpack|rollup|tsc)'; then
            warn "package.json scripts call npm/node tools: use chroma dev, chroma preview and chroma build instead."
            n=$((n + 1))
        fi
    fi
    if [ -d scripts ]; then
        local f hits=""
        while IFS= read -r -d '' f; do
            if grep -Eqi 'esbuild|rollup|webpack|terser|minif|bundl|require\(|node:|npm |npx ' "$f" 2>/dev/null; then
                hits="$hits $f"
            fi
        done < <(find scripts -maxdepth 2 -type f \( -name '*.mjs' -o -name '*.js' -o -name '*.cjs' -o -name '*.ts' -o -name '*.sh' \) -print0 2>/dev/null)
        if [ -n "$hits" ]; then
            warn "scripts/ holds build scripts that Chroma no longer runs:$hits — chroma build compiles, bundles and minifies by itself; remove or move them out of the project."
            n=$((n + 1))
        fi
    fi
    return $n
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

  --strict     Treat warnings (missing plugin manifest, empty static scripts, node_modules/npm leftovers) as errors
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
            warn "JSON Schema catalog not found — running structural checks only. Set CHROMA_SCHEMAS or run 'chroma install' (installs the schemas)."
        fi
    fi

    local had_err=0
    validate_manifest_structural chroma.json || had_err=1
    local leftovers=0
    warn_node_leftovers || leftovers=$?
    if [ "$leftovers" -gt 0 ] && [ "$strict" = true ]; then
        err "--strict: $leftovers leftover(s) of the Node/npm toolchain found"
        had_err=1
    fi

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
    recreate) shift; cmd_recreate "$@" ;;
    dev) shift; cmd_dev "$@" ;;
    preview) shift; cmd_preview "$@" ;;
    serve) shift; cmd_serve "$@" ;;
    build) shift; cmd_build "$@" ;;
    validate) shift; cmd_validate "$@" ;;
    add) shift; cmd_add "$@" ;;
    fs) shift; cmd_fs "$@" ;;
    help|--help|-h) usage ;;
    --version|-v) chroma_version ;;
    *) err "Unknown command: $_cmd"; echo; usage; exit 1 ;;
esac
