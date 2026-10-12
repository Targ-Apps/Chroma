//! `hookState`: Chroma's state hook.

use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;

use crate::signals;

/// Returns `[getter, setter]`.
///
/// The getter, called inside a reactive expression, registers the dependency;
/// the setter re-runs only the bindings that depend on the signal.
#[wasm_bindgen(js_name = hookState)]
pub fn hook_state(initial: JsValue) -> js_sys::Array {
    let id = signals::create_signal(initial);

    let getter =
        Closure::<dyn Fn() -> JsValue>::new(move || signals::read_signal(id)).into_js_value();
    let setter = Closure::<dyn Fn(JsValue)>::new(move |value: JsValue| {
        let next = if let Some(updater) = value.dyn_ref::<js_sys::Function>() {
            let current = signals::peek_signal(id);
            updater
                .call1(&JsValue::NULL, &current)
                .unwrap_or(current)
        } else {
            value
        };
        signals::write_signal(id, next);
    })
    .into_js_value();

    js_sys::Array::of2(&getter, &setter)
}

#[cfg(test)]
mod tests {
    use super::*;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    fn call0(f: &JsValue) -> JsValue {
        f.dyn_ref::<js_sys::Function>()
            .unwrap()
            .call0(&JsValue::NULL)
            .unwrap()
    }

    fn call1(f: &JsValue, arg: &JsValue) {
        f.dyn_ref::<js_sys::Function>()
            .unwrap()
            .call1(&JsValue::NULL, arg)
            .unwrap();
    }

    #[wasm_bindgen_test]
    fn getter_reads_the_initial_value() {
        let pair = hook_state(JsValue::from_f64(10.0));
        assert_eq!(call0(&pair.get(0)).as_f64(), Some(10.0));
    }

    #[wasm_bindgen_test]
    fn setter_writes_a_direct_value() {
        let pair = hook_state(JsValue::from_f64(1.0));
        let (getter, setter) = (pair.get(0), pair.get(1));

        call1(&setter, &JsValue::from_f64(5.0));
        assert_eq!(call0(&getter).as_f64(), Some(5.0));
    }

    #[wasm_bindgen_test]
    fn setter_accepts_an_updater_function_receiving_the_current_value() {
        let pair = hook_state(JsValue::from_f64(3.0));
        let (getter, setter) = (pair.get(0), pair.get(1));

        let updater: js_sys::Function =
            Closure::<dyn Fn(JsValue) -> JsValue>::new(|current: JsValue| {
                JsValue::from_f64(current.as_f64().unwrap() + 1.0)
            })
            .into_js_value()
            .unchecked_into();
        call1(&setter, &updater);

        assert_eq!(call0(&getter).as_f64(), Some(4.0));
    }
}
