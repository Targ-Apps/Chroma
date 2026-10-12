//! `useEffect`: reactive side effects with cleanup.

use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;

use super::reactive_expr;
use crate::signals::{self, BindingTarget};

/// Reactive side effect. The first run is deferred to a microtask (after the
/// component mounts); subsequent runs are synchronous when a dependency
/// changes. If it returns a function, it is used as a cleanup before each
/// re-run.
#[wasm_bindgen(js_name = useEffect)]
pub fn hook_effect(effect: js_sys::Function, deps: JsValue) -> Result<(), JsValue> {
    let expr = reactive_expr(effect, &deps);
    let cb = Closure::once_into_js(move || {
        signals::create_binding(expr, BindingTarget::Effect);
    });
    web_sys::window()
        .ok_or_else(|| JsValue::from_str("chroma: no window available"))?
        .queue_microtask(cb.unchecked_ref());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signals::{create_signal, read_signal, write_signal};
    use js_sys::Promise;
    use std::cell::Cell;
    use std::rc::Rc;
    use wasm_bindgen_futures::JsFuture;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    async fn flush_microtasks() {
        JsFuture::from(Promise::resolve(&JsValue::NULL))
            .await
            .unwrap();
    }

    #[wasm_bindgen_test]
    async fn first_run_is_deferred_to_a_microtask_after_mounting() {
        let id = create_signal(JsValue::from_f64(0.0));
        let ran = Rc::new(Cell::new(false));
        let r = ran.clone();
        let effect: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            read_signal(id);
            r.set(true);
            JsValue::UNDEFINED
        })
        .into_js_value()
        .unchecked_into();

        hook_effect(effect, JsValue::UNDEFINED).unwrap();
        assert!(!ran.get(), "useEffect must not run synchronously");

        flush_microtasks().await;
        assert!(ran.get());
    }

    #[wasm_bindgen_test]
    async fn reruns_synchronously_on_change_and_calls_cleanup_first() {
        let id = create_signal(JsValue::from_f64(0.0));
        let runs = Rc::new(Cell::new(0));
        let cleanups = Rc::new(Cell::new(0));
        let (r, c) = (runs.clone(), cleanups.clone());

        let effect: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            read_signal(id);
            r.set(r.get() + 1);
            let c = c.clone();
            Closure::once_into_js(move || {
                c.set(c.get() + 1);
            })
        })
        .into_js_value()
        .unchecked_into();

        hook_effect(effect, JsValue::UNDEFINED).unwrap();
        assert_eq!(runs.get(), 0);

        flush_microtasks().await;
        assert_eq!(runs.get(), 1);
        assert_eq!(cleanups.get(), 0);

        write_signal(id, JsValue::from_f64(1.0));
        assert_eq!(runs.get(), 2); // synchronous re-run
        assert_eq!(cleanups.get(), 1); // cleanup from the previous run
    }
}
