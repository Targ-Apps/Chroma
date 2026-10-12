//! `useCallback`: function memoization.

use wasm_bindgen::prelude::*;

/// Identity: without re-renders components run only once, so functions are
/// never recreated. Exists for API compatibility.
#[wasm_bindgen(js_name = useCallback)]
pub fn hook_callback(callback: JsValue, _deps: JsValue) -> JsValue {
    callback
}

#[cfg(test)]
mod tests {
    use super::*;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    #[wasm_bindgen_test]
    fn callback_returns_the_exact_same_function_reference() {
        let f: JsValue = Closure::<dyn Fn()>::new(|| {}).into_js_value();
        let out = hook_callback(f.clone(), JsValue::UNDEFINED);
        assert_eq!(out, f);
    }
}
