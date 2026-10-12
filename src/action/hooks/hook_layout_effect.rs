//! `useLayoutEffect`: synchronous effect, runs before paint.

use wasm_bindgen::prelude::*;

use super::reactive_expr;
use crate::signals;

/// Like `useEffect`, but the first run is synchronous: it fires as soon as
/// `render` finishes mounting the tree, before paint — the DOM (and the
/// `ref`s) are already available. Re-runs are also synchronous.
#[wasm_bindgen(js_name = useLayoutEffect)]
pub fn hook_layout_effect(effect: js_sys::Function, deps: JsValue) {
    signals::queue_layout_effect(reactive_expr(effect, &deps));
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    use std::rc::Rc;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    #[wasm_bindgen_test]
    fn layout_effect_only_runs_once_layout_effects_are_flushed() {
        let ran = Rc::new(Cell::new(false));
        let r = ran.clone();
        let effect: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            r.set(true);
            JsValue::UNDEFINED
        })
        .into_js_value()
        .unchecked_into();

        hook_layout_effect(effect, JsValue::UNDEFINED);
        assert!(!ran.get(), "queuing must not run the effect immediately");

        signals::flush_layout_effects();
        assert!(ran.get());
    }
}
