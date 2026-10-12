/**
 * Loads Chroma plugins declared in chroma.json.
 * Each plugin folder includes chroma.plugin.json (entry, hooks, capabilities).
 * Plugin packages are vendored under plugins/<name>/ by `chroma new`.
 */
export async function loadPlugins(options = {}) {
    const { manifestUrl = "./chroma.json", pluginsRoot = "./plugins" } = options;
    const manifest = await fetch(manifestUrl, { cache: "no-store" }).then((r) => r.json());
    const names = manifest.plugins ?? [];
    const loaded = {};

    for (const name of names) {
        const base = `${pluginsRoot}/${name}`;
        let meta;

        try {
            const res = await fetch(`${base}/chroma.plugin.json`, { cache: "no-store" });
            if (!res.ok) throw new Error("missing chroma.plugin.json");
            meta = await res.json();
        } catch {
            const legacy = await loadLegacyPlugin(name, base);
            if (legacy !== undefined) {
                loaded[legacy.key] = legacy.value;
            }
            continue;
        }

        const entry = meta.entry ?? "index.js";
        const mod = await import(`${base}/${entry}`);
        const key = meta.loadAs ?? name.replace(/^chroma-/, "");

        if (meta.hooks?.styles) {
            const inject = mod[meta.hooks.styles];
            if (typeof inject === "function") inject();
        }

        if (meta.hooks?.bootstrap) {
            const bootstrap = mod[meta.hooks.bootstrap];
            if (typeof bootstrap === "function") {
                const bootstrapOpts =
                    key === "router" ? (options.router ?? { manifestUrl: "./api/routes-manifest.json" }) : undefined;
                loaded[key] = bootstrapOpts !== undefined ? await bootstrap(bootstrapOpts) : await bootstrap();
                continue;
            }
        }

        loaded[key] = mod;
    }

    return loaded;
}

/** Fallback until chroma-fs ships chroma.plugin.json */
async function loadLegacyPlugin(name, base) {
    if (name === "chroma-fs") {
        const { createStorage } = await import(`${base}/index.js`);
        return {
            key: "fs",
            value: await createStorage({ configPath: "./chroma-fs.json" }),
        };
    }
    console.warn(`[loadPlugins] '${name}' has no chroma.plugin.json — skipped`);
    return undefined;
}
