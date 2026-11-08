# @chroma/router

API router plugin for Chroma: HTTP-like route handlers (GET, POST, PUT, DELETE, CUSTOM) that run in the browser and answer local `fetch` calls, so you can simulate endpoints without a backend.

Chroma is a fine-grained reactive web framework whose engine runs on Rust and WebAssembly. Not to be confused with the screen router (`createRouter` in the WASM engine), which maps URLs to screens.

## Install

Copy the plugin into your app's `plugins/` folder and list it in `chroma.json`. See [Plugins](https://docs.targapps.xyz/docs/chroma/guides/plugins).

## Usage

```js
// src/api.chr
import { createRouter } from "@chroma/router";

const router = createRouter();
router.registerRoute("/api/users/:id", {
  GET: (req) => ({ status: 200, body: { id: req.params.id } }),
});
router.hijackFetch();

const res = await fetch("/api/users/7");
```

Handlers receive `{ method, url, path, params, query, body, customOperation }`. `CUSTOM` handlers also get the operation name as second argument. Unmatched paths return 404; unsupported methods return 405.

## Documentation

[Routing](https://docs.targapps.xyz/docs/chroma/guides/routing) · [Plugins](https://docs.targapps.xyz/docs/chroma/guides/plugins)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0-or-later. Copyright (C) 2026 Targ Apps. See [LICENSE](LICENSE).
