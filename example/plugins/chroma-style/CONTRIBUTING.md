# Contributing to Chroma-Style

Plain ESM and CSS for the browser runtime (`index.js`, `tw.js`, `variants.js`, `lib/`; no dependencies, no build step). The CSS generator at build time is NOT a script of this package any more: it is the native `chroma-style` build plugin of the Chroma CLI (`Chroma-Compiler/crates/chroma-plugins/src/style/`, Rust). `lib/*.mjs` is the JavaScript twin of that grammar: `tw()` runs it in the browser to know which CSS properties a class sets. A utility change must be made in BOTH (`lib/rules.mjs` and `rules.rs`); the Rust tests compare the plugin with the output of this grammar.

- **Utilities** (`rules.mjs` / `rules.rs`, in the order they are emitted: shorthands before longhands), scales (`theme`), value parsing (`value`) and variants (`variants`). In JS add one with `add(roots, fn)`; in Rust `r.add1(root, |rest, ctx| …)`; the function returns the declarations or nothing.
- **Apps can extend** the grammar without touching the plugin: `pluginOptions.chroma-style` in `chroma.json` (`colors`, `breakpoints`, `safelist`, `variants`).
- **Tokens** (`tokens.css`) and the scales in `theme` must agree: every `var(--…)` the generator emits has to be defined in `tokens.css` (palette variables `--color-*` are emitted on demand).
- **Static CSS** (`tokens.css`, `base.css`, `prose.css`, `components.css`, `animate.css`) is plain CSS; `/* @when <regex> */` markers make a section conditional on a class being used, and only the `@keyframes` an `animation` references are included. The plugin embeds copies of these files: after changing them run `scripts/sync-chroma-plugins.sh` (it copies them to `Chroma-Compiler/crates/chroma-plugins/assets/style/`) and rebuild the CLI.
- `utilities.css` is generated: after changing utilities, tokens or `variants.js` run `cargo run -p chroma-plugins --example style_explain -- starter <this folder>` in Chroma-Compiler.
- Run `node test/selftest.mjs` (JS grammar and runtime class merge) and `cargo test -p chroma-plugins` (native generator) before sending a change.
- Bump `version` in `package.json`, `chroma.plugin.json` and `index.js` (`VERSION`) together. See [Versioning](https://docs.targapps.xyz/docs/chroma/contributing/versioning).
- Utility names and the default palette follow the conventions of utility-first CSS (shadcn/ui token names, oklch palette); the generator is an independent implementation.
