# @chroma/style

Design tokens, `tw()` class merging, `prose` typography and `cva` presets for Chroma apps. Its **utility CSS generator** is the native `chroma-style` build plugin of the Chroma CLI.

Chroma is a fine-grained reactive web framework whose engine runs on Rust and WebAssembly. Its styling layer needs no npm packages and no Node: the CSS generator ships with the Chroma CLI as the native build plugin `chroma-style`; this package holds the design tokens, the static CSS layers and the small browser runtime (`tw()`, `cva` presets).

## Install

Copy the plugin into your app's `plugins/` folder and list it in `chroma.json`. See [Plugins](https://docs.targapps.xyz/docs/chroma/guides/plugins).

## Usage

```js
// src/main.chr
import { cva, cx } from "../pkg/chroma.js";
import { bootstrapStyle } from "../plugins/chroma-style/index.js";

const { tw, presets } = bootstrapStyle({ cva, cx, styles: false });
document.body.className = tw("bg-background text-foreground", "p-4 px-2"); // -> "bg-background text-foreground p-4 px-2"
```

Generate the CSS (only the utilities your code uses): list the build plugin in `chroma.json` and give it options; `chroma dev` regenerates the stylesheet on every change and `chroma build` writes it minified.

```json
{
  "plugins": ["chroma-style"],
  "pluginOptions": {
    "chroma-style": { "src": ["src", "index.html"], "output": "assets/css/app.css", "include": ["src/styles/site.css"] }
  }
}
```

```html
<link rel="stylesheet" href="/assets/css/app.css">
```

The output is layered — `@layer tokens, base, components, utilities` — followed by your own CSS (`include`). Options: `src`, `include`, `output`, `colors`, `breakpoints`, `variants`, `safelist`, `minify`, `tokens`, `base`. Inspect what a class produces with `cargo run -p chroma-plugins --example style_explain -- explain "md:hover:bg-primary/80"` (in Chroma-Compiler).

Without a build step, `bootstrapStyle({ cva, cx })` links the starter sheets (`tokens.css`, `base.css`, `utilities.css`).

## What is inside

| File | Role |
| --- | --- |
| `tokens.css` | shadcn-compatible tokens (colors, radius, fonts, text scale, shadows), light + dark |
| `base.css` | reset + base styles (layer `base`) |
| `tw.js` | `twMerge()` / `tw()`: merges classes and resolves conflicts (last wins) |
| `lib/` | the class grammar in JavaScript (what each utility sets); `tw.js` uses it in the browser. The build-time CSS generator is the native `chroma-style` plugin |
| `prose.css` | typography for long-form content (`prose`, `prose-sm|lg|xl|2xl`, `prose-invert`) |
| `animate.css` | `@keyframes` (spin, marquee, accordion, enter/exit…), included only when referenced |
| `components.css` | `cs-*` shells and helpers, included only when used |
| `variants.js` | `button`, `badge`, `card`, `input` presets on top of the engine's `cva` |
| `utilities.css` | generated starter subset for apps without a build step (regenerated from `starter.txt` with the `style_explain starter` example) |

## Documentation

[Utilities](https://docs.targapps.xyz/docs/chroma-style/utilities) · [Tokens](https://docs.targapps.xyz/docs/chroma-style/tokens) · [Styling](https://docs.targapps.xyz/docs/chroma/guides/styling) · [Plugins](https://docs.targapps.xyz/docs/chroma/guides/plugins)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0-or-later. Copyright (C) 2026 Targ Apps. See [LICENSE](LICENSE).
