//! DOM node creation and reactive binding mounting via web-sys.

use std::borrow::Cow;

use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;

use crate::signals::{BindingTarget, create_binding, to_display_string};

pub fn document() -> Result<web_sys::Document, JsValue> {
    web_sys::window()
        .and_then(|w| w.document())
        .ok_or_else(|| JsValue::from_str("chroma: no document available (are you running in a browser?)"))
}

/// Creates an HTML element with its props and children.
pub fn create_element(
    tag: &str,
    props: &JsValue,
    children: &js_sys::Array,
) -> Result<web_sys::Element, JsValue> {
    let doc = document()?;
    let element = doc.create_element(tag)?;

    if props.is_object() {
        for entry in js_sys::Object::entries(props.unchecked_ref()).iter() {
            let pair: js_sys::Array = entry.unchecked_into();
            let key = pair.get(0).as_string().unwrap_or_default();
            let value = pair.get(1);
            apply_prop(&element, &key, &value)?;
        }
    }

    for child in children.iter() {
        append_child_value(&doc, &element, &child)?;
    }

    Ok(element)
}

/// Creates a DocumentFragment with the given children.
pub fn create_fragment(children: &js_sys::Array) -> Result<web_sys::DocumentFragment, JsValue> {
    let doc = document()?;
    let fragment = doc.create_document_fragment();
    for child in children.iter() {
        append_child_value(&doc, &fragment, &child)?;
    }
    Ok(fragment)
}

fn apply_prop(element: &web_sys::Element, key: &str, value: &JsValue) -> Result<(), JsValue> {
    // ref: delivers the freshly created node (useRef object or callback).
    if key == "ref" {
        if let Some(callback) = value.dyn_ref::<js_sys::Function>() {
            callback.call1(&JsValue::NULL, element)?;
        } else if value.is_object() {
            js_sys::Reflect::set(value, &"current".into(), element)?;
        }
        return Ok(());
    }

    // Events: onClick, onInput, ... → listener for "click", "input", ...
    if let Some(event) = key.strip_prefix("on")
        && !event.is_empty()
        && value.is_function()
    {
        let listener: &js_sys::Function = value.unchecked_ref();
        element.add_event_listener_with_callback(dom_event_name(event).as_ref(), listener)?;
        return Ok(());
    }

    // Function prop (non-event) → reactive attribute.
    if value.is_function() {
        create_binding(
            value.clone().unchecked_into(),
            BindingTarget::Attribute {
                element: element.clone(),
                name: attribute_name_stored(key),
            },
        );
        return Ok(());
    }

    // Static attribute; false/null/undefined mean "no attribute".
    if value.is_null() || value.is_undefined() || *value == JsValue::FALSE {
        return Ok(());
    }
    element.set_attribute(attribute_name(key), &to_display_string(value))
}

/// DOM attribute name for one-off `set_attribute` calls (no allocation for most keys).
fn attribute_name(key: &str) -> &str {
    match key {
        "className" => "class",
        "htmlFor" => "for",
        _ => key,
    }
}

/// Stored on the binding target (must own when aliasing React-style names).
fn attribute_name_stored(key: &str) -> String {
    match key {
        "className" => "class".to_owned(),
        "htmlFor" => "for".to_owned(),
        _ => key.to_owned(),
    }
}

/// `onClick` → `click`; avoids allocating when the suffix is already lowercase.
fn dom_event_name(event: &str) -> Cow<'_, str> {
    if event.bytes().any(|b| b.is_ascii_uppercase()) {
        Cow::Owned(event.to_ascii_lowercase())
    } else {
        Cow::Borrowed(event)
    }
}

/// Removes all children from a container node.
pub fn clear_children(parent: &web_sys::Node) {
    while let Some(child) = parent.first_child() {
        parent.remove_child(&child).ok();
    }
}

/// Replaces the content of a dynamic slot with the evaluated value.
pub fn replace_slot_content(doc: &web_sys::Document, slot: &web_sys::Element, value: &JsValue) {
    clear_children(slot);
    append_child_value(doc, slot, value).ok();
}

/// Appends an arbitrary value as a child: nodes, text, reactive
/// functions or arrays (flattened recursively).
pub fn append_child_value(
    doc: &web_sys::Document,
    parent: &web_sys::Node,
    child: &JsValue,
) -> Result<(), JsValue> {
    // null/undefined/booleans render nothing.
    if child.is_null() || child.is_undefined() || child.as_bool().is_some() {
        return Ok(());
    }

    if let Some(node) = child.dyn_ref::<web_sys::Node>() {
        parent.append_child(node)?;
        return Ok(());
    }

    if child.is_function() {
        // Reactive child: slot with a binding that accepts DOM nodes or text.
        let slot = doc.create_element("span")?;
        slot.set_attribute("style", "display: contents")?;
        parent.append_child(&slot)?;
        create_binding(
            child.clone().unchecked_into(),
            BindingTarget::DynamicChild { slot },
        );
        return Ok(());
    }

    if js_sys::Array::is_array(child) {
        let items: &js_sys::Array = child.unchecked_ref();
        for item in items.iter() {
            append_child_value(doc, parent, &item)?;
        }
        return Ok(());
    }

    let text = doc.create_text_node(&to_display_string(child));
    parent.append_child(&text)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signals::{create_signal, read_signal, write_signal};
    use std::cell::{Cell, RefCell};
    use std::rc::Rc;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    #[wasm_bindgen_test]
    fn create_element_sets_static_attributes_with_name_aliases() {
        let props = js_sys::Object::new();
        js_sys::Reflect::set(&props, &"className".into(), &"card".into()).unwrap();
        js_sys::Reflect::set(&props, &"htmlFor".into(), &"input-id".into()).unwrap();
        js_sys::Reflect::set(&props, &"title".into(), &"hi".into()).unwrap();

        let el = create_element("label", &props.into(), &js_sys::Array::new()).unwrap();

        assert_eq!(el.get_attribute("class").as_deref(), Some("card"));
        assert_eq!(el.get_attribute("for").as_deref(), Some("input-id"));
        assert_eq!(el.get_attribute("title").as_deref(), Some("hi"));
    }

    #[wasm_bindgen_test]
    fn create_element_omits_falsy_attributes() {
        let props = js_sys::Object::new();
        js_sys::Reflect::set(&props, &"hidden".into(), &JsValue::FALSE).unwrap();
        js_sys::Reflect::set(&props, &"data-x".into(), &JsValue::NULL).unwrap();

        let el = create_element("div", &props.into(), &js_sys::Array::new()).unwrap();

        assert!(!el.has_attribute("hidden"));
        assert!(!el.has_attribute("data-x"));
    }

    #[wasm_bindgen_test]
    fn create_element_wires_on_prefixed_function_props_as_event_listeners() {
        let clicks = Rc::new(Cell::new(0));
        let c = clicks.clone();
        let on_click: js_sys::Function = Closure::<dyn Fn()>::new(move || c.set(c.get() + 1))
            .into_js_value()
            .unchecked_into();

        let props = js_sys::Object::new();
        js_sys::Reflect::set(&props, &"onClick".into(), &on_click).unwrap();
        let el = create_element("button", &props.into(), &js_sys::Array::new()).unwrap();

        el.dispatch_event(&web_sys::Event::new("click").unwrap())
            .unwrap();
        assert_eq!(clicks.get(), 1);
    }

    #[wasm_bindgen_test]
    fn create_element_ref_prop_sets_current_on_an_object_ref() {
        let ref_obj = js_sys::Object::new();
        let props = js_sys::Object::new();
        js_sys::Reflect::set(&props, &"ref".into(), &ref_obj).unwrap();

        let el = create_element("div", &props.into(), &js_sys::Array::new()).unwrap();

        let current = js_sys::Reflect::get(&ref_obj, &"current".into()).unwrap();
        let current_el = current
            .dyn_ref::<web_sys::Element>()
            .expect("current should hold the created element");
        assert_eq!(current_el, &el);
    }

    #[wasm_bindgen_test]
    fn create_element_ref_prop_invokes_a_callback_ref() {
        let received: Rc<RefCell<Option<web_sys::Element>>> = Rc::new(RefCell::new(None));
        let r = received.clone();
        let ref_cb: js_sys::Function = Closure::<dyn Fn(web_sys::Element)>::new(move |el| {
            *r.borrow_mut() = Some(el);
        })
        .into_js_value()
        .unchecked_into();

        let props = js_sys::Object::new();
        js_sys::Reflect::set(&props, &"ref".into(), &ref_cb).unwrap();
        let el = create_element("div", &props.into(), &js_sys::Array::new()).unwrap();

        assert_eq!(received.borrow().as_ref(), Some(&el));
    }

    #[wasm_bindgen_test]
    fn create_element_function_prop_becomes_a_reactive_attribute() {
        let id = create_signal(JsValue::from_str("light"));
        let getter: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || read_signal(id))
            .into_js_value()
            .unchecked_into();

        let props = js_sys::Object::new();
        js_sys::Reflect::set(&props, &"class".into(), &getter).unwrap();
        let el = create_element("main", &props.into(), &js_sys::Array::new()).unwrap();

        assert_eq!(el.get_attribute("class").as_deref(), Some("light"));
        write_signal(id, JsValue::from_str("dark"));
        assert_eq!(el.get_attribute("class").as_deref(), Some("dark"));
    }

    #[wasm_bindgen_test]
    fn append_child_value_renders_text_and_skips_null_and_booleans() {
        let doc = document().unwrap();
        let parent = doc.create_element("div").unwrap();

        append_child_value(&doc, &parent, &JsValue::from_f64(3.0)).unwrap();
        append_child_value(&doc, &parent, &JsValue::NULL).unwrap();
        append_child_value(&doc, &parent, &JsValue::from_bool(true)).unwrap();

        assert_eq!(parent.child_nodes().length(), 1);
        assert_eq!(parent.text_content().as_deref(), Some("3"));
    }

    #[wasm_bindgen_test]
    fn append_child_value_flattens_nested_arrays_recursively() {
        let doc = document().unwrap();
        let parent = doc.create_element("ul").unwrap();

        let inner = js_sys::Array::of2(&"a".into(), &"b".into());
        let outer = js_sys::Array::of2(&"x".into(), &inner);

        append_child_value(&doc, &parent, &outer.into()).unwrap();

        assert_eq!(parent.child_nodes().length(), 3);
        assert_eq!(parent.text_content().as_deref(), Some("xab"));
    }

    #[wasm_bindgen_test]
    fn append_child_value_mounts_a_reactive_slot_that_updates_on_write() {
        let id = create_signal(JsValue::from_f64(1.0));
        let doc = document().unwrap();
        let parent = doc.create_element("p").unwrap();

        let getter: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || read_signal(id))
            .into_js_value()
            .unchecked_into();
        append_child_value(&doc, &parent, &getter.into()).unwrap();

        assert_eq!(parent.text_content().as_deref(), Some("1"));
        write_signal(id, JsValue::from_f64(2.0));
        assert_eq!(parent.text_content().as_deref(), Some("2"));
    }
}
