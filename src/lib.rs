//! Chroma: a VDOM-free web framework with its entire engine in Rust/WASM.
//!
//! Each component runs exactly once; reactive expressions stay bound to the
//! exact DOM node they update (fine-grained reactivity).

mod action;
mod components;
mod dom;
mod graph;
mod router;
mod signals;
mod trace;
mod variants;

use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;

#[wasm_bindgen(start)]
fn start() {
    // Always installed (not just in debug builds): a panic reaching this
    // hook is already the worst-case diagnostic — a raw wasm trap with no
    // component context otherwise — so production builds need it too. It
    // logs which component was on the trace stack, then delegates to
    // `console_error_panic_hook` for the underlying panic message and JS
    // stack, keeping the detail that hook already provides.
    std::panic::set_hook(Box::new(|info| {
        trace::log_error("chroma: panic");
        console_error_panic_hook::hook(info);
    }));
}

/// Creates a node: `e(tag, props, ...children)`.
///
/// If `tag` is a string, it creates the HTML element with its props (`on*`
/// events, static or reactive attributes) and children. If it is a function
/// (component), it invokes it exactly once with its props, with the children
/// included in `props.children`.
#[wasm_bindgen(variadic)]
pub fn e(tag: JsValue, props: JsValue, children: js_sys::Array) -> Result<JsValue, JsValue> {
    if let Some(component) = tag.dyn_ref::<js_sys::Function>() {
        let merged = js_sys::Object::new();
        if props.is_object() {
            js_sys::Object::assign(&merged, props.unchecked_ref());
        }
        if children.length() > 0 {
            let value: JsValue = if children.length() == 1 {
                children.get(0)
            } else {
                children.clone().into()
            };
            js_sys::Reflect::set(&merged, &"children".into(), &value)?;
        }
        let _frame = trace::push(trace::function_name(component));
        return component.call1(&JsValue::NULL, &merged);
    }

    let Some(tag) = tag.as_string() else {
        return Err(JsValue::from_str(
            "chroma: e() expects a string tag or a component function",
        ));
    };
    dom::create_element(&tag, &props, &children).map(JsValue::from)
}

/// Groups children without a wrapper element: `e(Fragment, null, ...children)`.
#[wasm_bindgen(js_name = Fragment)]
pub fn fragment(props: JsValue) -> Result<web_sys::DocumentFragment, JsValue> {
    let children = js_sys::Reflect::get(&props, &"children".into()).unwrap_or(JsValue::UNDEFINED);
    let list = if children.is_null() || children.is_undefined() {
        js_sys::Array::new()
    } else if js_sys::Array::is_array(&children) {
        children.unchecked_into()
    } else {
        js_sys::Array::of1(&children)
    };
    dom::create_fragment(&list)
}

/// Runs the component once and mounts the resulting tree into `container`.
#[wasm_bindgen]
pub fn render(component: &js_sys::Function, container: &JsValue) -> Result<(), JsValue> {
    let Some(container) = container.dyn_ref::<web_sys::Element>() else {
        return Err(JsValue::from_str(
            "chroma: render() requires an Element as the container (did the selector return null?)",
        ));
    };

    let _frame = trace::push(trace::function_name(component));
    let root = component.call1(&JsValue::NULL, &js_sys::Object::new())?;
    let Some(node) = root.dyn_ref::<web_sys::Node>() else {
        return Err(JsValue::from_str(
            "chroma: the root component did not return a DOM node",
        ));
    };

    container.append_child(node)?;

    // DOM mounted: now the layout effects run (before paint).
    signals::flush_layout_effects();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    use std::rc::Rc;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    #[wasm_bindgen_test]
    fn e_with_a_string_tag_creates_the_html_element() {
        let el = e(JsValue::from_str("div"), JsValue::NULL, js_sys::Array::new()).unwrap();
        let el: web_sys::Element = el.unchecked_into();
        assert_eq!(el.tag_name(), "DIV");
    }

    #[wasm_bindgen_test]
    fn e_with_neither_a_string_nor_a_function_tag_errors() {
        let err = e(JsValue::from_f64(1.0), JsValue::NULL, js_sys::Array::new()).unwrap_err();
        assert!(err.as_string().unwrap().contains("e()"));
    }

    #[wasm_bindgen_test]
    fn e_with_a_component_function_invokes_it_once_with_merged_children() {
        let calls = Rc::new(Cell::new(0));
        let c = calls.clone();
        let component: js_sys::Function =
            Closure::<dyn Fn(JsValue) -> JsValue>::new(move |props: JsValue| {
                c.set(c.get() + 1);
                js_sys::Reflect::get(&props, &"children".into()).unwrap()
            })
            .into_js_value()
            .unchecked_into();

        let children = js_sys::Array::of1(&"hello".into());
        let result = e(component.into(), JsValue::NULL, children).unwrap();

        assert_eq!(calls.get(), 1);
        assert_eq!(result.as_string(), Some("hello".into()));
    }

    #[wasm_bindgen_test]
    fn fragment_groups_children_into_a_document_fragment() {
        let props = js_sys::Object::new();
        let children = js_sys::Array::of2(&"a".into(), &"b".into());
        js_sys::Reflect::set(&props, &"children".into(), &children).unwrap();

        let frag = fragment(props.into()).unwrap();
        assert_eq!(frag.child_nodes().length(), 2);
    }

    #[wasm_bindgen_test]
    fn render_mounts_the_tree_and_flushes_queued_layout_effects() {
        let container = crate::dom::document().unwrap().create_element("div").unwrap();
        let ran = Rc::new(Cell::new(false));
        let r = ran.clone();

        let component: js_sys::Function =
            Closure::<dyn Fn(JsValue) -> JsValue>::new(move |_props| {
                let r = r.clone();
                let effect: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
                    r.set(true);
                    JsValue::UNDEFINED
                })
                .into_js_value()
                .unchecked_into();
                signals::queue_layout_effect(effect);
                crate::dom::document()
                    .unwrap()
                    .create_element("span")
                    .unwrap()
                    .into()
            })
            .into_js_value()
            .unchecked_into();

        render(&component, &container).unwrap();

        assert!(ran.get(), "layout effects must run once mounting finishes");
        assert_eq!(container.child_nodes().length(), 1);
    }

    #[wasm_bindgen_test]
    fn render_errors_when_the_container_is_not_an_element() {
        let component: js_sys::Function =
            Closure::<dyn Fn(JsValue) -> JsValue>::new(|_| JsValue::NULL)
                .into_js_value()
                .unchecked_into();
        let err = render(&component, &JsValue::NULL).unwrap_err();
        assert!(err.as_string().unwrap().contains("render()"));
    }

    #[wasm_bindgen_test]
    fn render_errors_when_the_component_does_not_return_a_dom_node() {
        let container = crate::dom::document().unwrap().create_element("div").unwrap();
        let component: js_sys::Function =
            Closure::<dyn Fn(JsValue) -> JsValue>::new(|_| JsValue::from_f64(1.0))
                .into_js_value()
                .unchecked_into();
        let err = render(&component, &container).unwrap_err();
        assert!(err.as_string().unwrap().contains("DOM node"));
    }
}
