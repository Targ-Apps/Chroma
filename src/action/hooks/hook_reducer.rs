//! `useReducer`: complex state managed through actions.

use wasm_bindgen::prelude::*;

use crate::signals;

/// Reducer-driven state: `[getter, dispatch]`. `dispatch(action)` computes the
/// next state with `reducer(current, action)` and notifies subscribers.
#[wasm_bindgen(js_name = useReducer)]
pub fn hook_reducer(reducer: js_sys::Function, initial: JsValue) -> js_sys::Array {
    let id = signals::create_signal(initial);

    let getter =
        Closure::<dyn Fn() -> JsValue>::new(move || signals::read_signal(id)).into_js_value();

    let dispatch = Closure::<dyn Fn(JsValue)>::new(move |action: JsValue| {
        let current = signals::peek_signal(id);
        match reducer.call2(&JsValue::NULL, &current, &action) {
            Ok(next) => signals::write_signal(id, next),
            Err(err) => {
                crate::trace::log_error_with("chroma: error in reducer:", &err);
            }
        }
    })
    .into_js_value();

    js_sys::Array::of2(&getter, &dispatch)
}

#[cfg(test)]
mod tests {
    use super::*;
    use wasm_bindgen::JsCast;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    #[wasm_bindgen_test]
    fn dispatch_computes_and_stores_the_next_state() {
        let reducer: js_sys::Function =
            Closure::<dyn Fn(JsValue, JsValue) -> JsValue>::new(|state: JsValue, action: JsValue| {
                let s = state.as_f64().unwrap();
                match action.as_string().as_deref() {
                    Some("inc") => JsValue::from_f64(s + 1.0),
                    _ => state,
                }
            })
            .into_js_value()
            .unchecked_into();

        let pair = hook_reducer(reducer, JsValue::from_f64(0.0));
        let getter = pair.get(0);
        let getter_fn = getter.dyn_ref::<js_sys::Function>().unwrap();
        let dispatch_fn = pair.get(1);
        let dispatch_fn = dispatch_fn.dyn_ref::<js_sys::Function>().unwrap();

        assert_eq!(getter_fn.call0(&JsValue::NULL).unwrap().as_f64(), Some(0.0));

        dispatch_fn
            .call1(&JsValue::NULL, &JsValue::from_str("inc"))
            .unwrap();
        assert_eq!(getter_fn.call0(&JsValue::NULL).unwrap().as_f64(), Some(1.0));
    }

    #[wasm_bindgen_test]
    fn reducer_errors_are_caught_and_leave_the_state_untouched() {
        let reducer: js_sys::Function = Closure::<
            dyn Fn(JsValue, JsValue) -> Result<JsValue, JsValue>,
        >::new(|_state, _action| Err(JsValue::from_str("boom")))
        .into_js_value()
        .unchecked_into();

        let pair = hook_reducer(reducer, JsValue::from_f64(5.0));
        let getter = pair.get(0);
        let dispatch = pair.get(1);

        dispatch
            .dyn_ref::<js_sys::Function>()
            .unwrap()
            .call1(&JsValue::NULL, &JsValue::NULL)
            .ok(); // the underlying reducer throws; hook_reducer must swallow it

        assert_eq!(
            getter
                .dyn_ref::<js_sys::Function>()
                .unwrap()
                .call0(&JsValue::NULL)
                .unwrap()
                .as_f64(),
            Some(5.0)
        );
    }
}
