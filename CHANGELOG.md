# Changelog

All notable changes to the Chroma engine and CLI are documented here.

## 0.6.0

- New: `chroma preview --host <ip>` (and `engine preview --host <ip>`) binds another address, for example `0.0.0.0` to serve other machines from a server or a VM. The default stays `127.0.0.1`; a non-loopback address logs a warning because the server has no TLS and no authentication. NorOS uses it to run deployed Chroma apps.

- Fix: without `jq`, `chroma recreate`, `chroma new` and `chroma validate` read the `plugins` array of a multi-line `chroma.json` (they found nothing) and stopped with an error when a key such as `plugins` was absent (`set -e` + `pipefail`). The `json_array` and `json_field` helpers now join lines and treat a missing key as empty. This is what stopped `chroma recreate` inside slim Docker images, which have no `jq`.

## 0.5.0

- New: `chroma recreate [path] [--template static|dynamic|standard] [--dry-run]` restores the Chroma files a project is missing (`pkg/`, `chroma.json`, `jsconfig.json`, `chroma-fs.json` and the runtime plugins listed in `chroma.json`) from the installed templates and engine. It only adds what is absent: it never overwrites or deletes anything, so project sources are untouched. Meant for fresh clones, deploy targets, and copied sources without `pkg/` or `chroma.json`.

## 0.4.0

Chroma no longer needs Node.js, npm, esbuild, or `node_modules` in any project. `chroma dev`, `chroma preview`, `chroma build`, and `chroma add` depend only on the CLI and its `engine` binary (Chroma-Server 0.2.0), which now contains Chroma's own compiler built on Oxc (`chroma-compiler`) and the global build plugins (`chroma-plugins`).

- New: `chroma preview [--port] [--dir]` serves the build output like a static host (no hot reload). `chroma serve` stays as an alias.
- New: `engine build`, `engine preview`, `engine dev`, `engine add`, `engine minify`, and `engine validate-schema` subcommands. Plain `engine --port --dir` still works.
- Change: `chroma build` bundles, transpiles, and minifies with the Chroma compiler; static mode minifies scripts and CSS and inlines the WASM engine without Node; HTML is minified without touching `<script>`, `<style>`, `<pre>`, or `<textarea>`. The output also gets `assets/`, the contents of `public/` (copied to the root of `outDir`), and the local files `index.html` points to.
- Change: `chroma add` runs inside the engine (no Node). Missing files are downloaded with the system `curl`.
- Change: `chroma validate` checks the schema with the engine (no `npm install ajv`), accepts global build plugin names in `plugins`, and warns about `node_modules/`, a `package.json` with dependencies or scripts that call npm/node, and `scripts/` files that bundle or minify. `--strict` turns those warnings into errors.
- New: `chroma.json` `plugins` accepts the global build plugins `chroma-mdx`, `chroma-blog`, `chroma-seo`, `chroma-icons`, and `chroma-style` next to runtime plugins; `pluginOptions.<name>` configures them. `chroma dev` compiles `.mdx` on request, serves the files plugins generate at their URL, and regenerates them (before the hot reload) when watched files change.
- Change: the templates have no `package.json` and no Node tooling, and the `dynamic` and `standard` templates set `engine.rebuildWasm` to `false`. `wasm-pack` is only needed when `engine.rebuildWasm` is `true`.
- Removed: `chroma fs link` (it needed npm), `lib/chroma-add.mjs`, and every `npx esbuild` call (`Chroma/build.sh` minifies `pkg/chroma.js` with `engine minify`).

## 0.3.13

- Fix: `Show` now follows JavaScript truthiness for numbers. `NaN` (like `0` and `-0`) is falsy, so `when: () => NaN` renders the fallback.
