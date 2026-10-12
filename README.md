# Chroma

Chroma is a fine-grained reactive web framework whose engine runs on Rust and WebAssembly.

Each component runs once; reactive expressions stay bound to the exact DOM node they update. There is no virtual DOM and no diffing. Server-side rendering is in experimental internal development and is not available.

## Install

```bash
sh <(curl https://docs.targapps.xyz/sh)
```

```powershell
irm https://docs.targapps.xyz/ps | iex
```

Confirm with `chroma --version`. What each command needs (Node.js, `wasm-pack`) and other install options: [Getting started](https://docs.targapps.xyz/docs/chroma/getting-started#prerequisites).

## Usage

```bash
chroma new my-app
cd my-app
chroma validate
chroma dev        # serves the app; reload the page on source changes
chroma build      # production bundle (esbuild; needs Node.js, and wasm-pack for dynamic apps)
```

```js
// src/App.chr
import { hookState, e } from "../pkg/chroma.js";

export function App() {
  const [count, setCount] = hookState(0);
  return e("button", { onClick: () => setCount(count() + 1) }, "Count: ", count);
}
```

## Documentation

- [Getting started](https://docs.targapps.xyz/docs/chroma/getting-started)
- [Concepts](https://docs.targapps.xyz/docs/chroma/concepts/reactivity)
- [Reference](https://docs.targapps.xyz/docs/chroma/reference/api)
- [Examples](https://docs.targapps.xyz/docs/chroma/examples)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0-or-later. Copyright (C) 2026 Targ Apps. See [LICENSE](LICENSE).
