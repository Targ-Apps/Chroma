# @chroma/style

Design tokens, utility CSS classes and `cva` presets for Chroma apps.

Chroma is a fine-grained reactive web framework whose engine runs on Rust and WebAssembly.

## Install

Copy the plugin into your app's `plugins/` folder and list it in `chroma.json`. See [Plugins](https://docs.targapps.xyz/docs/chroma/guides/plugins).

## Usage

```js
// src/main.chr
import { cva, cx } from "../pkg/chroma.js";
import { bootstrapStyle } from "@chroma/style";

const { tw, presets } = bootstrapStyle({ cva, cx }); // injects tokens.css and utilities.css
document.body.className = tw("bg-background", "text-foreground");
```

`bootstrapStyle` returns `{ tw, presets, utilityClasses, injectStyles, createVariants }`; `presets` is `null` unless you pass `cva`.

## Documentation

[Styling](https://docs.targapps.xyz/docs/chroma/guides/styling) · [Plugins](https://docs.targapps.xyz/docs/chroma/guides/plugins)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0-or-later. Copyright (C) 2026 Targ Apps. See [LICENSE](LICENSE).
