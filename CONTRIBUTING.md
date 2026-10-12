# Contributing to Chroma

## Build the engine from source

Requires Rust, the `wasm32-unknown-unknown` target, `wasm-pack` and Node.js (for the esbuild minify step).

```bash
./build.sh      # wasm-pack build --target web --release, then minifies pkg/chroma.js
./dev.sh        # watch mode: rebuilds pkg/ on changes
cargo test
```

`chroma install` (from a checkout, `./cli/chroma.sh install`) provisions the same toolchain and installs the `chroma` command.

## Versioning

The canonical version is the single line in `VERSION`; `Cargo.toml` `[package].version` must match it. Bump it in the same change as any engine or CLI modification (patch: fix, minor: feature, major: breaking). Full policy: [Versioning](https://docs.targapps.xyz/docs/chroma/contributing/versioning).

## Tests

See [Testing](https://docs.targapps.xyz/docs/chroma/contributing/testing).
