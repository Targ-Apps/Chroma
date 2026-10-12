#!/usr/bin/env node
/**
 * Vendors UMD/global legacy libraries from Chroma/cli/legacy-libs/registry.json into the cwd app.
 * Invoked by chroma.sh / chroma.ps1 (`chroma add <lib-id>`).
 *
 * First-party plugins: use `chroma install` (~/.chroma/plugins) or copy into ./plugins/ manually.
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
const __CLI_LIB_DIR = path.dirname(fileURLToPath(import.meta.url));

const HELP = `Usage: chroma add <lib-id> [options]

Vendor a third-party UMD/global script from Chroma/cli/legacy-libs/registry.json into the
current Chroma app (files under vendor/<id>/, legacyLibraries[] in chroma.json, index.html hooks).

First-party Chroma plugins (chroma-fs, chroma-style, chroma-router, chroma-t2t):
  Use chroma install (populates ~/.chroma/plugins/) and chroma new / manual copy into ./plugins/.
  chroma add does not install plugin packages.

Options:
  --list              List UMD/global library ids from the registry
  --registry <path>   Override registry.json location
  --force             Re-download / overwrite vendored files and refresh manifest hooks
  --dry-run           Print actions without writing files
  -h, --help          Show this message

Examples:
  chroma add dayjs
  chroma add echarts --force
  chroma add --list
`;

function parseArgs(argv) {
  const opts = {
    list: false,
    dryRun: false,
    force: false,
    help: false,
    libId: null,
    registry: null,
    cwd: process.cwd(),
  };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--help" || a === "-h") opts.help = true;
    else if (a === "--list") opts.list = true;
    else if (a === "--dry-run") opts.dryRun = true;
    else if (a === "--force") opts.force = true;
    else if (a === "--registry") opts.registry = argv[++i];
    else if (a.startsWith("--registry=")) opts.registry = a.slice("--registry=".length);
    else if (a.startsWith("-")) {
      console.error(`Unknown option: ${a}`);
      process.exit(1);
    } else rest.push(a);
  }
  opts.libId = rest[0] ?? null;
  return opts;
}

function defaultRegistryPath() {
  return path.resolve(__CLI_LIB_DIR, "..", "legacy-libs", "registry.json");
}

function resolveRegistry(explicit) {
  if (explicit && fs.existsSync(explicit)) return path.resolve(explicit);
  const candidates = [
    process.env.CHROMA_LEGACY_REGISTRY,
    process.env.CHROMA_HOME ? path.join(process.env.CHROMA_HOME, "legacy-libs", "registry.json") : null,
    defaultRegistryPath(),
  ].filter(Boolean);
  for (const c of candidates) {
    if (fs.existsSync(c)) return path.resolve(c);
  }
  return null;
}

function registryVendorRoot(registryPath) {
  return path.join(path.dirname(registryPath), "vendor");
}

function loadPluginsById() {
  const pluginsPath = path.join(path.dirname(defaultRegistryPath()), "plugins-registry.json");
  if (!fs.existsSync(pluginsPath)) return new Map();
  const raw = JSON.parse(fs.readFileSync(pluginsPath, "utf8"));
  const byId = new Map();
  for (const lib of raw.libraries ?? []) {
    if (lib?.id) byId.set(lib.id, lib);
  }
  return byId;
}

function loadRegistry(registryPath) {
  const raw = JSON.parse(fs.readFileSync(registryPath, "utf8"));
  const libs = raw.libraries ?? [];
  const byId = new Map();
  for (const lib of libs) {
    if (lib?.id) byId.set(lib.id, lib);
  }
  return { raw, byId, registryPath, vendorRoot: registryVendorRoot(registryPath) };
}

function isGlobalLib(lib) {
  return Boolean(lib.chromaJson?.global && (lib.files?.length ?? 0) > 0);
}

function log(msg) {
  console.log(msg);
}

async function downloadUrl(url, dest, dryRun) {
  if (dryRun) {
    log(`[dry-run] fetch ${url} -> ${dest}`);
    return;
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} for ${url}`);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  fs.writeFileSync(dest, buf);
}

function copyFile(src, dest, dryRun) {
  if (dryRun) {
    log(`[dry-run] copy ${src} -> ${dest}`);
    return;
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

async function vendorGlobalFiles(cwd, lib, vendorRoot, force, dryRun) {
  const primary = lib.cdn?.primary;
  const urls = [primary, ...(lib.cdn?.fallbacks ?? [])].filter(Boolean);
  if (urls.length === 0) {
    console.error(`Registry entry ${lib.id} has no cdn.primary URL.`);
    process.exit(1);
  }

  for (const fileEntry of lib.files ?? []) {
    const appPath = fileEntry.path;
    const dest = path.join(cwd, appPath);
    if (fs.existsSync(dest) && !force) {
      console.error(`Already vendored at ${appPath}. Pass --force to overwrite.`);
      process.exit(1);
    }

    const mirrorRel = appPath.replace(/^vendor\//, "");
    const mirror = path.join(vendorRoot, mirrorRel);
    if (fs.existsSync(mirror)) {
      copyFile(mirror, dest, dryRun);
      continue;
    }

    let lastErr = null;
    for (const url of urls) {
      try {
        await downloadUrl(url, dest, dryRun);
        lastErr = null;
        break;
      } catch (e) {
        lastErr = e;
      }
    }
    if (lastErr) {
      console.error(`Failed to download ${lib.id}: ${lastErr.message}`);
      process.exit(1);
    }
  }
}

function normalizeLegacyLibraries(manifest) {
  const raw = manifest.legacyLibraries;
  if (!raw) return [];
  if (Array.isArray(raw)) return [...raw];
  if (typeof raw === "object") {
    return Object.entries(raw).map(([id, meta]) => ({
      id,
      ...(typeof meta === "object" && meta !== null ? meta : {}),
    }));
  }
  return [];
}

function updateChromaJson(cwd, lib, dryRun) {
  const manifestPath = path.join(cwd, "chroma.json");
  if (!fs.existsSync(manifestPath)) {
    console.error("chroma.json not found in the current directory.");
    process.exit(1);
  }
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const list = normalizeLegacyLibraries(manifest);
  const idx = list.findIndex((e) => e.id === lib.id);
  const entry = {
    id: lib.id,
    source: "vendor",
    version: lib.version,
  };
  if (idx >= 0) list[idx] = { ...list[idx], ...entry };
  else list.push(entry);
  list.sort((a, b) => (a.id ?? "").localeCompare(b.id ?? ""));
  manifest.legacyLibraries = list;

  const staticBuild = lib.chromaJson?.hooks?.staticBuild;
  if (manifest.mode === "static" && staticBuild === "append-scripts") {
    manifest.build = manifest.build ?? {};
    const scripts = new Set(manifest.build.scripts ?? []);
    for (const f of lib.files ?? []) {
      if (f.role === "script") scripts.add(f.path);
    }
    manifest.build.scripts = [...scripts];
  }

  if (dryRun) {
    log(`[dry-run] update chroma.json legacyLibraries[] (${lib.id})`);
    return manifest;
  }
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}

const HOOK_INSERT = {
  "indexHtml:head": { before: /<\/head>/i, label: "head" },
  "indexHtml:body-start": { after: /<body[^>]*>/i, label: "body-start" },
  "indexHtml:body-end": { before: /<\/body>/i, label: "body-end" },
};

function scriptTag(fileEntry, libId) {
  const src = fileEntry.path;
  const integrity = fileEntry.integrity ? ` integrity="${fileEntry.integrity}"` : "";
  if (fileEntry.role === "style") {
    return `<link rel="stylesheet" href="${src}" data-chroma-legacy-lib="${libId}"${integrity}>`;
  }
  return `<script src="${src}" defer data-chroma-legacy-lib="${libId}"${integrity}></script>`;
}

function injectIndexHtml(cwd, lib, manifest, dryRun) {
  const hook = lib.chromaJson?.hooks?.load ?? "indexHtml:head";
  if (hook === "static:scripts") return;

  const htmlName = manifest.entry ?? "index.html";
  const htmlPath = path.join(cwd, htmlName);
  if (!fs.existsSync(htmlPath)) {
    log(`Skip index.html injection (${htmlName} not found).`);
    return;
  }

  let html = fs.readFileSync(htmlPath, "utf8");
  const markerRe = new RegExp(
    `<!-- chroma:legacy-lib:${lib.id} -->[\\s\\S]*?<!-- /chroma:legacy-lib:${lib.id} -->\\s*`,
    "g",
  );
  html = html.replace(markerRe, "");

  const block = [
    `<!-- chroma:legacy-lib:${lib.id} -->`,
    ...(lib.files ?? []).map((f) => scriptTag(f, lib.id)),
    `<!-- /chroma:legacy-lib:${lib.id} -->`,
  ].join("\n    ");

  const spec = HOOK_INSERT[hook];
  if (!spec) {
    log(`Unknown hooks.load "${hook}"; skipping HTML injection.`);
    return;
  }

  if (spec.before && spec.before.test(html)) {
    html = html.replace(spec.before, `    ${block}\n  $&`);
  } else if (spec.after) {
    html = html.replace(spec.after, (m) => `${m}\n    ${block}`);
  } else {
    log(`Could not find insertion point for ${hook} in ${htmlName}.`);
    return;
  }

  if (dryRun) {
    log(`[dry-run] inject legacy scripts into ${htmlName} (${hook})`);
    return;
  }
  fs.writeFileSync(htmlPath, html);
  log(`Updated ${htmlName} (${hook})`);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log(HELP);
    return;
  }

  const registryPath = resolveRegistry(opts.registry);
  if (!registryPath) {
    console.error(
      "Legacy library registry not found. Set CHROMA_LEGACY_REGISTRY or run chroma install (bundled registry under $CHROMA_HOME/legacy-libs/).",
    );
    process.exit(1);
  }

  const { byId, vendorRoot } = loadRegistry(registryPath);

  if (opts.list) {
    for (const lib of byId.values()) {
      if (!isGlobalLib(lib)) continue;
      console.log(`${lib.id}\t${lib.version}\t${lib.name}`);
    }
    return;
  }

  if (!opts.libId) {
    console.error("Missing <lib-id>. Try: chroma add --list");
    process.exit(1);
  }

  const pluginsById = loadPluginsById();
  const lib = byId.get(opts.libId);
  if (!lib) {
    if (pluginsById.has(opts.libId)) {
      console.error(
        `${opts.libId} is a first-party Chroma plugin. Use chroma install and copy from ~/.chroma/plugins/, not chroma add.`,
      );
      process.exit(1);
    }
    console.error(`Unknown library id: ${opts.libId}. Try: chroma add --list`);
    process.exit(1);
  }

  if (lib.chromaJson?.plugin || lib.install?.dest?.startsWith("plugins/")) {
    console.error(
      `${opts.libId} is a first-party Chroma plugin. Use chroma install and copy from ~/.chroma/plugins/, not chroma add.`,
    );
    process.exit(1);
  }

  if (!isGlobalLib(lib)) {
    console.error(`Registry entry ${lib.id} is not a UMD/global library (missing files or chromaJson.global).`);
    process.exit(1);
  }

  await vendorGlobalFiles(opts.cwd, lib, vendorRoot, opts.force, opts.dryRun);
  const manifest = updateChromaJson(opts.cwd, lib, opts.dryRun);
  injectIndexHtml(opts.cwd, lib, manifest, opts.dryRun);

  log(`Added ${lib.id}@${lib.version} (vendor + legacyLibraries + index.html)`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
