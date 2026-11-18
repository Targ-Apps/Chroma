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

    Write-HelpCmd 'recreate [path] [--template static|dynamic|standard] [--dry-run]'
    Write-HelpBody 'Restore the Chroma files a project is missing: pkg/, chroma.json, jsconfig.json, chroma-fs.json and listed runtime plugins.'
    Write-HelpKv 'When' 'A project has no pkg/ or chroma.json (fresh clone, deploy target, copied sources)'
    Write-HelpKv 'Why' 'Copies only what is absent from the installed templates; never overwrites or deletes anything'
    Write-HelpKv 'Flag' '--dry-run - list what would be created without writing'
    Write-HelpKv 'Example' 'chroma recreate ..\my-site --dry-run'

    Write-HelpCmd 'dev [--port <n>] [--no-desktop] [--static] [--no-reload | --reload]'
    Write-HelpBody 'Serve the project root with the engine dev server (needs chroma.json).'
    Write-HelpKv 'When' 'Day-to-day editing; default port from chroma.json or 4173'
    Write-HelpKv 'Why' 'Serves sources as ES modules; browser dev uses live reload'
    Write-HelpKv 'Plugins' 'Build plugins listed in chroma.json (chroma-mdx, chroma-blog, ...) compile .mdx on request and regenerate their files on change'
    Write-HelpKv 'Live reload' 'Full page refresh on source changes; off for Chroma Desktop develop'
    Write-HelpKv '--no-desktop' 'Browser only when dev.desktop is true'
    Write-HelpKv '--static' 'Same as chroma preview — run chroma build first'

    Write-HelpCmd 'preview [--port <n>] [--dir <path>]'
    Write-HelpBody 'Serve the build output (outDir) like a static host — no hot reload, no injection.'
    Write-HelpKv 'When' 'After chroma build; smoke-test dist\ before deploy'
    Write-HelpKv 'Why' 'Correct MIME types; same files a static host would serve'
    Write-HelpKv 'Alias' 'serve'

    Write-HelpCmd 'build'
    Write-HelpBody 'Compile and package into chroma.json outDir (default dist\; wiped each run).'
    Write-HelpKv 'When' 'Before deploy, preview, or Desktop zip import'
    Write-HelpKv 'Needs' 'Only the chroma CLI: no Node, no npm, no node_modules'

    Write-HelpCmd 'validate'
    Write-HelpBody 'Validate chroma.json (schema + structure); warns about node_modules, package.json dependencies and compile scripts\.'
    Write-HelpKv 'When' 'Before dev or build'

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
    Write-HelpBody 'ES modules; bundled by the Chroma compiler; optional engine.rebuildWasm.'
    Write-HelpCmd 'standard'
    Write-HelpBody 'Dynamic plus Chroma-Fs demo; dev.desktop default on.'
    Write-HelpBody 'All templates vendor pkg\. dev/preview/build use $env:CHROMA_HOME\bin\engine.exe — no package.json, no node_modules, no build scripts in the project.'

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

function Warn-LegacyJsInSrc {
    if (-not (Test-Path "src")) { return }
    Get-ChildItem -Path "src" -Filter "*.js" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        Warn "Legacy .js under src/: $($_.FullName.Substring((Get-Location).Path.Length + 1)) — use .chr for Chroma app source (see docs/chroma/chr-format)"
    }
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
    if ($fsSrc -and (Test-Path (Join-Path $fsSrc "dist"))) {
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
        Warn "Chroma-Fs build not found — plugin install skipped."
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

# Global build plugins that ship inside the engine binary (chroma.json "plugins" may list them).
$BuildPlugins = @("chroma-mdx", "chroma-blog", "chroma-seo", "chroma-icons", "chroma-style")

function Vendor-Plugins {
    param([string]$Project)
    $manifestPath = Join-Path $Project "chroma.json"
    if (-not (Test-Path $manifestPath)) { return }
    $cfg = Get-Content -Raw $manifestPath | ConvertFrom-Json
    if (-not $cfg.plugins) { return }
    foreach ($plugin in $cfg.plugins) {
        $src = Join-Path $ChromaPlugins $plugin
        if (-not (Test-Path $src)) {
            if ($BuildPlugins -contains $plugin) { continue }
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
    if (Test-Path $ChromaTemplates) { Remove-Item -Recurse -Force $ChromaTemplates }
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
        $pluginsReg = Join-Path $CliDir "legacy-libs/plugins-registry.json"
        if (Test-Path $pluginsReg) {
            Copy-Item -Force $pluginsReg (Join-Path $legacyDest "plugins-registry.json")
        }
        $legacyVendor = Join-Path $CliDir "legacy-libs/vendor"
        if (Test-Path $legacyVendor) {
            New-Item -ItemType Directory -Force -Path (Join-Path $legacyDest "vendor") | Out-Null
            Copy-Item -Recurse -Force (Join-Path $legacyVendor "*") (Join-Path $legacyDest "vendor")
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

    Set-JsonName (Join-Path $name "chroma.json") $name
    Vendor-Plugins -Project $name

    Ok "App created at .\$name"
    Write-Host "  cd $name; chroma dev"
}

# ── preview / serve (production-like static preview) ──────────────────────────
# `chroma serve` is the older name of `chroma preview` and stays as an alias.
function Invoke-ChromaPreview {
    param([string[]]$Arguments)

    if (-not (Test-Path "chroma.json")) {
        Fail "chroma.json not found in the current directory. Run this inside an app created with 'chroma new'."
    }
    if (-not (Test-Path $ChromaEngineBin)) {
        Fail "engine binary not found at $ChromaEngineBin. Run 'chroma install'."
    }

    $engineArgs = @("preview")
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        if ($arg -eq "--port" -or $arg -eq "--dir") {
            if ($i + 1 -ge $Arguments.Count) { Fail "$arg needs a value" }
            $engineArgs += @($arg, $Arguments[$i + 1])
            $i++
        } elseif ($arg -match '^--(port|dir)=(.*)$') {
            $engineArgs += @("--$($Matches[1])", $Matches[2])
        } elseif ($arg -in @("--static", "--no-desktop", "--no-hot-reload", "--no-reload", "--hot-reload", "--reload")) {
            continue
        } else {
            Fail "Unknown option for 'chroma preview': $arg (use --port <n> or --dir <path>)"
        }
    }

    $env:CHROMA_DEV_RELOAD = "0"
    & $ChromaEngineBin @engineArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-ChromaServe {
    param([string[]]$Arguments)
    Invoke-ChromaPreview -Arguments $Arguments
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
        Invoke-ChromaPreview -Arguments $filtered
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
    & $ChromaEngineBin dev --port $port --dir . $reloadArg
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
    $engine = Start-Process -FilePath $ChromaEngineBin -ArgumentList @("dev", "--port", $Port, "--dir", ".", "--no-reload") -PassThru -WindowStyle Hidden

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
# The whole build (bundle, minify, HTML, assets, build plugins, zip) is done by
# the engine binary: no Node, no npm, no esbuild.
function Invoke-ChromaBuild {
    param([string[]]$Arguments)
    if (-not (Test-Path "chroma.json")) { Fail "chroma.json not found in the current directory." }
    if (-not (Test-Path $ChromaEngineBin)) {
        Fail "engine binary not found at $ChromaEngineBin. Run 'chroma install'."
    }
    $env:CHROMA_HOME = $ChromaHome
    & $ChromaEngineBin build @Arguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-ChromaAdd {
    param([string[]]$Arguments)
    if (-not (Test-Path $ChromaEngineBin)) {
        Fail "engine binary not found at $ChromaEngineBin. Run 'chroma install'."
    }
    $env:CHROMA_HOME = $ChromaHome
    & $ChromaEngineBin add @Arguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Invoke-ChromaFs {
    param([string[]]$Arguments)

    $sub = if ($Arguments.Count -gt 0) { $Arguments[0] } else { "" }
    switch ($sub) {
        "init" { Invoke-ChromaFsInit }
        "link" { Fail "'chroma fs link' was removed: Chroma projects have no npm. Use the chroma-fs plugin (plugins/chroma-fs, copied by 'chroma new')." }
        default { Fail "Usage: chroma fs init" }
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

function Resolve-SchemasDir {
    foreach ($c in @($env:CHROMA_SCHEMAS, (Join-Path $ChromaHome "schemas"), (Join-Path $CliDir "schemas"))) {
        if ($c -and (Test-Path (Join-Path $c "chroma/chroma.schema.json"))) { return $c }
    }
    return $null
}

# Chroma projects have no Node, no npm and no node_modules: flag leftovers of the old toolchain.
function Warn-NodeLeftovers {
    if (Test-Path "node_modules") {
        Warn "node_modules/ found: Chroma projects have no node_modules. Delete it; import with relative paths or URLs."
    }
    if (Test-Path "package.json") {
        $raw = (Get-Content -Raw "package.json") -replace "[\r\n]", ""
        if ($raw -match '"(dependencies|devDependencies|optionalDependencies|peerDependencies)"\s*:\s*\{\s*"') {
            Warn "package.json declares dependencies: Chroma has no npm. Delete package.json."
        } elseif ($raw -match '"scripts"\s*:\s*\{[^}]*(npm |npx |node |esbuild|vite|webpack|rollup|tsc)') {
            Warn "package.json scripts call npm/node tools: use chroma dev, chroma preview and chroma build instead."
        }
    }
    if (Test-Path "scripts") {
        $hits = Get-ChildItem -Path "scripts" -Recurse -Depth 1 -File -Include *.mjs, *.js, *.cjs, *.ts, *.sh, *.ps1 -ErrorAction SilentlyContinue |
            Where-Object { Select-String -Path $_.FullName -Pattern 'esbuild|rollup|webpack|terser|minif|bundl|require\(|node:|npm |npx ' -Quiet }
        if ($hits) {
            Warn "scripts/ holds build scripts that Chroma no longer runs: $(($hits | ForEach-Object { $_.FullName }) -join ' ') — chroma build compiles by itself; remove them from the project."
        }
    }
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
        foreach ($plugId in $cfg.plugins) {
            $plugDir = Join-Path "plugins" $plugId
            if (-not (Test-Path $plugDir)) {
                # Global build plugins (chroma-mdx, chroma-blog, chroma-seo, chroma-icons, chroma-style) need no folder.
                if ($BuildPlugins -contains $plugId) { continue }
                Fail "chroma.json: plugin '$plugId' missing at $plugDir (global build plugins: $($BuildPlugins -join ', '))"
            }
        }
    }
    Warn-NodeLeftovers
    $schemaDir = Resolve-SchemasDir
    if ($schemaDir -and (Test-Path $ChromaEngineBin)) {
        & $ChromaEngineBin validate-schema (Join-Path $schemaDir "chroma/chroma.schema.json") (Resolve-Path "chroma.json").Path
        if ($LASTEXITCODE -ne 0) { Fail "chroma.json failed JSON Schema validation (see errors above)" }
        Ok "chroma.json matches chroma.schema.json"
    }
    Ok "Validation passed (structure)"
}

# ── recreate ─────────────────────────────────────────────────────────────────
# Restores the Chroma files a project is missing (pkg/, chroma.json, jsconfig.json, chroma-fs.json and the runtime
# plugins listed in chroma.json) from the installed templates. It ONLY adds what is absent: it never overwrites an
# existing file and never deletes anything, so project source is left exactly as it is.
function Copy-MissingFile {
    param([string]$Source, [string]$Dest, [string]$Root, [ref]$Counts, [bool]$DryRun)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return }
    $shown = $Dest.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
    if (Test-Path -LiteralPath $Dest) { $Counts.Value.Skipped++; return }
    $Counts.Value.Created++
    if ($DryRun) { Write-Host "  would create $shown"; return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Dest
    Write-Host "  + $shown"
}

function Copy-MissingTree {
    param([string]$SourceDir, [string]$DestDir, [string]$Root, [ref]$Counts, [bool]$DryRun)
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) { return }
    $base = (Resolve-Path -LiteralPath $SourceDir).Path
    Get-ChildItem -LiteralPath $base -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($base.Length).TrimStart('\', '/')
        Copy-MissingFile -Source $_.FullName -Dest (Join-Path $DestDir $rel) -Root $Root -Counts $Counts -DryRun $DryRun
    }
}

function Invoke-ChromaRecreate {
    param([string[]]$Arguments)

    $target = "."
    $template = ""
    $dryRun = $false
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = $Arguments[$i]
        if ($a -eq "--template") { $template = $Arguments[$i + 1]; $i++ }
        elseif ($a -match '^--template=(.*)$') { $template = $Matches[1] }
        elseif ($a -eq "--dry-run" -or $a -eq "-n") { $dryRun = $true }
        elseif ($a.StartsWith("-")) { Fail "Unknown option: $a" }
        else { $target = $a }
    }

    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        Fail "Usage: chroma recreate [path] [--template static|dynamic|standard] [--dry-run] - '$target' is not a directory."
    }
    $root = (Resolve-Path -LiteralPath $target).Path.TrimEnd('\', '/')
    if (-not (Test-Path $ChromaTemplates)) { Fail "Chroma environment not found at $ChromaHome. Run 'chroma install' first (from the repo)." }
    $enginePkg = Join-Path $ChromaEngineSrc "pkg"
    if (-not (Test-Path $enginePkg)) { Fail "Compiled engine not found at $enginePkg. Run 'chroma install' first." }

    $manifestPath = Join-Path $root "chroma.json"
    $hadManifest = Test-Path -LiteralPath $manifestPath
    $cfg = $null
    if ($hadManifest) { $cfg = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json }

    # Template: --template wins, then the project's own "mode", then a guess from its sources.
    if (-not $template -and $cfg -and $cfg.mode) { $template = [string]$cfg.mode }
    if (-not $template) {
        $srcDir = Join-Path $root "src"
        $hasChr = (Test-Path $srcDir) -and (Get-ChildItem -LiteralPath $srcDir -Recurse -Filter *.chr -File -ErrorAction SilentlyContinue | Select-Object -First 1)
        $template = if ($hasChr) { "dynamic" } else { "static" }
    }
    if ($template -ne "static" -and $template -ne "dynamic" -and $template -ne "standard") {
        Fail "Invalid template: '$template' (use 'static', 'dynamic', or 'standard')"
    }
    $tdir = Join-Path $ChromaTemplates $template
    if (-not (Test-Path $tdir)) { Fail "Template '$template' not found at $tdir. Run 'chroma install' first." }

    if ($dryRun) { Info "Dry run: nothing is written. Checking $root (template: $template)..." }
    else { Info "Restoring missing Chroma files in $root (template: $template). Existing files are never touched." }

    $counts = [pscustomobject]@{ Created = 0; Skipped = 0 }

    # 1. chroma.json (from the template, named after the folder).
    if (-not $hadManifest) {
        Copy-MissingFile -Source (Join-Path $tdir "chroma.json") -Dest $manifestPath -Root $root -Counts ([ref]$counts) -DryRun $dryRun
        if (-not $dryRun -and (Test-Path -LiteralPath $manifestPath)) { Set-JsonName $manifestPath (Split-Path -Leaf $root) }
    }
    $sourceManifest = if (Test-Path -LiteralPath $manifestPath) { $manifestPath } else { Join-Path $tdir "chroma.json" }
    $srcCfg = Get-Content -Raw -LiteralPath $sourceManifest | ConvertFrom-Json

    # 2. pkg/ (engine glue + WASM), at engine.vendorDir.
    $vendor = "pkg"
    if ($srcCfg.engine -and $srcCfg.engine.vendorDir) { $vendor = [string]$srcCfg.engine.vendorDir }
    if ($vendor.StartsWith("/") -or $vendor.StartsWith("\") -or $vendor.Contains("..") -or [System.IO.Path]::IsPathRooted($vendor)) {
        Fail "engine.vendorDir '$vendor' must be a relative path inside the project."
    }
    Copy-MissingTree -SourceDir $enginePkg -DestDir (Join-Path $root $vendor) -Root $root -Counts ([ref]$counts) -DryRun $dryRun
    $havePkg = Join-Path (Join-Path $root $vendor) "package.json"
    $wantPkg = Join-Path $enginePkg "package.json"
    if ((Test-Path -LiteralPath $havePkg) -and (Test-Path -LiteralPath $wantPkg)) {
        $have = (Get-Content -Raw -LiteralPath $havePkg | ConvertFrom-Json).version
        $want = (Get-Content -Raw -LiteralPath $wantPkg | ConvertFrom-Json).version
        if ($have -and $want -and $have -ne $want) {
            Warn "$vendor/ is engine $have; the installed engine is $want. recreate never replaces existing files: copy $enginePkg over it yourself if you want to update."
        }
    }

    # 3. Editor config and the Chroma-Fs config, only when the project uses them.
    Copy-MissingFile -Source (Join-Path $tdir "jsconfig.json") -Dest (Join-Path $root "jsconfig.json") -Root $root -Counts ([ref]$counts) -DryRun $dryRun
    $plugins = @()
    if ($srcCfg.plugins) { $plugins = @($srcCfg.plugins) }
    if ($plugins -contains "chroma-fs") {
        Copy-MissingFile -Source (Join-Path $tdir "chroma-fs.json") -Dest (Join-Path $root "chroma-fs.json") -Root $root -Counts ([ref]$counts) -DryRun $dryRun
    }

    # 4. Runtime plugins listed in chroma.json (build plugins live inside the engine and need no files).
    $hasRuntime = $false
    foreach ($plugin in $plugins) {
        $src = Join-Path $ChromaPlugins $plugin
        if (Test-Path $src) {
            if ($BuildPlugins -notcontains $plugin) { $hasRuntime = $true }
            Copy-MissingTree -SourceDir $src -DestDir (Join-Path (Join-Path $root "plugins") $plugin) -Root $root -Counts ([ref]$counts) -DryRun $dryRun
        } elseif ($BuildPlugins -notcontains $plugin) {
            Warn "Plugin '$plugin' is listed in chroma.json but not installed at $src; skipped."
        }
    }
    if ($hasRuntime) {
        Copy-MissingFile -Source (Join-Path (Join-Path $tdir "plugins") "loader.js") -Dest (Join-Path (Join-Path $root "plugins") "loader.js") -Root $root -Counts ([ref]$counts) -DryRun $dryRun
    }

    if ($counts.Created -eq 0) {
        Ok "Nothing to restore: all Chroma files are already there ($($counts.Skipped) checked, none changed)."
    } elseif ($dryRun) {
        Ok "Dry run: $($counts.Created) file(s) would be created, $($counts.Skipped) existing file(s) left alone."
    } else {
        Ok "Restored $($counts.Created) file(s); $($counts.Skipped) existing file(s) left untouched."
        Write-Host "  cd $target; chroma validate"
    }
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
    "recreate" { Invoke-ChromaRecreate -Arguments $Rest }
    "dev"     { Invoke-ChromaDev -Arguments $Rest }
    "preview" { Invoke-ChromaPreview -Arguments $Rest }
    "serve"   { Invoke-ChromaServe -Arguments $Rest }
    "build"   { Invoke-ChromaBuild -Arguments $Rest }
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
