//! Reusable components with style variants: `cx` and `cva`.
//!
//! Both are pure class-name utilities — they know nothing about the DOM or
//! signals — so a "reusable component" stays a plain function built with
//! `e()` (see `components.rs` for the same philosophy applied to control
//! flow). `cva` just gives that function a declarative way to branch its
//! `class` attribute over named variants instead of hand-rolled string
//! concatenation per call site.

use std::collections::HashMap;

use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;

/// Merges class names: `cx("btn", active && "btn-active", ["a", "b"])`.
///
/// Skips `null`/`undefined`/`false`/empty strings, flattens arrays, joins
/// the rest with a single space. Mirrors the common `clsx`/`classnames`
/// helper so conditional classes read the same as everywhere else in JS.
#[wasm_bindgen(js_name = cx, variadic)]
pub fn cx(parts: js_sys::Array) -> String {
    let mut out = Vec::new();
    collect_class_parts(&parts.into(), &mut out);
    out.join(" ")
}

fn collect_class_parts(value: &JsValue, out: &mut Vec<String>) {
    if value.is_null() || value.is_undefined() || *value == JsValue::FALSE {
        return;
    }
    if js_sys::Array::is_array(value) {
        let items: &js_sys::Array = value.unchecked_ref();
        for item in items.iter() {
            collect_class_parts(&item, out);
        }
        return;
    }
    if let Some(s) = value.as_string()
        && !s.is_empty()
    {
        out.push(s);
    }
}

struct CompoundVariant {
    conditions: HashMap<String, String>,
    class: String,
}

/// Defines a reusable class resolver: `cva({ base, variants, compoundVariants, defaultVariants })`.
///
/// Returns a function `(props) => string` that a component calls to
/// compute its root `class` attribute, resolving in order: `base`, the
/// matching option per variant group (falling back to `defaultVariants`
/// when the prop is missing), every `compoundVariants` entry whose
/// conditions all match the selected options, and finally `props.class` /
/// `props.className` verbatim (so callers can still bolt on one-off
/// classes):
///
/// ```js
/// const buttonClass = cva({
///     base: "btn",
///     variants: {
///         variant: { primary: "btn-primary", ghost: "btn-ghost" },
///         size: { sm: "btn-sm", lg: "btn-lg" },
///     },
///     compoundVariants: [
///         { variant: "primary", size: "lg", class: "btn-primary-lg" },
///     ],
///     defaultVariants: { variant: "primary", size: "sm" },
/// });
///
/// function Button(props) {
///     return e("button", { class: buttonClass(props), onClick: props.onClick }, props.children);
/// }
///
/// e(Button, { variant: "ghost", size: "lg" }, "Cancel");
/// ```
///
/// - **`base`** *(optional)* — `string | string[]`, always included.
/// - **`variants`** *(optional)* — `{ group: { option: class } }`.
/// - **`compoundVariants`** *(optional)* — `[{ ...selectedOptions, class }]`,
///   applied when every named group in the entry matches the resolved
///   selection.
/// - **`defaultVariants`** *(optional)* — `{ group: option }`, used for any
///   group missing from `props`.
#[wasm_bindgen(js_name = cva)]
pub fn cva(config: JsValue) -> Result<JsValue, JsValue> {
    let Some(config) = config.dyn_ref::<js_sys::Object>() else {
        return Err(JsValue::from_str("chroma: cva expects a config object"));
    };

    let base = read_class_list(&get(config, "base"));
    let variants = read_variants(config)?;
    let compound_variants = read_compound_variants(config)?;
    let default_variants = read_string_map(&get(config, "defaultVariants"));

    let resolver = move |props: JsValue| -> JsValue {
        let mut selected = default_variants.clone();
        if let Some(props_obj) = props.dyn_ref::<js_sys::Object>() {
            for group in variants.keys() {
                let value = get(props_obj, group);
                if let Some(option) = value.as_string() {
                    selected.insert(group.clone(), option);
                } else if let Some(flag) = value.as_bool() {
                    selected.insert(group.clone(), flag.to_string());
                }
            }
        }

        let mut classes = base.clone();
        for (group, option) in selected.iter() {
            if let Some(class) = variants.get(group).and_then(|options| options.get(option)) {
                classes.push(class.clone());
            }
        }
        for compound in compound_variants.iter() {
            let matches = compound
                .conditions
                .iter()
                .all(|(group, option)| selected.get(group) == Some(option));
            if matches {
                classes.push(compound.class.clone());
            }
        }

        if let Some(props_obj) = props.dyn_ref::<js_sys::Object>() {
            for key in ["class", "className"] {
                if let Some(extra) = get(props_obj, key).as_string()
                    && !extra.is_empty()
                {
                    classes.push(extra);
                }
            }
        }

        JsValue::from_str(&classes.join(" "))
    };

    Ok(Closure::<dyn Fn(JsValue) -> JsValue>::new(resolver).into_js_value())
}

fn get(obj: &js_sys::Object, key: &str) -> JsValue {
    js_sys::Reflect::get(obj, &key.into()).unwrap_or(JsValue::UNDEFINED)
}

fn read_class_list(value: &JsValue) -> Vec<String> {
    let mut out = Vec::new();
    collect_class_parts(value, &mut out);
    out
}

/// `{ key: "string value" }` → `{ key: value }`, skipping non-string entries.
fn read_string_map(value: &JsValue) -> HashMap<String, String> {
    let mut out = HashMap::new();
    if let Some(obj) = value.dyn_ref::<js_sys::Object>() {
        for entry in js_sys::Object::entries(obj).iter() {
            let pair: js_sys::Array = entry.unchecked_into();
            let key = pair.get(0).as_string().unwrap_or_default();
            if let Some(val) = pair.get(1).as_string() {
                out.insert(key, val);
            }
        }
    }
    out
}

/// `variants: { group: { option: "class" } }` → nested owned maps.
fn read_variants(config: &js_sys::Object) -> Result<HashMap<String, HashMap<String, String>>, JsValue> {
    let raw = get(config, "variants");
    let mut out = HashMap::new();
    let Some(groups) = raw.dyn_ref::<js_sys::Object>() else {
        return Ok(out);
    };
    for entry in js_sys::Object::entries(groups).iter() {
        let pair: js_sys::Array = entry.unchecked_into();
        let group = pair.get(0).as_string().unwrap_or_default();
        out.insert(group, read_string_map(&pair.get(1)));
    }
    Ok(out)
}

/// `compoundVariants: [{ ...conditions, class }]` → owned entries.
///
/// Every key besides `class` is treated as a `group: option` condition.
fn read_compound_variants(config: &js_sys::Object) -> Result<Vec<CompoundVariant>, JsValue> {
    let raw = get(config, "compoundVariants");
    let mut out = Vec::new();
    if raw.is_null() || raw.is_undefined() {
        return Ok(out);
    }
    let Some(list) = raw.dyn_ref::<js_sys::Array>() else {
        return Err(JsValue::from_str(
            "chroma: cva expects config.compoundVariants to be an array",
        ));
    };
    for item in list.iter() {
        let Some(entry) = item.dyn_ref::<js_sys::Object>() else {
            return Err(JsValue::from_str(
                "chroma: cva expects every compoundVariants entry to be an object",
            ));
        };
        let Some(class) = get(entry, "class").as_string() else {
            return Err(JsValue::from_str(
                "chroma: cva expects every compoundVariants entry to have a string `class`",
            ));
        };
        let mut conditions = HashMap::new();
        for pair in js_sys::Object::entries(entry).iter() {
            let pair: js_sys::Array = pair.unchecked_into();
            let key = pair.get(0).as_string().unwrap_or_default();
            if key == "class" {
                continue;
            }
            if let Some(val) = pair.get(1).as_string() {
                conditions.insert(key, val);
            }
        }
        out.push(CompoundVariant { conditions, class });
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    fn call(f: &JsValue, arg: JsValue) -> String {
        let f: &js_sys::Function = f.unchecked_ref();
        f.call1(&JsValue::NULL, &arg).unwrap().as_string().unwrap()
    }

    #[wasm_bindgen_test]
    fn cx_skips_falsy_values_and_flattens_arrays() {
        let out = cx(js_sys::Array::of5(
            &"btn".into(),
            &JsValue::FALSE,
            &JsValue::NULL,
            &"".into(),
            &js_sys::Array::of2(&"a".into(), &"b".into()).into(),
        ));
        assert_eq!(out, "btn a b");
    }

    #[wasm_bindgen_test]
    fn cva_resolves_base_plus_selected_variant_options() {
        let config = js_sys::Object::new();
        js_sys::Reflect::set(&config, &"base".into(), &"btn".into()).unwrap();

        let variants = js_sys::Object::new();
        let variant_group = js_sys::Object::new();
        js_sys::Reflect::set(&variant_group, &"primary".into(), &"btn-primary".into()).unwrap();
        js_sys::Reflect::set(&variant_group, &"ghost".into(), &"btn-ghost".into()).unwrap();
        js_sys::Reflect::set(&variants, &"variant".into(), &variant_group).unwrap();
        js_sys::Reflect::set(&config, &"variants".into(), &variants).unwrap();

        let defaults = js_sys::Object::new();
        js_sys::Reflect::set(&defaults, &"variant".into(), &"primary".into()).unwrap();
        js_sys::Reflect::set(&config, &"defaultVariants".into(), &defaults).unwrap();

        let resolver = cva(config.into()).unwrap();

        assert_eq!(call(&resolver, JsValue::UNDEFINED), "btn btn-primary");

        let props = js_sys::Object::new();
        js_sys::Reflect::set(&props, &"variant".into(), &"ghost".into()).unwrap();
        assert_eq!(call(&resolver, props.into()), "btn btn-ghost");
    }

    #[wasm_bindgen_test]
    fn cva_applies_matching_compound_variants_and_trailing_class_prop() {
        let config = js_sys::Object::new();
        js_sys::Reflect::set(&config, &"base".into(), &"btn".into()).unwrap();

        let variants = js_sys::Object::new();
        let variant_group = js_sys::Object::new();
        js_sys::Reflect::set(&variant_group, &"primary".into(), &"btn-primary".into()).unwrap();
        js_sys::Reflect::set(&variants, &"variant".into(), &variant_group).unwrap();
        let size_group = js_sys::Object::new();
        js_sys::Reflect::set(&size_group, &"lg".into(), &"btn-lg".into()).unwrap();
        js_sys::Reflect::set(&variants, &"size".into(), &size_group).unwrap();
        js_sys::Reflect::set(&config, &"variants".into(), &variants).unwrap();

        let compound = js_sys::Object::new();
        js_sys::Reflect::set(&compound, &"variant".into(), &"primary".into()).unwrap();
        js_sys::Reflect::set(&compound, &"size".into(), &"lg".into()).unwrap();
        js_sys::Reflect::set(&compound, &"class".into(), &"btn-primary-lg".into()).unwrap();
        js_sys::Reflect::set(
            &config,
            &"compoundVariants".into(),
            &js_sys::Array::of1(&compound),
        )
        .unwrap();

        let resolver = cva(config.into()).unwrap();

        let props = js_sys::Object::new();
        js_sys::Reflect::set(&props, &"variant".into(), &"primary".into()).unwrap();
        js_sys::Reflect::set(&props, &"size".into(), &"lg".into()).unwrap();
        js_sys::Reflect::set(&props, &"class".into(), &"mt-4".into()).unwrap();

        assert_eq!(
            call(&resolver, props.into()),
            "btn btn-primary btn-lg btn-primary-lg mt-4"
        );
    }

    #[wasm_bindgen_test]
    fn cva_requires_a_config_object() {
        let err = cva(JsValue::UNDEFINED).unwrap_err();
        assert!(err.as_string().unwrap().contains("cva"));
    }
}
