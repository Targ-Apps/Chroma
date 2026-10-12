//! Component call-stack tracing for diagnostics.
//!
//! Fine-grained reactivity means a browser stack trace for a wasm trap or a
//! raw JS error almost never says which *component* was rendering or which
//! binding was re-evaluating when something went wrong: it's wasm-function
//! indices and minified closure names all the way down. This module keeps a
//! thread-local stack of component names, pushed for the duration of each
//! `e(Component, ...)` / `render(Component, ...)` call, so every diagnostic
//! the runtime emits — a caught JS error, a logged warning, or an actual
//! Rust panic — can say *where* it happened, not just *what*.

use std::cell::RefCell;

thread_local! {
    static STACK: RefCell<Vec<String>> = const { RefCell::new(Vec::new()) };
}

/// RAII guard: pops its frame when dropped.
///
/// Popping on `Drop` (rather than requiring a matching explicit "pop" call)
/// keeps the stack correct across early returns via `?`, since invoking a
/// component is fallible (`e`/`render` both return `Result`).
#[must_use]
pub struct Frame;

impl Drop for Frame {
    fn drop(&mut self) {
        STACK.with(|s| {
            s.borrow_mut().pop();
        });
    }
}

/// Pushes `name` onto the component stack. Keep the returned guard alive for
/// as long as `name` is "currently rendering".
pub fn push(name: impl Into<String>) -> Frame {
    STACK.with(|s| s.borrow_mut().push(name.into()));
    Frame
}

/// Current component path, outermost first, e.g. `"AppShell > Layout > Onboarding"`.
pub fn path() -> String {
    STACK.with(|s| s.borrow().join(" > "))
}

/// Best-effort name for a JS function: its `.name`, or `"<anonymous>"`.
///
/// Both `function` declarations and arrow functions expose `.name` (inferred
/// from the binding they were assigned to) in every engine chroma targets,
/// so this is what shows up as the component name in traces.
pub fn function_name(f: &js_sys::Function) -> String {
    js_sys::Reflect::get(f, &"name".into())
        .ok()
        .and_then(|v| v.as_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "<anonymous>".into())
}

/// Prefixes a diagnostic with the current component path, when there is one.
pub fn annotate(message: &str) -> String {
    let path = path();
    if path.is_empty() {
        message.to_string()
    } else {
        format!("{message} (in {path})")
    }
}

/// Logs `message` via `console.error`, annotated with the current component path.
pub fn log_error(message: &str) {
    web_sys::console::error_1(&annotate(message).into());
}

/// Logs `message` (annotated) alongside the JS error value that caused it,
/// matching the runtime's existing two-argument diagnostics — the second
/// argument keeps the original `Error` object (and its own JS stack) intact
/// in the console instead of flattening it into text.
pub fn log_error_with(message: &str, err: &wasm_bindgen::JsValue) {
    web_sys::console::error_2(&annotate(message).into(), err);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_is_empty_with_no_frames() {
        assert_eq!(path(), "");
    }

    #[test]
    fn push_appends_and_drop_pops() {
        assert_eq!(path(), "");
        {
            let _outer = push("Outer");
            assert_eq!(path(), "Outer");
            {
                let _inner = push("Inner");
                assert_eq!(path(), "Outer > Inner");
            }
            assert_eq!(path(), "Outer");
        }
        assert_eq!(path(), "");
    }

    #[test]
    fn annotate_appends_the_path_only_when_non_empty() {
        assert_eq!(annotate("boom"), "boom");
        let _frame = push("Widget");
        assert_eq!(annotate("boom"), "boom (in Widget)");
    }
}
