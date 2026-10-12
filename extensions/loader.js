/**
 * Standard extension loader — vanilla browser JS, no bundler and no Node.
 *
 * Mirrors the `plugins` convention already used by `chroma new` scaffolds
 * (see cli/examples/*\/plugins/loader.js: a `chroma.json` array of names,
 * resolved from a local folder). Extensions are the CSS/design-system
 * counterpart of plugins: every extension is a folder with an
 * `extension.json` manifest —
 *
 * ```json
 * { "name": "styling", "version": "0.1.0", "type": "styling",
 *   "styles": ["tokens.css", "utilities.css"], "entry": "variants.js" }
 * ```
 *
 * — declaring `styles` (stylesheets appended to `<head>` once) and an
 * optional `entry` (an ES module, dynamically imported and returned to the
 * caller). Declare which ones to load in `chroma.json`:
 *
 * ```json
 * { "extensions": ["styling"] }
 * ```
 *
 * ```js
 * import { loadExtensions } from "./extensions/loader.js";
 * const { styling } = await loadExtensions();
 * const { createVariants } = styling;
 * ```
 */
export async function loadExtensions(manifestUrl = "./chroma.json", extensionsRoot = "./extensions") {
    const manifest = await fetch(manifestUrl, { cache: "no-store" }).then((r) => r.json());
    const names = manifest.extensions ?? [];
    const loaded = {};

    for (const name of names) {
        const base = `${extensionsRoot}/${name}`;
        const meta = await fetch(`${base}/extension.json`, { cache: "no-store" }).then((r) => r.json());

        for (const href of meta.styles ?? []) {
            injectStylesheet(name, base, href);
        }

        loaded[name] = meta.entry ? await import(/* @vite-ignore */ `${base}/${meta.entry}`) : meta;
    }

    return loaded;
}

function injectStylesheet(extensionName, base, href) {
    const marker = `${extensionName}:${href}`;
    if (document.querySelector(`link[data-chroma-extension="${marker}"]`)) {
        return;
    }
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = `${base}/${href}`;
    link.dataset.chromaExtension = marker;
    document.head.appendChild(link);
}
