//! Chroma hooks, adapted to fine-grained reactivity (no re-renders).
//!
//! Key difference from React/Preact: the dependency array does not carry
//! values but signal **getters** (`[count]`, not `[count()]`) — without
//! re-renders there is no "compare against the previous render"; the
//! dependency is the subscription to the signal. Without an array, reads are
//! tracked automatically (SolidJS style); with `[]`, it runs only once.
//!
//! One file per hook.

pub mod hook_state;
pub mod hook_callback;
pub mod hook_context;
pub mod hook_debug_value;
pub mod hook_effect;
pub mod hook_layout_effect;
pub mod hook_memo;
pub mod hook_reducer;
pub mod hook_ref;

use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;

use crate::signals;

/// Builds a binding's expression from (fn, deps).
///
/// Without deps: `f` itself (auto-tracking). With deps: a wrapper that reads
/// the getters (subscribing) and runs `f` without tracking, like React where
/// the effect body does not define the dependencies.
pub(crate) fn reactive_expr(f: js_sys::Function, deps: &JsValue) -> js_sys::Function {
    if deps.is_undefined() || deps.is_null() {
        return f;
    }

    let getters: js_sys::Array = if js_sys::Array::is_array(deps) {
        deps.clone().unchecked_into()
    } else {
        crate::trace::log_error("chroma: a hook's second argument must be an array of getters");
        js_sys::Array::new()
    };

    Closure::<dyn Fn() -> JsValue>::new(move || {
        for dep in getters.iter() {
            if let Some(getter) = dep.dyn_ref::<js_sys::Function>() {
                let _ = getter.call0(&JsValue::NULL);
            } else {
                crate::trace::log_error(
                    "chroma: dependencies must be getters (functions) — pass `count`, not `count()`",
                );
            }
        }
        signals::untracked(|| f.call0(&JsValue::NULL)).unwrap_or_else(|err| {
            crate::trace::log_error_with("chroma: error in an effect/memo:", &err);
            JsValue::UNDEFINED
        })
    })
    .into_js_value()
    .unchecked_into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signals::{create_binding, create_signal, read_signal, write_signal, BindingTarget};
    use std::cell::Cell;
    use std::rc::Rc;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    #[wasm_bindgen_test]
    fn reactive_expr_without_deps_returns_the_function_unchanged() {
        let f: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(|| JsValue::from_f64(1.0))
            .into_js_value()
            .unchecked_into();
        let expr = reactive_expr(f.clone(), &JsValue::UNDEFINED);
        assert_eq!(expr, f);
    }

    #[wasm_bindgen_test]
    fn reactive_expr_with_deps_subscribes_only_the_declared_getters() {
        let tracked = create_signal(JsValue::from_f64(1.0));
        let untracked_signal = create_signal(JsValue::from_f64(2.0));

        let getter: js_sys::Function =
            Closure::<dyn Fn() -> JsValue>::new(move || read_signal(tracked))
                .into_js_value()
                .unchecked_into();

        let body_runs = Rc::new(Cell::new(0));
        let b = body_runs.clone();
        let body: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            // With an explicit deps array, reads in the body run untracked:
            // this read must not create a subscription.
            read_signal(untracked_signal);
            b.set(b.get() + 1);
            JsValue::UNDEFINED
        })
        .into_js_value()
        .unchecked_into();

        let deps = js_sys::Array::of1(&getter);
        let expr = reactive_expr(body, &deps.into());
        create_binding(expr, BindingTarget::Effect);
        assert_eq!(body_runs.get(), 1);

        write_signal(untracked_signal, JsValue::from_f64(99.0));
        assert_eq!(body_runs.get(), 1, "the body's own reads must not subscribe");

        write_signal(tracked, JsValue::from_f64(5.0));
        assert_eq!(body_runs.get(), 2, "the deps getter must subscribe");
    }
}
