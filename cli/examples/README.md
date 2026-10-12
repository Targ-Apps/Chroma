# Chroma CLI app templates (`chroma new`)

Templates copied by `chroma new <name> --template static|dynamic|standard` live in `standard/`, `dynamic/`, and `static/`.

## `.chr` — canonical app source

**Chroma UI** under `src/` uses `**/*.chr` (language id `chroma` in the VS Code/Cursor extension). Files are ESM JavaScript; only the extension differs.

- **Dynamic / standard** — `src/main.chr`, `src/App.chr`, and `src/components/*.chr`; `chroma.json` → `build.jsEntry` points at `src/main.chr`.
- **Static** — root `index.js` (no `src/` bundle entry); plugins and `pkg/` stay `.js`.

`chroma validate` accepts `.chr` for `build.jsEntry` and warns if legacy `.js` files remain under `src/`. `chroma build` passes `--loader:.chr=js` to esbuild; `chroma dev` serves `.chr` as `text/javascript` via the engine.

See [`.chr` source format](https://docs.targapps.xyz/docs/chroma/reference/chr-format) in the docs.

Plugins (`plugins/`), the engine (`pkg/`), and JSON manifests (`chroma.json`, etc.) are unchanged.
