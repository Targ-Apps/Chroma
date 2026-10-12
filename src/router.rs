//! Client-side router: URL-style routes with reserved verb handlers
//! (`GET`/`POST`/`PUT`/`DELETE`/`CUSTOM`), reactive navigation and a
//! generic request dispatcher.
//!
//! Chroma ships no bundler and no server-side rendering, so there is no
//! file-system scan like Next.js' `app/` directory: the app builds its own
//! route table (typically one entry per file, by convention) and hands it
//! to [`createRouter`]. Each entry looks like a Next.js route module:
//!
//! ```js
//! const routes = [
//!     {
//!         path: "/",
//!         component: () => e(Library, {}),
//!     },
//!     {
//!         path: "/apps/:id",
//!         component: (props) => e(AppView, { id: props.params.id }),
//!         GET(req) { return loadApp(req.params.id); },
//!         DELETE(req) { return removeApp(req.params.id); },
//!         CUSTOM(op, req) {
//!             if (op === "reload") return reloadApp(req.params.id);
//!             throw new Error(`unknown op: ${op}`);
//!         },
//!     },
//! ];
//!
//! const router = createRouter(routes, { mode: "hash" });
//! router.navigate("/apps/42");
//! await router.request({ method: "DELETE", path: "/apps/42" });
//! ```
//!
//! `GET`, `POST`, `PUT` and `DELETE` are reserved verb names; anything else
//! a route needs to expose (an app-specific action, a webhook-like
//! notification, ...) goes through `CUSTOM(op, request)`, where `op` is the
//! only free-form part of the contract. This mirrors how the desktop
//! shell's `postMessage` bridge already tags each call with an `op` string
//! (see Chroma-Desktop's `chroma-fs` channel) — `request()` gives that
//! pattern one router instead of a hand-rolled `switch`.
//!
//! Two independent concerns share the same route table:
//! - **Navigation** (`navigate`, `back`, `current`, `View`): which page is
//!   showing, driven by a signal so [`crate::components`]-style reactive
//!   re-rendering falls out for free.
//! - **Requests** (`request`): a synchronous-or-async call into a route's
//!   verb handler, independent of what is currently on screen — the shape
//!   a webhook or an RPC bridge needs.
//!
//! Default navigation mode is `"hash"` (`#/path?query`), not `"history"`:
//! Chroma's local dev/app servers (see `docs/architecture.mdx`) only serve
//! static files by exact path with no SPA fallback, so a `pushState`d path
//! would 404 on refresh. `"history"` mode is opt-in for hosts that do
//! rewrite unknown paths to `index.html`.

use std::collections::HashMap;

use wasm_bindgen::JsCast;
use wasm_bindgen::prelude::*;

use crate::signals::{self, BindingTarget};

// --- Route pattern matching (pure — no JsValue, testable with `cargo test`) --

#[derive(Debug, PartialEq, Eq, Clone)]
enum Segment {
    Static(String),
    Param(String),
    /// `*rest` — swallows every remaining segment (must be last).
    Wildcard(String),
}

fn parse_pattern(pattern: &str) -> Vec<Segment> {
    pattern
        .trim_matches('/')
        .split('/')
        .filter(|s| !s.is_empty())
        .map(|s| {
            if let Some(name) = s.strip_prefix(':') {
                Segment::Param(name.to_owned())
            } else if let Some(name) = s.strip_prefix('*') {
                Segment::Wildcard(if name.is_empty() { "wildcard".to_owned() } else { name.to_owned() })
            } else {
                Segment::Static(s.to_owned())
            }
        })
        .collect()
}

fn split_path_segments(path: &str) -> Vec<&str> {
    let path = path.split(['?', '#']).next().unwrap_or("");
    path.trim_matches('/').split('/').filter(|s| !s.is_empty()).collect()
}

/// Matches `path` against a route `pattern` (`/apps/:id`, `/files/*rest`),
/// returning the extracted params or `None` when it does not match. Any
/// query string or hash on `path` is ignored.
fn match_path(pattern: &str, path: &str) -> Option<HashMap<String, String>> {
    let segments = parse_pattern(pattern);
    let parts = split_path_segments(path);

    let mut params = HashMap::new();
    let mut i = 0;
    for segment in &segments {
        match segment {
            Segment::Wildcard(name) => {
                params.insert(name.clone(), parts.get(i..).unwrap_or(&[]).join("/"));
                return Some(params);
            }
            Segment::Param(name) => {
                let value = *parts.get(i)?;
                params.insert(name.clone(), value.to_owned());
                i += 1;
            }
            Segment::Static(expected) => {
                if parts.get(i).copied() != Some(expected.as_str()) {
                    return None;
                }
                i += 1;
            }
        }
    }
    if i == parts.len() { Some(params) } else { None }
}

/// Percent-decodes a `application/x-www-form-urlencoded` component. Works
/// on raw bytes (never slices a `&str`) so malformed input cannot panic on
/// a char-boundary.
fn decode_component(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => {
                out.push(b' ');
                i += 1;
            }
            b'%' if i + 2 < bytes.len() && bytes[i + 1].is_ascii_hexdigit() && bytes[i + 2].is_ascii_hexdigit() => {
                let hi = (bytes[i + 1] as char).to_digit(16).unwrap() as u8;
                let lo = (bytes[i + 2] as char).to_digit(16).unwrap() as u8;
                out.push((hi << 4) | lo);
                i += 3;
            }
            b => {
                out.push(b);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Parses a query string (`"a=1&b=2"` or `"?a=1&b=2"`) into a flat map.
fn parse_query(input: &str) -> HashMap<String, String> {
    let query = input.strip_prefix('?').unwrap_or(input);
    let mut out = HashMap::new();
    if query.is_empty() {
        return out;
    }
    for pair in query.split('&') {
        if pair.is_empty() {
            continue;
        }
        let mut parts = pair.splitn(2, '=');
        let key = decode_component(parts.next().unwrap_or(""));
        let value = decode_component(parts.next().unwrap_or(""));
        out.insert(key, value);
    }
    out
}

fn split_location(location: &str) -> (&str, &str) {
    match location.split_once('?') {
        Some((path, search)) => (path, search),
        None => (location, ""),
    }
}

/// The reserved verbs a route may implement. `Custom` covers everything
/// else, dispatched with an explicit `op` tag so a single route can expose
/// many named actions (webhook-style notifications, app-specific commands)
/// without inventing new reserved words.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Method {
    Get,
    Post,
    Put,
    Delete,
    Custom,
}

impl Method {
    fn parse(raw: &str) -> Method {
        match raw.to_ascii_uppercase().as_str() {
            "GET" => Method::Get,
            "POST" => Method::Post,
            "PUT" => Method::Put,
            "DELETE" => Method::Delete,
            _ => Method::Custom,
        }
    }

    fn handler_key(self) -> &'static str {
        match self {
            Method::Get => "GET",
            Method::Post => "POST",
            Method::Put => "PUT",
            Method::Delete => "DELETE",
            Method::Custom => "CUSTOM",
        }
    }
}

// --- JS interop helpers ------------------------------------------------------

fn get(obj: &js_sys::Object, key: &str) -> JsValue {
    js_sys::Reflect::get(obj, &JsValue::from_str(key)).unwrap_or(JsValue::UNDEFINED)
}

fn set_fn(obj: &js_sys::Object, key: &str, value: js_sys::Function) -> Result<(), JsValue> {
    js_sys::Reflect::set(obj, &JsValue::from_str(key), &value).map(|_| ())
}

fn map_to_object(map: &HashMap<String, String>) -> js_sys::Object {
    let obj = js_sys::Object::new();
    for (key, value) in map {
        js_sys::Reflect::set(&obj, &JsValue::from_str(key), &JsValue::from_str(value)).ok();
    }
    obj
}

/// `matchRoute(pattern, path)` → `{ ...params } | null`. Exposed standalone
/// so an app can build its own matching logic on top of the same rules
/// `createRouter` uses internally.
#[wasm_bindgen(js_name = matchRoute)]
pub fn match_route_js(pattern: String, path: String) -> JsValue {
    match match_path(&pattern, &path) {
        Some(params) => map_to_object(&params).into(),
        None => JsValue::NULL,
    }
}

/// `parseQuery("?a=1&b=2")` → `{ a: "1", b: "2" }`.
#[wasm_bindgen(js_name = parseQuery)]
pub fn parse_query_js(input: String) -> JsValue {
    map_to_object(&parse_query(&input)).into()
}

// --- Location (mode: "hash" | "history") -------------------------------------

fn current_location(mode: &str) -> String {
    let Some(window) = web_sys::window() else {
        return String::new();
    };
    let location = window.location();
    if mode == "history" {
        format!(
            "{}{}",
            location.pathname().unwrap_or_default(),
            location.search().unwrap_or_default()
        )
    } else {
        let hash = location.hash().unwrap_or_default();
        hash.strip_prefix('#').unwrap_or(&hash).to_owned()
    }
}

fn navigate_to(mode: &str, path: &str, replace: bool) {
    let Some(window) = web_sys::window() else {
        return;
    };
    if mode == "history" {
        let Ok(history) = window.history() else {
            return;
        };
        if replace {
            history.replace_state_with_url(&JsValue::NULL, "", Some(path)).ok();
        } else {
            history.push_state_with_url(&JsValue::NULL, "", Some(path)).ok();
        }
    } else {
        let location = window.location();
        if replace {
            location.replace(&format!("#{path}")).ok();
        } else {
            location.set_hash(path).ok();
        }
    }
}

// --- Matching against a live route table -------------------------------------

/// `{ route, path, params, query } | null` for the first route whose
/// pattern matches `location` (path + optional `?search`).
fn build_match_result(routes: &js_sys::Array, location: &str) -> JsValue {
    let (path, search) = split_location(location);
    for route in routes.iter() {
        let Some(route_obj) = route.dyn_ref::<js_sys::Object>() else {
            continue;
        };
        let Some(pattern) = get(route_obj, "path").as_string() else {
            continue;
        };
        let Some(params) = match_path(&pattern, path) else {
            continue;
        };

        let result = js_sys::Object::new();
        js_sys::Reflect::set(&result, &"route".into(), &route).ok();
        js_sys::Reflect::set(&result, &"path".into(), &JsValue::from_str(path)).ok();
        js_sys::Reflect::set(&result, &"params".into(), &map_to_object(&params)).ok();
        js_sys::Reflect::set(&result, &"query".into(), &map_to_object(&parse_query(search))).ok();
        return result.into();
    }
    JsValue::NULL
}

fn render_matched_view(doc: &web_sys::Document, slot: &web_sys::Element, routes: &js_sys::Array, location: &str) {
    crate::dom::clear_children(slot);

    let matched = build_match_result(routes, location);
    let Some(matched_obj) = matched.dyn_ref::<js_sys::Object>() else {
        return;
    };
    let route = get(matched_obj, "route");
    let Some(route_obj) = route.dyn_ref::<js_sys::Object>() else {
        return;
    };
    let Some(component) = get(route_obj, "component").dyn_ref::<js_sys::Function>().cloned() else {
        crate::trace::log_error("chroma: matched route has no `component`");
        return;
    };

    let props = js_sys::Object::new();
    js_sys::Reflect::set(&props, &"params".into(), &get(matched_obj, "params")).ok();
    js_sys::Reflect::set(&props, &"query".into(), &get(matched_obj, "query")).ok();
    js_sys::Reflect::set(&props, &"path".into(), &get(matched_obj, "path")).ok();

    let _frame = crate::trace::push(crate::trace::function_name(&component));
    match component.call1(&JsValue::NULL, &props.into()) {
        Ok(node) => {
            crate::dom::append_child_value(doc, slot, &node).ok();
        }
        Err(err) => {
            crate::trace::log_error_with("chroma: error rendering the matched route:", &err);
        }
    }
}

// --- Verb dispatch (webhook-style requests, independent of navigation) ------

fn status_result(status: u16, message: &str) -> JsValue {
    let obj = js_sys::Object::new();
    js_sys::Reflect::set(&obj, &"ok".into(), &JsValue::FALSE).ok();
    js_sys::Reflect::set(&obj, &"status".into(), &JsValue::from_f64(status as f64)).ok();
    js_sys::Reflect::set(&obj, &"error".into(), &JsValue::from_str(message)).ok();
    obj.into()
}

/// Routes `request` to the matching route's handler for `request.method`.
///
/// - `GET`/`POST`/`PUT`/`DELETE` call `route.METHOD(normalizedRequest)`.
/// - Anything else is treated as `CUSTOM` and calls
///   `route.CUSTOM(request.op, normalizedRequest)`.
/// - No matching route → `{ ok: false, status: 404 }`.
/// - A matching route without that verb → `{ ok: false, status: 405 }`.
///
/// The handler's return value (including a `Promise`, for an async
/// handler) is passed straight back to the caller — `request()` does not
/// itself return a `Promise` unless the handler does.
fn dispatch(routes: &js_sys::Array, request: JsValue) -> JsValue {
    let req_obj = request.dyn_ref::<js_sys::Object>();
    let method_raw = req_obj.and_then(|o| get(o, "method").as_string()).unwrap_or_else(|| "GET".to_owned());
    let path = req_obj.and_then(|o| get(o, "path").as_string()).unwrap_or_default();
    let method = Method::parse(&method_raw);

    for route in routes.iter() {
        let Some(route_obj) = route.dyn_ref::<js_sys::Object>() else {
            continue;
        };
        let Some(pattern) = get(route_obj, "path").as_string() else {
            continue;
        };
        let Some(params) = match_path(&pattern, &path) else {
            continue;
        };

        let handler = get(route_obj, method.handler_key());
        let Some(handler_fn) = handler.dyn_ref::<js_sys::Function>() else {
            return status_result(405, "Method Not Allowed");
        };

        let normalized = js_sys::Object::new();
        js_sys::Reflect::set(&normalized, &"method".into(), &JsValue::from_str(&method_raw)).ok();
        js_sys::Reflect::set(&normalized, &"path".into(), &JsValue::from_str(&path)).ok();
        js_sys::Reflect::set(&normalized, &"params".into(), &map_to_object(&params)).ok();
        let query = req_obj.map(|o| get(o, "query")).unwrap_or(JsValue::UNDEFINED);
        js_sys::Reflect::set(&normalized, &"query".into(), &query).ok();
        let body = req_obj.map(|o| get(o, "body")).unwrap_or(JsValue::UNDEFINED);
        js_sys::Reflect::set(&normalized, &"body".into(), &body).ok();

        // `op` travels on every verb, not just CUSTOM: a route may reuse
        // one sub-operation tag across GET/POST/PUT (e.g. Chroma-Desktop's
        // Chroma-Fs bridge, where `op` picks the exact call within a verb).
        let op = req_obj.and_then(|o| get(o, "op").as_string()).unwrap_or_default();
        js_sys::Reflect::set(&normalized, &"op".into(), &JsValue::from_str(&op)).ok();

        return if method == Method::Custom {
            handler_fn
                .call2(&JsValue::NULL, &JsValue::from_str(&op), &normalized)
                .unwrap_or(JsValue::UNDEFINED)
        } else {
            handler_fn.call1(&JsValue::NULL, &normalized).unwrap_or(JsValue::UNDEFINED)
        };
    }

    status_result(404, "Not Found")
}

// --- createRouter -------------------------------------------------------------

/// Builds a router from a route table: `createRouter(routes, { mode })`.
///
/// `routes` is an array of `{ path, component, GET, POST, PUT, DELETE, CUSTOM }`
/// objects (every key but `path` optional). `options.mode` is `"hash"`
/// (default) or `"history"`.
///
/// Returns a plain JS object:
/// - `navigate(path, { replace? })` — updates the URL and the current match.
/// - `back()` — `history.back()`.
/// - `current()` — reactive getter: `{ route, path, params, query } | null`
///   for right now; call it from inside an effect/attribute/`For` to
///   subscribe to navigation.
/// - `match(path)` — same shape as `current()`, but for an arbitrary path
///   and without subscribing to anything.
/// - `request(req)` — verb dispatch, see [`dispatch`].
/// - `View` — a Chroma component: `e(router.View, {})` mounts the matched
///   route's `component` and re-renders it whenever the location changes.
#[wasm_bindgen(js_name = createRouter)]
pub fn create_router(routes: JsValue, options: JsValue) -> Result<JsValue, JsValue> {
    let routes: js_sys::Array = routes
        .dyn_into()
        .map_err(|_| JsValue::from_str("chroma: createRouter expects an array of routes"))?;

    let mode = options
        .dyn_ref::<js_sys::Object>()
        .and_then(|o| get(o, "mode").as_string())
        .unwrap_or_else(|| "hash".to_owned());

    let location_id = signals::create_signal(JsValue::from_str(&current_location(&mode)));

    if let Some(window) = web_sys::window() {
        let sync_mode = mode.clone();
        let listener: js_sys::Function = Closure::<dyn Fn()>::new(move || {
            signals::write_signal(location_id, JsValue::from_str(&current_location(&sync_mode)));
        })
        .into_js_value()
        .unchecked_into();
        let event_name = if mode == "history" { "popstate" } else { "hashchange" };
        window.add_event_listener_with_callback(event_name, &listener).ok();
    }

    let router = js_sys::Object::new();

    {
        let nav_mode = mode.clone();
        let navigate: js_sys::Function = Closure::<dyn Fn(JsValue, JsValue)>::new(move |path: JsValue, opts: JsValue| {
            let Some(path) = path.as_string() else {
                crate::trace::log_error("chroma: router.navigate expects a string path");
                return;
            };
            let replace = opts
                .dyn_ref::<js_sys::Object>()
                .map(|o| get(o, "replace").is_truthy())
                .unwrap_or(false);
            navigate_to(&nav_mode, &path, replace);
            signals::write_signal(location_id, JsValue::from_str(&current_location(&nav_mode)));
        })
        .into_js_value()
        .unchecked_into();
        set_fn(&router, "navigate", navigate)?;
    }

    {
        let back: js_sys::Function = Closure::<dyn Fn()>::new(|| {
            if let Some(window) = web_sys::window()
                && let Ok(history) = window.history()
            {
                history.back().ok();
            }
        })
        .into_js_value()
        .unchecked_into();
        set_fn(&router, "back", back)?;
    }

    {
        let current_routes = routes.clone();
        let current: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            let location = signals::read_signal(location_id);
            build_match_result(&current_routes, &location.as_string().unwrap_or_default())
        })
        .into_js_value()
        .unchecked_into();
        set_fn(&router, "current", current)?;
    }

    {
        let match_routes = routes.clone();
        let match_fn: js_sys::Function = Closure::<dyn Fn(JsValue) -> JsValue>::new(move |path: JsValue| {
            build_match_result(&match_routes, &path.as_string().unwrap_or_default())
        })
        .into_js_value()
        .unchecked_into();
        set_fn(&router, "match", match_fn)?;
    }

    {
        let request_routes = routes.clone();
        let request_fn: js_sys::Function = Closure::<dyn Fn(JsValue) -> JsValue>::new(move |req: JsValue| dispatch(&request_routes, req))
            .into_js_value()
            .unchecked_into();
        set_fn(&router, "request", request_fn)?;
    }

    {
        let view_routes = routes.clone();
        let view: js_sys::Function = Closure::<dyn Fn(JsValue) -> Result<JsValue, JsValue>>::new(move |_props: JsValue| {
            let doc = crate::dom::document()?;
            let root = doc.create_element("div")?;
            root.set_attribute("style", "display: contents")?;
            let slot = doc.create_element("div")?;
            slot.set_attribute("style", "display: contents")?;
            root.append_child(&slot)?;

            let bound_routes = view_routes.clone();
            let bound_slot = slot.clone();
            signals::create_binding(
                Closure::<dyn Fn() -> JsValue>::new(move || {
                    let location = signals::read_signal(location_id);
                    if let Some(doc) = bound_slot.owner_document() {
                        render_matched_view(&doc, &bound_slot, &bound_routes, &location.as_string().unwrap_or_default());
                    }
                    JsValue::UNDEFINED
                })
                .into_js_value()
                .unchecked_into(),
                BindingTarget::Effect,
            );

            Ok(root.into())
        })
        .into_js_value()
        .unchecked_into();
        set_fn(&router, "View", view)?;
    }

    Ok(router.into())
}

#[cfg(test)]
mod pure_tests {
    use super::*;

    #[test]
    fn match_path_extracts_named_params() {
        let params = match_path("/apps/:id/files/:name", "/apps/42/files/readme.txt").unwrap();
        assert_eq!(params.get("id"), Some(&"42".to_owned()));
        assert_eq!(params.get("name"), Some(&"readme.txt".to_owned()));
    }

    #[test]
    fn match_path_rejects_wrong_segment_count_or_static_mismatch() {
        assert_eq!(match_path("/apps/:id", "/apps"), None);
        assert_eq!(match_path("/apps/:id", "/apps/1/extra"), None);
        assert_eq!(match_path("/apps/:id", "/other/1"), None);
    }

    #[test]
    fn match_path_wildcard_swallows_the_rest_of_the_path() {
        let params = match_path("/files/*rest", "/files/a/b/c.txt").unwrap();
        assert_eq!(params.get("rest"), Some(&"a/b/c.txt".to_owned()));
    }

    #[test]
    fn match_path_ignores_query_and_hash_on_the_matched_path() {
        assert!(match_path("/apps/:id", "/apps/1?tab=files#top").is_some());
    }

    #[test]
    fn match_path_matches_the_root_pattern() {
        assert_eq!(match_path("/", "/").unwrap().len(), 0);
    }

    #[test]
    fn parse_query_decodes_percent_and_plus_encoding() {
        let query = parse_query("?name=Targ%20Apps&tag=a+b");
        assert_eq!(query.get("name"), Some(&"Targ Apps".to_owned()));
        assert_eq!(query.get("tag"), Some(&"a b".to_owned()));
    }

    #[test]
    fn parse_query_of_an_empty_string_is_empty() {
        assert!(parse_query("").is_empty());
        assert!(parse_query("?").is_empty());
    }

    #[test]
    fn decode_component_leaves_a_trailing_incomplete_escape_untouched() {
        assert_eq!(decode_component("100%"), "100%");
        assert_eq!(decode_component("100%2"), "100%2");
    }

    #[test]
    fn method_parse_recognizes_reserved_verbs_case_insensitively() {
        assert_eq!(Method::parse("get"), Method::Get);
        assert_eq!(Method::parse("POST"), Method::Post);
        assert_eq!(Method::parse("Put"), Method::Put);
        assert_eq!(Method::parse("DELETE"), Method::Delete);
        assert_eq!(Method::parse("reload"), Method::Custom);
    }
}

#[cfg(test)]
mod wasm_tests {
    use super::*;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    fn route(path: &str) -> js_sys::Object {
        let obj = js_sys::Object::new();
        js_sys::Reflect::set(&obj, &"path".into(), &JsValue::from_str(path)).unwrap();
        obj
    }

    #[wasm_bindgen_test]
    fn match_route_js_returns_null_when_it_does_not_match() {
        assert!(match_route_js("/apps/:id".into(), "/nope".into()).is_null());
    }

    #[wasm_bindgen_test]
    fn match_route_js_returns_the_params_object() {
        let result = match_route_js("/apps/:id".into(), "/apps/7".into());
        let obj: js_sys::Object = result.unchecked_into();
        assert_eq!(get(&obj, "id").as_string(), Some("7".into()));
    }

    #[wasm_bindgen_test]
    fn dispatch_returns_404_when_no_route_matches() {
        let routes = js_sys::Array::new();
        let req = js_sys::Object::new();
        js_sys::Reflect::set(&req, &"method".into(), &"GET".into()).unwrap();
        js_sys::Reflect::set(&req, &"path".into(), &"/missing".into()).unwrap();

        let result = dispatch(&routes, req.into());
        let obj: js_sys::Object = result.unchecked_into();
        assert_eq!(get(&obj, "status").as_f64(), Some(404.0));
    }

    #[wasm_bindgen_test]
    fn dispatch_returns_405_when_the_route_matches_but_lacks_that_verb() {
        let routes = js_sys::Array::of1(&route("/apps/:id"));
        let req = js_sys::Object::new();
        js_sys::Reflect::set(&req, &"method".into(), &"DELETE".into()).unwrap();
        js_sys::Reflect::set(&req, &"path".into(), &"/apps/1".into()).unwrap();

        let result = dispatch(&routes, req.into());
        let obj: js_sys::Object = result.unchecked_into();
        assert_eq!(get(&obj, "status").as_f64(), Some(405.0));
    }

    #[wasm_bindgen_test]
    fn dispatch_calls_the_matching_verb_handler_with_params() {
        let route_obj = route("/apps/:id");
        let handler: js_sys::Function = Closure::<dyn Fn(JsValue) -> JsValue>::new(|req: JsValue| {
            let req: js_sys::Object = req.unchecked_into();
            get(&req, "params")
        })
        .into_js_value()
        .unchecked_into();
        js_sys::Reflect::set(&route_obj, &"GET".into(), &handler).unwrap();

        let routes = js_sys::Array::of1(&route_obj);
        let req = js_sys::Object::new();
        js_sys::Reflect::set(&req, &"method".into(), &"GET".into()).unwrap();
        js_sys::Reflect::set(&req, &"path".into(), &"/apps/9".into()).unwrap();

        let result = dispatch(&routes, req.into());
        let params: js_sys::Object = result.unchecked_into();
        assert_eq!(get(&params, "id").as_string(), Some("9".into()));
    }

    #[wasm_bindgen_test]
    fn dispatch_routes_custom_method_with_the_op_as_first_argument() {
        let route_obj = route("/apps/:id");
        let handler: js_sys::Function = Closure::<dyn Fn(JsValue, JsValue) -> JsValue>::new(|op: JsValue, _req: JsValue| op)
            .into_js_value()
            .unchecked_into();
        js_sys::Reflect::set(&route_obj, &"CUSTOM".into(), &handler).unwrap();

        let routes = js_sys::Array::of1(&route_obj);
        let req = js_sys::Object::new();
        js_sys::Reflect::set(&req, &"method".into(), &"reload".into()).unwrap();
        js_sys::Reflect::set(&req, &"path".into(), &"/apps/9".into()).unwrap();
        js_sys::Reflect::set(&req, &"op".into(), &"reload".into()).unwrap();

        let result = dispatch(&routes, req.into());
        assert_eq!(result.as_string(), Some("reload".into()));
    }

    #[wasm_bindgen_test]
    fn create_router_navigate_updates_current_and_dispatch_finds_the_new_match() {
        let route_obj = route("/apps/:id");
        let component: js_sys::Function = Closure::<dyn Fn(JsValue) -> JsValue>::new(|_props| crate::dom::document().unwrap().create_element("div").unwrap().into())
            .into_js_value()
            .unchecked_into();
        js_sys::Reflect::set(&route_obj, &"component".into(), &component).unwrap();

        let routes = js_sys::Array::of1(&route_obj);
        let options = js_sys::Object::new();
        js_sys::Reflect::set(&options, &"mode".into(), &"hash".into()).unwrap();

        let router: js_sys::Object = create_router(routes.into(), options.into()).unwrap().unchecked_into();

        let navigate: js_sys::Function = get(&router, "navigate").unchecked_into();
        navigate.call1(&JsValue::NULL, &"/apps/5".into()).unwrap();

        let current: js_sys::Function = get(&router, "current").unchecked_into();
        let matched: js_sys::Object = current.call0(&JsValue::NULL).unwrap().unchecked_into();
        assert_eq!(get(&matched, "path").as_string(), Some("/apps/5".into()));

        let params: js_sys::Object = get(&matched, "params").unchecked_into();
        assert_eq!(get(&params, "id").as_string(), Some("5".into()));
    }
}
