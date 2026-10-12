//! `useDebugValue`: debug labels for custom hooks.

use wasm_bindgen::prelude::*;

/// Debug label for custom hooks. Without dedicated DevTools, it only writes
/// to the console if `globalThis.__CHROMA_DEBUG__` is truthy.
#[wasm_bindgen(js_name = useDebugValue)]
pub fn hook_debug_value(value: JsValue, formatter: Option<js_sys::Function>) {
    let enabled = js_sys::Reflect::get(&js_sys::global(), &"__CHROMA_DEBUG__".into())
        .map(|v| v.is_truthy())
        .unwrap_or(false);
    if !enabled {
        return;
    }
    let shown = formatter
        .and_then(|f| f.call1(&JsValue::NULL, &value).ok())
        .unwrap_or(value);
    web_sys::console::debug_2(&"useDebugValue:".into(), &shown);
}

#[cfg(test)]
mod tests {
    use super::*;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    fn set_debug_flag(enabled: bool) {
        js_sys::Reflect::set(
            &js_sys::global(),
            &"__CHROMA_DEBUG__".into(),
            &JsValue::from_bool(enabled),
        )
        .unwrap();
    }

    #[wasm_bindgen_test]
    fn is_silent_and_does_not_panic_when_the_debug_flag_is_unset() {
        set_debug_flag(false);
        hook_debug_value(JsValue::from_str("value"), None);
    }

    #[wasm_bindgen_test]
    fn runs_the_formatter_without_panicking_when_the_debug_flag_is_set() {
        set_debug_flag(true);
        let formatter: js_sys::Function =
            Closure::<dyn Fn(JsValue) -> JsValue>::new(|v: JsValue| {
                JsValue::from_str(&format!("formatted:{}", v.as_string().unwrap()))
            })
            .into_js_value()
            .unchecked_into();

        hook_debug_value(JsValue::from_str("x"), Some(formatter));

        set_debug_flag(false);
    }
}
