//! Reactive control-flow components (`Show`, `For`).
//!
//! They mount their content exactly once (preserving inner hooks) and only
//! update what depends on the subscribed signals.

use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;

use crate::dom::{append_child_value, clear_children, document};
use crate::signals::{self, BindingTarget};

/// JavaScript truthiness for numbers: `0`, `-0` and `NaN` are falsy.
fn number_is_truthy(n: f64) -> bool {
    !(n == 0.0 || n.is_nan())
}

fn js_truthy(value: &JsValue) -> bool {
    if value.is_null() || value.is_undefined() {
        return false;
    }
    if *value == JsValue::FALSE {
        return false;
    }
    if let Some(n) = value.as_f64()
        && !number_is_truthy(n)
    {
        return false;
    }
    if let Some(s) = value.as_string()
        && s.is_empty()
    {
        return false;
    }
    true
}

fn prop_fn(props: &js_sys::Object, key: &str) -> Option<js_sys::Function> {
    js_sys::Reflect::get(props, &key.into())
        .ok()
        .and_then(|v| v.dyn_ref::<js_sys::Function>().cloned())
}

/// Conditional rendering: `e(Show, { when: getter, fallback: () => ... }, () => ...)`.
///
/// Mounts both branches exactly once; only toggles visibility based on `when`.
#[wasm_bindgen(js_name = Show)]
pub fn show(props: JsValue) -> Result<JsValue, JsValue> {
    let Some(props) = props.dyn_ref::<js_sys::Object>() else {
        return Err(JsValue::from_str("chroma: Show expects a props object"));
    };

    let Some(when_fn) = prop_fn(props, "when") else {
        return Err(JsValue::from_str(
            "chroma: Show requires props.when to be a getter (function)",
        ));
    };

    let doc = document()?;
    let root = doc.create_element("div")?;
    root.set_attribute("style", "display: contents")?;

    let fallback_slot = doc.create_element("div")?;
    let content_slot = doc.create_element("div")?;

    if let Some(fallback_fn) = prop_fn(props, "fallback") {
        let node = signals::untracked(|| fallback_fn.call0(&JsValue::NULL))?;
        append_child_value(&doc, &fallback_slot, &node)?;
    }

    let children = js_sys::Reflect::get(props, &"children".into()).unwrap_or(JsValue::UNDEFINED);
    if let Some(child_fn) = children.dyn_ref::<js_sys::Function>() {
        let node = signals::untracked(|| child_fn.call0(&JsValue::NULL))?;
        append_child_value(&doc, &content_slot, &node)?;
    } else {
        append_child_value(&doc, &content_slot, &children)?;
    }

    root.append_child(&fallback_slot)?;
    root.append_child(&content_slot)?;

    let content = content_slot.clone();
    let fallback = fallback_slot.clone();
    signals::create_binding(
        Closure::<dyn Fn() -> JsValue>::new(move || {
            let show = js_truthy(&when_fn.call0(&JsValue::NULL).unwrap_or(JsValue::UNDEFINED));
            let (content_style, fallback_style) = if show {
                ("display: contents;", "display: none;")
            } else {
                ("display: none;", "display: contents;")
            };
            content.set_attribute("style", content_style).ok();
            fallback.set_attribute("style", fallback_style).ok();
            JsValue::UNDEFINED
        })
        .into_js_value()
        .unchecked_into(),
        BindingTarget::Effect,
    );

    Ok(root.into())
}

/// Reactive list: `e(For, { each: getter, children: (item) => node })`.
///
/// Rebuilds the child nodes only when the array read by `each` changes.
#[wasm_bindgen(js_name = For)]
pub fn for_each(props: JsValue) -> Result<JsValue, JsValue> {
    let Some(props) = props.dyn_ref::<js_sys::Object>() else {
        return Err(JsValue::from_str("chroma: For expects a props object"));
    };

    let Some(each_fn) = prop_fn(props, "each") else {
        return Err(JsValue::from_str(
            "chroma: For requires props.each to be a getter (function)",
        ));
    };

    let children = js_sys::Reflect::get(props, &"children".into()).unwrap_or(JsValue::UNDEFINED);
    let Some(render_fn) = children.dyn_ref::<js_sys::Function>().cloned() else {
        return Err(JsValue::from_str(
            "chroma: For requires props.children to be a function: (item) => node",
        ));
    };

    let doc = document()?;
    let container = doc.create_element("span")?;
    container.set_attribute("style", "display: contents")?;

    let slot = container.clone();
    signals::create_binding(
        Closure::<dyn Fn() -> JsValue>::new(move || {
            let items = each_fn
                .call0(&JsValue::NULL)
                .unwrap_or(JsValue::UNDEFINED);
            signals::untracked(|| {
                clear_children(&slot);
                if let Some(arr) = items.dyn_ref::<js_sys::Array>() {
                    for item in arr.iter() {
                        if let Ok(node) = render_fn.call1(&JsValue::NULL, &item) {
                            append_child_value(&doc, &slot, &node).ok();
                        }
                    }
                }
            });
            JsValue::UNDEFINED
        })
        .into_js_value()
        .unchecked_into(),
        BindingTarget::Effect,
    );

    Ok(container.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signals::{create_signal, read_signal, write_signal};
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    fn getter_over(id: crate::graph::SignalId) -> js_sys::Function {
        Closure::<dyn Fn() -> JsValue>::new(move || read_signal(id))
            .into_js_value()
            .unchecked_into()
    }

    #[wasm_bindgen_test]
    fn show_mounts_both_branches_once_and_toggles_display_on_when_change() {
        let when = create_signal(JsValue::from_bool(true));

        let props = js_sys::Object::new();
        js_sys::Reflect::set(&props, &"when".into(), &getter_over(when)).unwrap();

        let content: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(|| {
            document().unwrap().create_text_node("content").into()
        })
        .into_js_value()
        .unchecked_into();
        js_sys::Reflect::set(&props, &"children".into(), &content).unwrap();

        let fallback: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(|| {
            document().unwrap().create_text_node("fallback").into()
        })
        .into_js_value()
        .unchecked_into();
        js_sys::Reflect::set(&props, &"fallback".into(), &fallback).unwrap();

        let root: web_sys::Element = show(props.into()).unwrap().unchecked_into();
        // Layout: fallback_slot is appended first, content_slot second (see `show` above).
        let fallback_slot = root.first_element_child().unwrap();
        let content_slot = root.last_element_child().unwrap();

        assert_eq!(content_slot.get_attribute("style").as_deref(), Some("display: contents;"));
        assert_eq!(fallback_slot.get_attribute("style").as_deref(), Some("display: none;"));

        write_signal(when, JsValue::from_bool(false));

        assert_eq!(content_slot.get_attribute("style").as_deref(), Some("display: none;"));
        assert_eq!(fallback_slot.get_attribute("style").as_deref(), Some("display: contents;"));
        // Both branches stay mounted — toggling only flips visibility.
        assert!(root.text_content().unwrap().contains("content"));
        assert!(root.text_content().unwrap().contains("fallback"));
    }

    #[wasm_bindgen_test]
    fn show_requires_a_when_getter() {
        let props = js_sys::Object::new();
        let err = show(props.into()).unwrap_err();
        assert!(err.as_string().unwrap().contains("when"));
    }

    #[wasm_bindgen_test]
    fn for_each_rebuilds_the_list_when_the_array_reference_changes() {
        let items = create_signal(js_sys::Array::of2(&"a".into(), &"b".into()).into());

        let props = js_sys::Object::new();
        js_sys::Reflect::set(&props, &"each".into(), &getter_over(items)).unwrap();
        let render_item: js_sys::Function =
            Closure::<dyn Fn(JsValue) -> JsValue>::new(|item: JsValue| {
                document()
                    .unwrap()
                    .create_text_node(&format!("[{}]", item.as_string().unwrap()))
                    .into()
            })
            .into_js_value()
            .unchecked_into();
        js_sys::Reflect::set(&props, &"children".into(), &render_item).unwrap();

        let root: web_sys::Element = for_each(props.into()).unwrap().unchecked_into();
        assert_eq!(root.text_content().as_deref(), Some("[a][b]"));

        write_signal(
            items,
            js_sys::Array::of3(&"a".into(), &"b".into(), &"c".into()).into(),
        );
        assert_eq!(root.text_content().as_deref(), Some("[a][b][c]"));
    }

    #[wasm_bindgen_test]
    fn for_each_requires_an_each_getter_and_a_children_function() {
        let props = js_sys::Object::new();
        assert!(for_each(props.clone().into()).is_err());

        js_sys::Reflect::set(
            &props,
            &"each".into(),
            &getter_over(create_signal(js_sys::Array::new().into())),
        )
        .unwrap();
        assert!(for_each(props.into()).is_err()); // still missing `children`
    }

    #[test]
    fn number_truthiness_matches_javascript() {
        assert!(!number_is_truthy(0.0));
        assert!(!number_is_truthy(-0.0));
        assert!(!number_is_truthy(f64::NAN));
        assert!(number_is_truthy(1.0));
        assert!(number_is_truthy(-1.0));
        assert!(number_is_truthy(f64::INFINITY));
    }

    #[wasm_bindgen_test]
    fn js_truthy_matches_javascript() {
        assert!(!js_truthy(&JsValue::from_f64(f64::NAN)));
        assert!(!js_truthy(&JsValue::from_f64(0.0)));
        assert!(!js_truthy(&JsValue::from_f64(-0.0)));
        assert!(!js_truthy(&JsValue::from_str("")));
        assert!(!js_truthy(&JsValue::NULL));
        assert!(!js_truthy(&JsValue::UNDEFINED));
        assert!(!js_truthy(&JsValue::FALSE));
        assert!(js_truthy(&JsValue::from_f64(1.0)));
        assert!(js_truthy(&JsValue::from_str("a")));
    }
}
