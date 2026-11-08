# @chroma/t2t

Test-to-test utilities for Chroma apps: a Node test bridge, snapshot smoke checks and persist round-trip validation for apps that use `@chroma/fs`.

Chroma is a fine-grained reactive web framework whose engine runs on Rust and WebAssembly.

## Install

Copy the plugin into your app's `plugins/` folder and list it in `chroma.json`. See [Plugins](https://docs.targapps.xyz/docs/chroma/guides/plugins).

## Usage

```js
// src/test-setup.chr
import { bootstrapT2t } from "@chroma/t2t";

await bootstrapT2t({
  persist: { adapters, seed, verify },
  snapshot: { getSnapshot, collectionKeys: ["items"] },
});
// then in the console: globalThis.__chromaT2t.runAll()
```

Run the Node bridge tests with `node node/run-tests.mjs`.

## Documentation

[Plugins](https://docs.targapps.xyz/docs/chroma/guides/plugins) · [Testing](https://docs.targapps.xyz/docs/chroma/contributing/testing)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0-or-later. Copyright (C) 2026 Targ Apps. See [LICENSE](LICENSE).
