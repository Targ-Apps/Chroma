# Chroma CLI (Windows) — provisions the toolchain and scaffolds/builds
# Chroma apps. Run `.\chroma.ps1 install` once from a checkout of the repo;
# afterwards the `chroma` command is available system-wide.
#
# If Windows blocks script execution, run first:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)

$ErrorActionPreference = "Stop"

# ── Path resolution ──────────────────────────────────────────────────────────
$CliDir = $PSScriptRoot
$RepoDir = Split-Path $CliDir -Parent

$ChromaHome = if ($env:CHROMA_HOME) { $env:CHROMA_HOME } else { Join-Path $HOME ".chroma" }
$ChromaBin = Join-Path $ChromaHome "bin"
$ChromaTemplates = Join-Path $ChromaHome "templates"
$ChromaPlugins = Join-Path $ChromaHome "plugins"
$ChromaEngineSrc = Join-Path $ChromaHome "engine-src"
$ChromaEngineBin = Join-Path $ChromaBin "engine.exe"
$ChromaDesktopBin = Join-Path $ChromaBin "chroma-desktop.exe"
$WorkspaceRoot = Split-Path $CliDir -Parent

# ── Output ───────────────────────────────────────────────────────────────────
function Info($msg) { Write-Host "-> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "OK $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "!! $msg" -ForegroundColor Yellow }
function Err($msg)  { Write-Host "XX $msg" -ForegroundColor Red }
function Fail($msg) { Err $msg; exit 1 }

# Canonical version: Chroma/VERSION (monorepo), CLI_DIR/VERSION (standalone
# package), or $CHROMA_HOME/VERSION after `chroma install`.
function Get-ChromaVersionRaw {
    $candidates = @(
        (Join-Path $RepoDir "VERSION"),
        (Join-Path $CliDir "VERSION"),
        (Join-Path $ChromaHome "VERSION")
    )
    foreach ($f in $candidates) {
        if (Test-Path $f) {
            return (Get-Content -Path $f -Raw).Trim()
        }
    }
    return "unknown"
}

function Get-ChromaVersionString {
    return "Chroma v$(Get-ChromaVersionRaw)"
}

function Show-ChromaVersion { Write-Host (Get-ChromaVersionString) }

function Show-ChromaStartup {
    Write-Host (Get-ChromaVersionString) -ForegroundColor DarkGray
}

function Install-VersionFile {
    $versionSrc = $null
    foreach ($candidate in @((Join-Path $RepoDir "VERSION"), (Join-Path $CliDir "VERSION"))) {
        if (Test-Path $candidate) { $versionSrc = $candidate; break }
    }
    if ($versionSrc) {
        Copy-Item -Force $versionSrc (Join-Path $ChromaHome "VERSION")
    }
}

function Test-ChromaHelpColor {
    if ($env:CHROMA_NO_COLOR -or $env:NO_COLOR) { return $false }
    try { return -not [Console]::IsOutputRedirected } catch { return $Host.UI.SupportsVirtualTerminal }
}

function Write-HelpRule {
    if (Test-ChromaHelpColor) { Write-Host '────────────────────────────────────────────────────────' -ForegroundColor DarkGray }
    else { Write-Host '----------------------------------------' }
}

function Write-HelpSection($title) {
    if (Test-ChromaHelpColor) { Write-Host "`n│ $title │" -ForegroundColor DarkGray }
    else { Write-Host "`n[$title]" }
}

function Write-HelpCmd($sig) {
    if (Test-ChromaHelpColor) { Write-Host "`n  $sig" -ForegroundColor Cyan }
    else { Write-Host "`n  $sig" }
}

function Write-HelpBody($text) {
    if (Test-ChromaHelpColor) { Write-Host "      $text" -ForegroundColor DarkGray }
    else { Write-Host "      $text" }
}

function Write-HelpKv($key, $value) {
    if (Test-ChromaHelpColor) {
        Write-Host -NoNewline "      $key" -ForegroundColor White
        Write-Host ": $value"
    } else {
        Write-Host "      ${key}: $value"
    }
}

function Show-Usage {
    $ver = Get-ChromaVersionRaw
    if (Test-ChromaHelpColor) {
        Write-Host -NoNewline 'chroma ' -ForegroundColor Cyan
        Write-Host "— CLI for the Chroma WASM engine  (v$ver)"
    } else {
        Write-Host "chroma — CLI for the Chroma WASM engine (v$ver)"
    }
    Write-HelpBody 'Run chroma <command> [options] inside an app directory unless noted.'
    Write-HelpRule

    Write-HelpSection 'USAGE'
    Write-HelpCmd 'chroma <command> [options]'
    Write-HelpKv 'Tip' 'Pipe to a file — colors are omitted when stdout is redirected'

    Write-HelpSection 'COMMANDS'

    Write-HelpCmd 'install [--no-rebase-root]'
    Write-HelpBody 'Provision CHROMA_HOME: engine.exe, templates, pkg\, plugins, chroma on PATH.'
    Write-HelpKv 'When' 'First setup, after upgrading Chroma, or to fix a broken install'
    Write-HelpKv 'Why' 'new, dev, and build expect $env:CHROMA_HOME\bin (run: .\cli\chroma.ps1 install)'
    Write-HelpKv 'Default' 'Wipes CHROMA_HOME and reinstalls (clean slate)'
    Write-HelpKv 'Flag' '--no-rebase-root — update in place without deleting CHROMA_HOME first'

    Write-HelpCmd 'new <name> [--template static|dynamic|standard]'
    Write-HelpBody 'Scaffold .\<name> from a template (default: static).'
    Write-HelpKv 'When' 'Starting a project; templates set mode, plugins, and desktop dev defaults'
    Write-HelpKv 'Example' 'chroma new my-app --template dynamic'

    Write-HelpCmd 'dev [--port <n>] [--no-desktop] [--static] [--no-reload | --reload]'
    Write-HelpBody 'Serve the project root with the engine dev server (needs chroma.json).'
    Write-HelpKv 'When' 'Day-to-day editing; default port from chroma.json or 4173'
    Write-HelpKv 'Why' 'Serves sources as ES modules; browser dev uses live reload'
    Write-HelpKv 'Live reload' 'Full page refresh on source changes; off for Chroma Desktop develop'
    Write-HelpKv '--no-desktop' 'Browser only when dev.desktop is true'
    Write-HelpKv '--static' 'Serve outDir like chroma serve — run chroma build first'

    Write-HelpCmd 'serve [--port <n>] [--dir <path>]'
    Write-HelpBody 'Serve compiled outDir — production-like static host, no live reload.'
    Write-HelpKv 'When' 'After chroma build; smoke-test dist\ before deploy'
    Write-HelpKv 'Why' 'Correct MIME types; no dev-reload script injection'

    Write-HelpCmd 'build'
    Write-HelpBody 'Package into chroma.json outDir (default dist\; wiped each run).'
    Write-HelpKv 'When' 'Before deploy, serve, or Desktop zip import'

    Write-HelpCmd 'validate'
    Write-HelpBody 'Structural checks for chroma.json (entry, pkg\, plugins). JSON Schema: chroma.sh on macOS/Linux.'
    Write-HelpKv 'When' 'Before dev or build on Windows'

    Write-HelpCmd 'add <lib-id> [--list] [--force] [--dry-run] [--registry <path>]'
    Write-HelpBody 'Vendor a legacy UMD/CDN library. See chroma add --help.'
    Write-HelpKv 'When' 'Not for first-party plugins (use install + new)'

    Write-HelpCmd 'help | --help | -h'
    Write-HelpBody 'Show this help.'

    Write-HelpCmd '--version | -v'
    Write-HelpBody 'Print CLI version only.'

    Write-HelpSection 'TEMPLATES'
    Write-HelpCmd 'static'
    Write-HelpBody 'Flat HTML/JS; WASM inlined into chroma.js.'
    Write-HelpCmd 'dynamic'
    Write-HelpBody 'ES modules; esbuild bundle; optional engine.rebuildWasm.'
    Write-HelpCmd 'standard'
    Write-HelpBody 'Dynamic plus Chroma-Fs demo; dev.desktop default on.'
    Write-HelpBody 'All templates vendor pkg\. dev/build use $env:CHROMA_HOME\bin\engine.exe — no server copied into the project.'

    Write-HelpSection 'ENVIRONMENT'
    Write-HelpCmd 'CHROMA_HOME'
    Write-HelpBody 'Install root (default $HOME\.chroma): bin\, engine-src\, templates\, plugins\.'
    Write-HelpCmd 'CHROMA_DEV_RELOAD'
    Write-HelpBody '1 enables live reload for browser dev; 0 disables (Desktop develop).'
    Write-HelpCmd 'NO_COLOR | CHROMA_NO_COLOR'
    Write-HelpBody 'Disables color in help output when set.'

    Write-HelpSection 'EXIT STATUS'
    Write-HelpBody '0 on success; 1 on usage errors (missing chroma.json, invalid template, etc.).'
    Write-Host ''
}

function Assert-Node {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Fail "Node.js is required for this step (bundling/minifying). Install it from https://nodejs.org and try again."
    }
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Fail "npx not found (ships with npm). Install/update Node.js."
    }
}

function Invoke-Esbuild {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$EsbuildArgs)
    npx --yes esbuild --loader:.chr=js @EsbuildArgs
}

function Warn-LegacyJsInSrc {
    if (-not (Test-Path "src")) { return }
    Get-ChildItem -Path "src" -Filter "*.js" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        Warn "Legacy .js under src/: $($_.FullName.Substring((Get-Location).Path.Length + 1)) — use .chr for Chroma app source (see docs/chroma/chr-format)"
    }
}

# Generates jsconfig.json if the project doesn't already have one, so
# VSCode-family editors resolve types from pkg/chroma.d.ts (hover docs,
# autocomplete) without any manual setup. Never overwrites an existing file.
function Ensure-JsConfig {
    if (Test-Path "jsconfig.json") { return }
    Info "jsconfig.json not found, generating one for editor IntelliSense..."
    $jsconfig = @'
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
'@
    Set-Content -Path "jsconfig.json" -Value $jsconfig
}

# Inlines chroma_bg.wasm as base64 directly into chroma.js (replacing the
# `new URL('chroma_bg.wasm', import.meta.url)` + fetch path with an embedded
# byte array) and minifies the result. Used by static builds so the shipped
# engine is a single JS file — no .wasm request, no separate artifact.
function Inline-WasmJs {
    param([string]$VendorDir, [string]$OutDir)
    Assert-Node
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

    $jsSrc = Join-Path $VendorDir "chroma.js"
    $wasmSrc = Join-Path $VendorDir "chroma_bg.wasm"
    $js = Get-Content -Raw -Path $jsSrc
    $wasmB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($wasmSrc))
    $marker = "new URL('chroma_bg.wasm', import.meta.url)"
    if (-not $js.Contains($marker)) {
        Fail "chroma.js: wasm URL marker not found, cannot inline wasm"
    }
    $inline = "Uint8Array.from(atob('$wasmB64'), c => c.charCodeAt(0))"
    $js = $js.Replace($marker, $inline)

    $inlined = Join-Path ([IO.Path]::GetTempPath()) "$([Guid]::NewGuid()).js"
    Set-Content -Path $inlined -Value $js -NoNewline
    npx --yes esbuild $inlined --minify --outfile="$(Join-Path $OutDir "chroma.js")"
    Remove-Item -Force $inlined
}

# Minifies HTML (strips comments and whitespace) and, optionally, replaces a
# literal text reference (used to point <script src> at the bundle output).
function Minify-Html {
    param([string]$Src, [string]$Dst, [string]$From = "", [string]$To = "")
    $html = Get-Content -Raw -Path $Src
    if ($From) { $html = $html.Replace($From, $To) }
    $html = [regex]::Replace($html, '<!--[\s\S]*?-->', '')
    $html = [regex]::Replace($html, '>\s+<', '><')
    $html = [regex]::Replace($html, '[ \t]+', ' ')
    $html = [regex]::Replace($html, '\n\s*', '')
    $dstDir = Split-Path $Dst -Parent
    if ($dstDir) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
    Set-Content -Path $Dst -Value $html.Trim() -NoNewline
}

function Remove-DistMetadata {
    param([string]$Dir)
    Get-ChildItem -Path $Dir -Force -Recurse -Directory -Filter '.git' -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $Dir -Force -Recurse -File -Filter '.gitignore' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $Dir -Force -Recurse -File -Filter '.env*' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Set-JsonName {
    param([string]$File, [string]$Name)
    if (-not (Test-Path $File)) { return }
    $content = Get-Content -Raw -Path $File
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m) $m.Groups[1].Value + '"' + $Name + '"'
    }
    $content = [regex]::Replace($content, '(?m)^( *"name": *)"[^"]*"', $evaluator)
    Set-Content -Path $File -Value $content -NoNewline
}

function Resolve-ChromaFsSrc {
    foreach ($candidate in @(
        (Join-Path $WorkspaceRoot "Chroma-Fs"),
        (Join-Path $RepoDir "Chroma-Fs"),
        (Join-Path $CliDir "..\Chroma-Fs")
    )) {
        if (Test-Path (Join-Path $candidate "package.json")) {
            return $candidate
        }
    }
    return $null
}

function Resolve-PluginSrc {
    param([string]$Plugin)
    $topLevel = switch ($Plugin) {
        "chroma-style" { Join-Path $WorkspaceRoot "Chroma-Style" }
        "chroma-router" { Join-Path $WorkspaceRoot "Chroma-Router" }
        "chroma-t2t" { Join-Path $WorkspaceRoot "Chroma-t2t" }
        default { $null }
    }
    if ($topLevel -and (Test-Path (Join-Path $topLevel "chroma.plugin.json"))) {
        return $topLevel
    }
    $bundled = Join-Path $CliDir "plugins/$Plugin"
    if (Test-Path $bundled) { return $bundled }
    return $null
}

function Install-Plugins {
    New-Item -ItemType Directory -Force -Path $ChromaPlugins | Out-Null
    $fsSrc = Resolve-ChromaFsSrc
    if ($fsSrc) {
        Info "Building Chroma-Fs plugin from $fsSrc..."
        Push-Location $fsSrc
        try {
            npm install --silent | Out-Null
            npm run build | Out-Null
        } catch {
            Warn "Chroma-Fs build failed — plugin install skipped."
            Pop-Location
            return
        }
        Pop-Location
        $dest = Join-Path $ChromaPlugins "chroma-fs"
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item -Force (Join-Path $fsSrc "package.json") $dest
        Copy-Item -Recurse -Force (Join-Path $fsSrc "dist/*") $dest
        Ok "Chroma-Fs plugin ready at $dest"
    } elseif (Test-Path (Join-Path $CliDir "plugins/chroma-fs")) {
        $dest = Join-Path $ChromaPlugins "chroma-fs"
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        Copy-Item -Recurse -Force (Join-Path $CliDir "plugins/chroma-fs") $dest
        Ok "Chroma-Fs plugin copied from $(Join-Path $CliDir 'plugins/chroma-fs')"
    } else {
        Warn "Chroma-Fs source not found — plugin install skipped."
    }

    foreach ($plugin in @("chroma-style", "chroma-router", "chroma-t2t")) {
        $src = Resolve-PluginSrc $plugin
        if ($src) {
            $dest = Join-Path $ChromaPlugins $plugin
            if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
            Copy-Item -Recurse -Force $src $dest
            Ok "$plugin copied from $src"
        }
    }
}

function Install-Desktop {
    $desktopDir = $null
    foreach ($candidate in @(
        (Join-Path $WorkspaceRoot "Chroma-Desktop"),
        (Join-Path $RepoDir "Chroma-Desktop"),
        (Join-Path $CliDir "..\Chroma-Desktop")
    )) {
        if (Test-Path (Join-Path $candidate "Cargo.toml")) {
            $desktopDir = $candidate
            break
        }
    }

    if ($desktopDir) {
        Info "Building Chroma Desktop for develop mode..."
        Push-Location $desktopDir
        try {
            cargo build -q 2>$null
        } catch {
            Pop-Location
            Warn "Chroma Desktop build failed — develop mode will require a manual build."
            return
        }
        Pop-Location
        $built = Join-Path $desktopDir "target/debug/chroma-desktop.exe"
        if (Test-Path $built) {
            Copy-Item -Force $built $ChromaDesktopBin
            Ok "chroma-desktop ready at $ChromaDesktopBin"
            return
        }
        Warn "Chroma Desktop build failed — develop mode will require a manual build."
    } elseif (Test-Path (Join-Path $CliDir "desktop/chroma-desktop.exe")) {
        Copy-Item -Force (Join-Path $CliDir "desktop/chroma-desktop.exe") $ChromaDesktopBin
        Ok "chroma-desktop ready at $ChromaDesktopBin"
    }
}

function Resolve-DesktopBin {
    if (Test-Path $ChromaDesktopBin) { return $ChromaDesktopBin }
    foreach ($desktopDir in @(
        (Join-Path $WorkspaceRoot "Chroma-Desktop"),
        (Join-Path $RepoDir "Chroma-Desktop"),
        (Join-Path $CliDir "..\Chroma-Desktop")
    )) {
        foreach ($candidate in @(
            (Join-Path $desktopDir "target/debug/chroma-desktop.exe"),
            (Join-Path $desktopDir "target/release/chroma-desktop.exe")
        )) {
            if (Test-Path $candidate) { return $candidate }
        }
    }
    $onPath = Get-Command chroma-desktop -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    return $null
}

function Vendor-Plugins {
    param([string]$Project)
    $manifestPath = Join-Path $Project "chroma.json"
    if (-not (Test-Path $manifestPath)) { return }
    $cfg = Get-Content -Raw $manifestPath | ConvertFrom-Json
    if (-not $cfg.plugins) { return }
    foreach ($plugin in $cfg.plugins) {
        $src = Join-Path $ChromaPlugins $plugin
        if (-not (Test-Path $src)) {
            Fail "Plugin '$plugin' not found at $src. Run 'chroma install'."
        }
        $destRoot = Join-Path $Project "plugins"
        New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
        Copy-Item -Recurse -Force $src (Join-Path $destRoot $plugin)
    }
}

# ── install ──────────────────────────────────────────────────────────────────
function Install-Chroma {
    param([string[]]$Arguments)

    $noRebaseRoot = $Arguments -contains "--no-rebase-root"

    # Two ways to run this script: from a Chroma checkout (cli\chroma.ps1,
    # with Cargo.toml/src\ next to cli\ — can build and rebuild from source)
    # or from a standalone Chroma-CLI package (chroma.ps1 at the package
    # root, with a prebuilt pkg\ next to it and no Rust source at all).
    $monorepoMode = Test-Path (Join-Path $RepoDir "Cargo.toml")
    if (-not $monorepoMode -and -not (Test-Path (Join-Path $CliDir "pkg"))) {
        Fail "Neither a Chroma checkout (Cargo.toml next to cli/) nor a prebuilt pkg/ next to this script was found."
    }

    if (-not $noRebaseRoot -and (Test-Path $ChromaHome)) {
        Info "Wiping $ChromaHome for a clean reinstall (use --no-rebase-root to update in place)..."
        Remove-Item -Recurse -Force $ChromaHome
    }

    if (Get-Command node -ErrorAction SilentlyContinue) {
        Ok "Node.js detected ($(node --version))"
    } else {
        Warn "Node.js not found. Required for 'chroma build' (bundling/minifying via esbuild). Install it from https://nodejs.org."
    }

    if (Test-Path $ChromaEngineSrc) { Remove-Item -Recurse -Force $ChromaEngineSrc }
    New-Item -ItemType Directory -Force -Path (Join-Path $ChromaEngineSrc "pkg") | Out-Null

    if ($monorepoMode) {
        Info "Checking Rust..."
        if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
            Info "Installing Rust (rustup)..."
            $rustupInit = Join-Path $env:TEMP "rustup-init.exe"
            Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile $rustupInit
            & $rustupInit -y --default-toolchain stable
            $env:PATH = "$HOME\.cargo\bin;$env:PATH"
        } else {
            Ok "Rust already installed ($(rustc --version))"
        }

        Info "Checking wasm32-unknown-unknown target..."
        $targets = & rustup target list --installed 2>$null
        if (-not ($targets -match "wasm32-unknown-unknown")) {
            rustup target add wasm32-unknown-unknown
        }
        Ok "wasm32-unknown-unknown target ready"

        Info "Checking wasm-pack..."
        if (-not (Get-Command wasm-pack -ErrorAction SilentlyContinue)) {
            Info "Installing wasm-pack..."
            Invoke-Expression (Invoke-WebRequest -Uri "https://rustwasm.github.io/wasm-pack/installer/init.ps1" -UseBasicParsing).Content
        } else {
            Ok "wasm-pack already installed ($(wasm-pack --version))"
        }

        Info "Vendoring the engine source into $ChromaEngineSrc..."
        New-Item -ItemType Directory -Force -Path (Join-Path $ChromaEngineSrc "src") | Out-Null
        Copy-Item -Recurse -Force (Join-Path $RepoDir "src/*") (Join-Path $ChromaEngineSrc "src")
        Copy-Item -Force (Join-Path $RepoDir "Cargo.toml") (Join-Path $ChromaEngineSrc "Cargo.toml")
        Copy-Item -Force (Join-Path $RepoDir "build.sh") (Join-Path $ChromaEngineSrc "build.sh")
        $lockPath = Join-Path $RepoDir "Cargo.lock"
        if (Test-Path $lockPath) { Copy-Item -Force $lockPath (Join-Path $ChromaEngineSrc "Cargo.lock") }

        $repoPkg = Join-Path $RepoDir "pkg"
        if (-not (Test-Path $repoPkg)) {
            Info "pkg/ not built yet. Building it with wasm-pack..."
            Push-Location $RepoDir
            wasm-pack build --target web
            Add-Content -Path (Join-Path $repoPkg "chroma.js") -Value "`nawait __wbg_init();"
            Pop-Location
        }
        Copy-Item -Recurse -Force (Join-Path $repoPkg "*") (Join-Path $ChromaEngineSrc "pkg")
        Ok "Engine source + compiled pkg ready at $ChromaEngineSrc"
    } else {
        Info "Installing the prebuilt engine into $ChromaEngineSrc..."
        Copy-Item -Recurse -Force (Join-Path $CliDir "pkg/*") (Join-Path $ChromaEngineSrc "pkg")
        Ok "Prebuilt engine ready at $ChromaEngineSrc (no Rust source shipped - dynamic apps' rebuildWasm is unavailable)"
    }

    Info "Installing the dev-server binary (engine)..."
    $enginePrebuilt = Join-Path $CliDir "engine-server/engine.exe"
    if (-not (Test-Path $enginePrebuilt)) { Fail "Prebuilt binary not found at $enginePrebuilt." }
    New-Item -ItemType Directory -Force -Path $ChromaBin | Out-Null
    Copy-Item -Force $enginePrebuilt $ChromaEngineBin
    Ok "engine.exe ready at $ChromaEngineBin"

    Info "Copying templates..."
    New-Item -ItemType Directory -Force -Path $ChromaTemplates | Out-Null
    Copy-Item -Recurse -Force (Join-Path $CliDir "examples/*") $ChromaTemplates
    Ok "Templates ready at $ChromaTemplates (static, dynamic, standard)"

    $legacyBundled = Join-Path $CliDir "legacy-libs/registry.json"
    if (Test-Path $legacyBundled) {
        $legacyDest = Join-Path $ChromaHome "legacy-libs"
        New-Item -ItemType Directory -Force -Path $legacyDest | Out-Null
        Copy-Item -Force $legacyBundled (Join-Path $legacyDest "registry.json")
        $legacySchema = Join-Path $CliDir "legacy-libs/registry.schema.json"
        if (Test-Path $legacySchema) {
            Copy-Item -Force $legacySchema (Join-Path $legacyDest "registry.schema.json")
        }
        Ok "Legacy library registry installed at $legacyDest\registry.json"
    }

    Install-Plugins
    Install-Desktop

    Info "Installing the 'chroma' command..."
    Copy-Item -Force $PSCommandPath (Join-Path $ChromaBin "chroma.ps1")
    $shimPath = Join-Path $ChromaBin "chroma.cmd"
    $shimContent = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0chroma.ps1`" %*"
    Set-Content -Path $shimPath -Value $shimContent -Encoding ASCII
    Ok "chroma installed at $ChromaBin (chroma.ps1 + chroma.cmd shim)"

    Install-VersionFile

    Add-ChromaToPath

    Write-Host ""
    Ok "Chroma environment ready ($(Get-ChromaVersionString))."
    Write-Host "  Open a new terminal and try:"
    Write-Host "    chroma new my-app --template static"
    Write-Host "    cd my-app; chroma dev"
}

function Add-ChromaToPath {
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -and ($currentPath -split ';' -contains $ChromaBin)) {
        Ok "PATH already includes $ChromaBin"
        return
    }
    $newPath = if ($currentPath) { "$ChromaBin;$currentPath" } else { $ChromaBin }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:PATH = "$ChromaBin;$env:PATH"
    Warn "Added $ChromaBin to the user PATH — open a new terminal for it to take effect everywhere."
}

# ── new ──────────────────────────────────────────────────────────────────────
function New-ChromaApp {
    param([string[]]$Arguments)

    $name = $null
    $template = "static"
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        if ($Arguments[$i] -eq "--template") {
            $template = $Arguments[$i + 1]
            $i++
        } elseif ($Arguments[$i] -match '^--template=(.*)$') {
            $template = $Matches[1]
        } elseif (-not $name) {
            $name = $Arguments[$i]
        }
    }

    if (-not $name) { Fail "Usage: chroma new <name> [--template static|dynamic|standard]" }
    if ($template -ne "static" -and $template -ne "dynamic" -and $template -ne "standard") {
        Fail "Invalid template: '$template' (use 'static', 'dynamic', or 'standard')"
    }

    $templateDir = Join-Path $ChromaTemplates $template
    if (-not (Test-Path $templateDir)) {
        Fail "Chroma environment not found at $ChromaHome. Run 'chroma install' first (from the repo)."
    }
    if (Test-Path $name) { Fail "'$name' already exists in the current directory." }
    if (-not (Test-Path (Join-Path $ChromaEngineSrc "pkg"))) {
        Fail "Compiled engine not found at $ChromaEngineSrc\pkg. Run 'chroma install' first."
    }

    Info "Creating app '$name' (template: $template)..."
    New-Item -ItemType Directory -Force -Path $name | Out-Null
    Copy-Item -Recurse -Force (Join-Path $templateDir "*") $name

    $pkgDest = Join-Path $name "pkg"
    New-Item -ItemType Directory -Force -Path $pkgDest | Out-Null
    Copy-Item -Recurse -Force (Join-Path $ChromaEngineSrc "pkg/*") $pkgDest

    Set-JsonName (Join-Path $name "package.json") $name
    Set-JsonName (Join-Path $name "chroma.json") $name
    Vendor-Plugins -Project $name

    Ok "App created at .\$name"
    Write-Host "  cd $name; chroma dev"
}

# ── serve (production-like static preview) ─────────────────────────────────────
function Invoke-ChromaServe {
    param([string[]]$Arguments)

    if (-not (Test-Path "chroma.json")) {
        Fail "chroma.json not found in the current directory. Run this inside an app created with 'chroma new'."
    }
    if (-not (Test-Path $ChromaEngineBin)) {
        Fail "engine binary not found at $ChromaEngineBin. Run 'chroma install'."
    }

    $cfg = Get-Content -Raw "chroma.json" | ConvertFrom-Json
    $port = if ($cfg.dev.port) { $cfg.dev.port } else { 4173 }
    $outDir = if ($cfg.outDir) { $cfg.outDir } else { "dist" }
    $entry = if ($cfg.entry) { $cfg.entry } else { "index.html" }

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        if ($arg -eq "--port") {
            $port = $Arguments[$i + 1]
            $i++
        } elseif ($arg -match '^--port=(.*)$') {
            $port = $Matches[1]
        } elseif ($arg -eq "--dir") {
            $outDir = $Arguments[$i + 1]
            $i++
        } elseif ($arg -match '^--dir=(.*)$') {
            $outDir = $Matches[1]
        } elseif ($arg -in @("--static", "--no-desktop", "--no-hot-reload", "--no-reload", "--hot-reload", "--reload")) {
            continue
        } else {
            Fail "Unknown option for 'chroma serve': $arg (use --port <n> or --dir <path>)"
        }
    }

    if (-not (Test-Path $outDir -PathType Container)) {
        Fail "Build output not found at $outDir/. Run 'chroma build' first."
    }
    $entryPath = Join-Path $outDir $entry
    if (-not (Test-Path $entryPath)) {
        Fail "$entryPath not found. Run 'chroma build' or check chroma.json entry/outDir."
    }

    Info "Serving $outDir/ at http://127.0.0.1:${port}/ (production-like — no hot-reload)"
    $env:CHROMA_DEV_RELOAD = "0"
    & $ChromaEngineBin --port $port --dir $outDir --no-reload
}

# ── dev ──────────────────────────────────────────────────────────────────────
# Both templates are served the same way in development: they're ES modules
# the browser already understands without transforms. build is where
# static/dynamic actually diverge (plain minification vs. bundle + wasm).
# Serving uses the engine binary installed at $ChromaBin — nothing is
# vendored into the project for this, having the CLI installed is enough.
function Invoke-ChromaDev {
    param([string[]]$Arguments)

    if (-not (Test-Path "chroma.json")) {
        Fail "chroma.json not found in the current directory. Run this inside an app created with 'chroma new'."
    }
    if (-not (Test-Path $ChromaEngineBin)) {
        Fail "engine binary not found at $ChromaEngineBin. Run 'chroma install'."
    }

    if ($Arguments -contains "--static") {
        $filtered = $Arguments | Where-Object { $_ -ne "--static" }
        Invoke-ChromaServe -Arguments $filtered
        return
    }

    $cfg = Get-Content -Raw "chroma.json" | ConvertFrom-Json
    $port = if ($cfg.dev.port) { $cfg.dev.port } else { 4173 }
    $noDesktop = $false

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        if ($Arguments[$i] -eq "--port") {
            $port = $Arguments[$i + 1]
            $i++
        } elseif ($Arguments[$i] -match '^--port=(.*)$') {
            $port = $Matches[1]
        } elseif ($Arguments[$i] -eq "--no-desktop") {
            $noDesktop = $true
        } elseif ($Arguments[$i] -in @("--no-hot-reload", "--no-reload")) {
            $env:CHROMA_DEV_RELOAD = "0"
        } elseif ($Arguments[$i] -in @("--hot-reload", "--reload")) {
            $env:CHROMA_DEV_RELOAD = "1"
        }
    }

    $useDesktop = ($cfg.mode -eq "dynamic") -and ($cfg.dev.desktop -eq $true) -and (-not $noDesktop)
    if ($useDesktop) {
        Launch-DevWithDesktop -Port $port -Cfg $cfg
        return
    }

    $reloadArg = if (Test-ChromaDevReloadEnabled) { "--reload" } else { "--no-reload" }
    & $ChromaEngineBin --port $port --dir . $reloadArg
}

function Test-ChromaDevReloadEnabled {
    if (Test-Path "chroma.json") {
        $cfg = Get-Content -Raw "chroma.json" | ConvertFrom-Json
        if ($null -ne $cfg.dev -and $null -ne $cfg.dev.hotReload) {
            if ($cfg.dev.hotReload -eq $false) { return $false }
            if ($cfg.dev.hotReload -eq $true) { return $true }
        }
    }
    $envVal = $env:CHROMA_DEV_RELOAD
    if ($null -eq $envVal) { return $true }
    if ($envVal -in @("0", "false", "FALSE", "no", "NO")) { return $false }
    return $true
}

function Add-QueryParam {
    param([string]$Url, [string]$Key, [string]$Value)
    if ($Url -match '\?') { return "${Url}&${Key}=${Value}" }
    return "${Url}?${Key}=${Value}"
}

function Launch-DevWithDesktop {
    param([string]$Port, $Cfg)

    $entry = if ($Cfg.entry) { $Cfg.entry } else { "index.html" }
    $name = if ($Cfg.name) { $Cfg.name } else { "Chroma app" }
    $url = "http://127.0.0.1:${Port}/${entry}"
    $url = Add-QueryParam -Url $url -Key "chroma_no_reload" -Value "1"

    $desktopBin = Resolve-DesktopBin
    if (-not $desktopBin) {
        Fail "chroma-desktop not found. Run 'chroma install' from a full workspace checkout, or pass --no-desktop."
    }

    Info "Starting dev server on port $Port (hot-reload disabled for Desktop)..."
    $env:CHROMA_DEV_RELOAD = "0"
    $engine = Start-Process -FilePath $ChromaEngineBin -ArgumentList @("--port", $Port, "--dir", ".", "--no-reload") -PassThru -WindowStyle Hidden

    try {
        Start-Sleep -Milliseconds 400
        Info "Opening Chroma Desktop in develop mode..."
        & $desktopBin --develop --url $url --title $name
    } finally {
        if ($engine -and -not $engine.HasExited) {
            Stop-Process -Id $engine.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

# ── build ────────────────────────────────────────────────────────────────────
function Invoke-ChromaBuild {
    if (-not (Test-Path "chroma.json")) { Fail "chroma.json not found in the current directory." }
    $cfg = Get-Content -Raw "chroma.json" | ConvertFrom-Json
    $outDir = if ($cfg.outDir) { $cfg.outDir } else { "dist" }

    Ensure-JsConfig

    if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    switch ($cfg.mode) {
        "static" { Build-Static -Cfg $cfg -OutDir $outDir }
        "dynamic" { Build-Dynamic -Cfg $cfg -OutDir $outDir }
        default { Fail "Unknown mode in chroma.json: '$($cfg.mode)'" }
    }
}

function Build-Static {
    param($Cfg, [string]$OutDir)
    Assert-Node

    Info "Building static -> $OutDir/ (source files minified as written)"

    Minify-Html -Src $Cfg.entry -Dst (Join-Path $OutDir $Cfg.entry)

    foreach ($f in $Cfg.build.scripts) {
        $destDir = Join-Path $OutDir (Split-Path $f -Parent)
        if ($destDir) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        Invoke-Esbuild $f --minify --outfile="$(Join-Path $OutDir $f)"
    }
    foreach ($f in $Cfg.build.styles) {
        $destDir = Join-Path $OutDir (Split-Path $f -Parent)
        if ($destDir) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        Invoke-Esbuild $f --minify --outfile="$(Join-Path $OutDir $f)"
    }

    $vendorDir = $Cfg.engine.vendorDir
    Inline-WasmJs -VendorDir $vendorDir -OutDir (Join-Path $OutDir $vendorDir)

    if (Test-Path "plugins") {
        Copy-Item -Recurse -Force "plugins" (Join-Path $OutDir "plugins")
    }
    if (Test-Path "chroma-fs.json") {
        Copy-Item -Force "chroma-fs.json" (Join-Path $OutDir "chroma-fs.json")
    }
    Copy-Item -Force "chroma.json" (Join-Path $OutDir "chroma.json")
    Remove-DistMetadata $OutDir

    Ok "Static build ready: $OutDir/ (engine wasm inlined into minified chroma.js, no .wasm file, not recompiled)"
}

function Build-Dynamic {
    param($Cfg, [string]$OutDir)
    Assert-Node
    if (-not (Get-Command wasm-pack -ErrorAction SilentlyContinue)) { Fail "wasm-pack not found. Run 'chroma install'." }

    $vendorDir = $Cfg.engine.vendorDir
    $outfile = if ($Cfg.build.outfile) { $Cfg.build.outfile } else { "bundle.js" }

    if ($Cfg.engine.rebuildWasm) {
        if (-not (Test-Path $ChromaEngineSrc)) { Fail "Engine source not found at $ChromaEngineSrc. Run 'chroma install'." }
        Info "Recompiling the engine to WASM ($ChromaEngineSrc)..."
        Push-Location $ChromaEngineSrc
        wasm-pack build --target web
        Add-Content -Path (Join-Path (Get-Location).Path "pkg/chroma.js") -Value "`nawait __wbg_init();"
        Pop-Location
        if (Test-Path $vendorDir) { Remove-Item -Recurse -Force $vendorDir }
        New-Item -ItemType Directory -Force -Path $vendorDir | Out-Null
        Copy-Item -Recurse -Force (Join-Path $ChromaEngineSrc "pkg/*") $vendorDir
    } else {
        Warn "engine.rebuildWasm=false: using the engine already compiled at $vendorDir/"
    }

    Info "Bundling $($Cfg.build.jsEntry) -> $OutDir/$outfile (esbuild, .chr loader, minified)"
    Invoke-Esbuild $Cfg.build.jsEntry --bundle --format=esm --minify --outfile="$(Join-Path $OutDir $outfile)"

    # wasm-bindgen resolves the .wasm with `new URL(..., import.meta.url)`,
    # so it must sit next to the packaged bundle.
    Copy-Item -Force (Join-Path $vendorDir "chroma_bg.wasm") (Join-Path $OutDir "chroma_bg.wasm")

    Minify-Html -Src $Cfg.entry -Dst (Join-Path $OutDir $Cfg.entry) -From $Cfg.build.jsEntry -To $outfile

    if (Test-Path "plugins") {
        Copy-Item -Recurse -Force "plugins" (Join-Path $OutDir "plugins")
    }
    if (Test-Path "chroma-fs.json") {
        Copy-Item -Force "chroma-fs.json" (Join-Path $OutDir "chroma-fs.json")
    }
    Copy-Item -Force "chroma.json" (Join-Path $OutDir "chroma.json")
    Remove-DistMetadata $OutDir

    Ok "Dynamic build ready: $OutDir/"

    if ($Cfg.package.zip) {
        $zipPath = "$($Cfg.name).zip"
        if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
        Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zipPath
        Ok "Package ready: $zipPath"
    }
}

function Invoke-ChromaAdd {
    param([string[]]$Arguments)
    Assert-Node
    $addScript = Join-Path $CliDir "lib/chroma-add.mjs"
    if (-not (Test-Path $addScript)) {
        Fail "chroma add helper not found at $addScript (reinstall CLI from repo)."
    }
    $env:CHROMA_HOME = $ChromaHome
    & node $addScript @Arguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-ChromaFs {
    param([string[]]$Arguments)

    $sub = if ($Arguments.Count -gt 0) { $Arguments[0] } else { "" }
    switch ($sub) {
        "init" { Invoke-ChromaFsInit }
        "link" { Invoke-ChromaFsLink }
        default { Fail "Usage: chroma fs <init|link>" }
    }
}

function Invoke-ChromaFsInit {
    if (-not (Test-Path "chroma.json")) {
        Fail "chroma.json not found in the current directory."
    }
    if (Test-Path "chroma-fs.json") {
        Fail "chroma-fs.json already exists."
    }

    $cfg = Get-Content -Raw "chroma.json" | ConvertFrom-Json
    if ($cfg.mode -eq "dynamic") {
        @'
{
  "storage": {
    "backend": "filesystem",
    "basePath": "./data"
  }
}
'@ | Set-Content -Path "chroma-fs.json" -Encoding UTF8
        Ok "Created chroma-fs.json (backend: filesystem)"
    } else {
        @'
{
  "storage": {
    "backend": "indexeddb",
    "indexedDb": {
      "dbName": "chroma-fs",
      "storeName": "files"
    }
  }
}
'@ | Set-Content -Path "chroma-fs.json" -Encoding UTF8
        Ok "Created chroma-fs.json (backend: indexeddb)"
    }
}

function Invoke-ChromaFsLink {
    Assert-Node
    $fsSrc = Resolve-ChromaFsSrc
    if (-not $fsSrc) {
        Fail "Chroma-Fs source not found. Run from the TargApps workspace."
    }

    Info "Building Chroma-Fs..."
    Push-Location $fsSrc
    npm install --silent
    npm run build
    Pop-Location

    if (-not (Test-Path "package.json")) {
        Fail "package.json not found in the current directory."
    }

    $pkg = Get-Content -Raw "package.json" | ConvertFrom-Json
    if (-not $pkg.dependencies) {
        $pkg | Add-Member -NotePropertyName dependencies -NotePropertyValue ([PSCustomObject]@{})
    }
    $pkg.dependencies | Add-Member -NotePropertyName "@chroma/fs" -NotePropertyValue "file:$fsSrc" -Force
    $pkg | ConvertTo-Json -Depth 10 | Set-Content -Path "package.json" -Encoding UTF8
    npm install --silent
    Ok "@chroma/fs linked from $fsSrc"
}

function Invoke-ChromaValidate {
    if (-not (Test-Path "chroma.json")) {
        Fail "chroma.json not found in the current directory."
    }
    $cfg = Get-Content -Raw "chroma.json" | ConvertFrom-Json
    if (-not $cfg.name) { Fail "chroma.json: missing required field 'name'" }
    if ($cfg.mode -notin @("static", "dynamic")) {
        Fail "chroma.json: mode must be 'static' or 'dynamic' (template 'standard' uses dynamic)."
    }
    $entry = if ($cfg.entry) { $cfg.entry } else { "index.html" }
    if (-not (Test-Path $entry)) { Fail "chroma.json: entry file not found: $entry" }
    $vendor = if ($cfg.engine -and $cfg.engine.vendorDir) { $cfg.engine.vendorDir } else { "pkg" }
    if (-not (Test-Path (Join-Path $vendor "chroma.js"))) {
        Fail "chroma.json: engine vendor dir missing pkg at $vendor/chroma.js"
    }
    if ($cfg.mode -eq "dynamic") {
        if (-not $cfg.build -or -not $cfg.build.jsEntry) {
            Fail "chroma.json: dynamic mode requires build.jsEntry"
        }
        if (-not (Test-Path $cfg.build.jsEntry)) {
            Fail "chroma.json: build.jsEntry not found: $($cfg.build.jsEntry)"
        }
    }
    Warn-LegacyJsInSrc
    if ($cfg.plugins) {
        foreach ($pid in $cfg.plugins) {
            $plugDir = Join-Path "plugins" $pid
            if (-not (Test-Path $plugDir)) {
                Fail "chroma.json: plugin '$pid' missing at $plugDir"
            }
        }
    }
    Ok "Validation passed (structure)"
}

# ── dispatch ─────────────────────────────────────────────────────────────────
switch ($Command) {
    { $_ -in @("help", "--help", "-h", "--version", "-v") } { }
    default { Show-ChromaStartup }
}

switch ($Command) {
    "install" { Install-Chroma -Arguments $Rest }
    "new"     { New-ChromaApp -Arguments $Rest }
    "init"    { New-ChromaApp -Arguments $Rest }
    "dev"     { Invoke-ChromaDev -Arguments $Rest }
    "serve"   { Invoke-ChromaServe -Arguments $Rest }
    "build"   { Invoke-ChromaBuild }
    "validate" { Invoke-ChromaValidate }
    "add"     { Invoke-ChromaAdd -Arguments $Rest }
    "fs"      { Invoke-ChromaFs -Arguments $Rest }
    "help"    { Show-Usage }
    "--help"  { Show-Usage }
    "-h"      { Show-Usage }
    "--version" { Show-ChromaVersion }
    "-v"        { Show-ChromaVersion }
    default {
        Err "Unknown command: $Command"
        Write-Host ""
        Show-Usage
        exit 1
    }
}
