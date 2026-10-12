//! `useRef`: mutable references without reactivity.

use wasm_bindgen::prelude::*;

/// Non-reactive mutable reference: `{ current: initial }`. Pass it as the
/// `ref` prop of an element to receive the DOM node in `current`.
#[wasm_bindgen(js_name = useRef)]
pub fn hook_ref(initial: JsValue) -> Result<JsValue, JsValue> {
    let obj = js_sys::Object::new();
    js_sys::Reflect::set(&obj, &"current".into(), &initial)?;
    Ok(obj.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    #[wasm_bindgen_test]
    fn ref_object_exposes_current_with_the_initial_value() {
        let obj = hook_ref(JsValue::from_f64(1.0)).unwrap();
        let current = js_sys::Reflect::get(&obj, &"current".into()).unwrap();
        assert_eq!(current.as_f64(), Some(1.0));
    }

    #[wasm_bindgen_test]
    fn ref_object_current_can_be_mutated_after_creation() {
        let obj = hook_ref(JsValue::NULL).unwrap();
        js_sys::Reflect::set(&obj, &"current".into(), &JsValue::from_f64(9.0)).unwrap();
        let current = js_sys::Reflect::get(&obj, &"current".into()).unwrap();
        assert_eq!(current.as_f64(), Some(9.0));
    }
}
