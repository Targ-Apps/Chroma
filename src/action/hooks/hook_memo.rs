//! `useMemo`: cached derived values.

use wasm_bindgen::prelude::*;

use super::reactive_expr;
use crate::signals::{self, BindingTarget};

/// Cached derived value. Returns a reactive getter: the computation re-runs
/// only when its dependencies change, not on every read.
#[wasm_bindgen(js_name = useMemo)]
pub fn hook_memo(calc: js_sys::Function, deps: JsValue) -> JsValue {
    let signal = signals::create_signal(JsValue::UNDEFINED);
    signals::create_binding(reactive_expr(calc, &deps), BindingTarget::Memo(signal));
    Closure::<dyn Fn() -> JsValue>::new(move || signals::read_signal(signal)).into_js_value()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signals::{create_signal, read_signal, write_signal};
    use wasm_bindgen::JsCast;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    #[wasm_bindgen_test]
    fn memo_recomputes_only_when_a_declared_dependency_changes() {
        let source = create_signal(JsValue::from_f64(2.0));
        let getter_src: js_sys::Function =
            Closure::<dyn Fn() -> JsValue>::new(move || read_signal(source))
                .into_js_value()
                .unchecked_into();

        let calc: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            JsValue::from_f64(read_signal(source).as_f64().unwrap() * 2.0)
        })
        .into_js_value()
        .unchecked_into();

        let deps = js_sys::Array::of1(&getter_src);
        let doubled = hook_memo(calc, deps.into());
        let doubled_fn = doubled.dyn_ref::<js_sys::Function>().unwrap();

        assert_eq!(
            doubled_fn.call0(&JsValue::NULL).unwrap().as_f64(),
            Some(4.0)
        );

        write_signal(source, JsValue::from_f64(10.0));
        assert_eq!(
            doubled_fn.call0(&JsValue::NULL).unwrap().as_f64(),
            Some(20.0)
        );
    }

    #[wasm_bindgen_test]
    fn memo_without_deps_auto_tracks_reads_inside_the_calculation() {
        let source = create_signal(JsValue::from_f64(1.0));
        let calc: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            JsValue::from_f64(read_signal(source).as_f64().unwrap() + 100.0)
        })
        .into_js_value()
        .unchecked_into();

        let result = hook_memo(calc, JsValue::UNDEFINED);
        let result_fn = result.dyn_ref::<js_sys::Function>().unwrap();

        assert_eq!(
            result_fn.call0(&JsValue::NULL).unwrap().as_f64(),
            Some(101.0)
        );
        write_signal(source, JsValue::from_f64(5.0));
        assert_eq!(
            result_fn.call0(&JsValue::NULL).unwrap().as_f64(),
            Some(105.0)
        );
    }
}
