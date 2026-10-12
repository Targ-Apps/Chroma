# Changelog

All notable changes to the Chroma engine and CLI are documented here.

## 0.3.13

- Fix: `Show` now follows JavaScript truthiness for numbers. `NaN` (like `0` and `-0`) is falsy, so `when: () => NaN` renders the fallback.
