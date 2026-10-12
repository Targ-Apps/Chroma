//! `createContext` / `useContext`: shared values without prop-drilling.

use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;

use crate::dom;
use crate::signals;

const CONTEXT_ID_KEY: &str = "__chromaContextId";

/// Creates a context: `{ Provider, defaultValue }`.
///
/// Without a VDOM the children are evaluated before the parent component, so
/// the Provider receives the children as a **function** in order to evaluate
/// them with the context active: `e(Ctx.Provider, { value }, () => e(Child))`.
#[wasm_bindgen(js_name = createContext)]
pub fn hook_create_context(default_value: JsValue) -> Result<JsValue, JsValue> {
    let id = signals::create_context_slot();

    let ctx = js_sys::Object::new();
    js_sys::Reflect::set(&ctx, &CONTEXT_ID_KEY.into(), &JsValue::from_f64(id as f64))?;
    js_sys::Reflect::set(&ctx, &"defaultValue".into(), &default_value)?;

    let fallback = default_value.clone();
    let provider = Closure::<dyn Fn(JsValue) -> JsValue>::new(move |props: JsValue| {
        let value = js_sys::Reflect::get(&props, &"value".into()).unwrap_or(JsValue::UNDEFINED);
        let value = if value.is_undefined() {
            fallback.clone()
        } else {
            value
        };

        signals::push_context(id, value);
        let children =
            js_sys::Reflect::get(&props, &"children".into()).unwrap_or(JsValue::UNDEFINED);
        // Function children: evaluated here, with the provider on the stack.
        let evaluated = if let Some(f) = children.dyn_ref::<js_sys::Function>() {
            f.call0(&JsValue::NULL).unwrap_or_else(|err| {
                crate::trace::log_error_with("chroma: error in Provider children:", &err);
                JsValue::UNDEFINED
            })
        } else {
            children
        };
        signals::pop_context(id);

        let list = if evaluated.is_null() || evaluated.is_undefined() {
            js_sys::Array::new()
        } else if js_sys::Array::is_array(&evaluated) {
            evaluated.unchecked_into()
        } else {
            js_sys::Array::of1(&evaluated)
        };
        match dom::create_fragment(&list) {
            Ok(fragment) => fragment.into(),
            Err(err) => {
                crate::trace::log_error_with("chroma: error mounting the Provider:", &err);
                JsValue::UNDEFINED
            }
        }
    })
    .into_js_value();
    js_sys::Reflect::set(&ctx, &"Provider".into(), &provider)?;

    Ok(ctx.into())
}

/// Value of the nearest active `Provider`, or `defaultValue` if there is none.
#[wasm_bindgen(js_name = useContext)]
pub fn hook_context(ctx: &JsValue) -> Result<JsValue, JsValue> {
    let id = js_sys::Reflect::get(ctx, &CONTEXT_ID_KEY.into())?
        .as_f64()
        .ok_or_else(|| {
            JsValue::from_str("chroma: useContext expects a context created with createContext")
        })? as usize;

    Ok(signals::read_context(id)
        .unwrap_or_else(|| js_sys::Reflect::get(ctx, &"defaultValue".into()).unwrap_or_default()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::rc::Rc;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    #[wasm_bindgen_test]
    fn use_context_returns_the_default_value_without_an_active_provider() {
        let ctx = hook_create_context(JsValue::from_str("light")).unwrap();
        let value = hook_context(&ctx).unwrap();
        assert_eq!(value.as_string(), Some("light".into()));
    }

    #[wasm_bindgen_test]
    fn use_context_expects_a_context_created_with_create_context() {
        // An object without the internal context-id marker: `Reflect::get`
        // succeeds (unlike on a non-object value) but returns `undefined`.
        let not_a_context = js_sys::Object::new();
        let err = hook_context(&not_a_context.into()).unwrap_err();
        assert!(err.as_string().unwrap().contains("createContext"));
    }

    #[wasm_bindgen_test]
    fn provider_makes_its_value_visible_to_children_evaluated_inside_it_and_pops_after() {
        let ctx = hook_create_context(JsValue::from_str("light")).unwrap();
        let provider = js_sys::Reflect::get(&ctx, &"Provider".into()).unwrap();
        let provider_fn = provider.dyn_ref::<js_sys::Function>().unwrap();

        let ctx_clone = ctx.clone();
        let seen: Rc<RefCell<Option<String>>> = Rc::new(RefCell::new(None));
        let s = seen.clone();
        let children: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            *s.borrow_mut() = hook_context(&ctx_clone).unwrap().as_string();
            JsValue::UNDEFINED
        })
        .into_js_value()
        .unchecked_into();

        let props = js_sys::Object::new();
        js_sys::Reflect::set(&props, &"value".into(), &"dark".into()).unwrap();
        js_sys::Reflect::set(&props, &"children".into(), &children).unwrap();
        provider_fn.call1(&JsValue::NULL, &props).unwrap();

        assert_eq!(seen.borrow().as_deref(), Some("dark"));

        // Outside the provider (after it returns), the stack is popped again.
        assert_eq!(
            hook_context(&ctx).unwrap().as_string(),
            Some("light".into())
        );
    }

    #[wasm_bindgen_test]
    fn provider_falls_back_to_the_default_value_when_value_prop_is_undefined() {
        let ctx = hook_create_context(JsValue::from_str("fallback")).unwrap();
        let provider = js_sys::Reflect::get(&ctx, &"Provider".into()).unwrap();
        let provider_fn = provider.dyn_ref::<js_sys::Function>().unwrap();

        let ctx_clone = ctx.clone();
        let seen: Rc<RefCell<Option<String>>> = Rc::new(RefCell::new(None));
        let s = seen.clone();
        let children: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            *s.borrow_mut() = hook_context(&ctx_clone).unwrap().as_string();
            JsValue::UNDEFINED
        })
        .into_js_value()
        .unchecked_into();

        let props = js_sys::Object::new(); // no "value" set
        js_sys::Reflect::set(&props, &"children".into(), &children).unwrap();
        provider_fn.call1(&JsValue::NULL, &props).unwrap();

        assert_eq!(seen.borrow().as_deref(), Some("fallback"));
    }
}
