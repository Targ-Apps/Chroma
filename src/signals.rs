//! Reactive runtime: signal values, bindings and their re-execution.
//!
//! WASM is single-threaded, so the runtime lives in a `thread_local`.
//! Re-entrancy rule: never hold the `RUNTIME` borrow while invoking JS code
//! (a binding expression may read or write signals).

use std::cell::RefCell;

use wasm_bindgen::prelude::*;

use crate::graph::{BindingId, DepGraph, SignalId, UNTRACKED};

/// What a binding does with the result of its expression.
#[derive(Clone)]
pub enum BindingTarget {
    /// Rewrites (or removes) an attribute.
    Attribute {
        element: web_sys::Element,
        name: String,
    },
    /// Pure side effect: if the result is a function, it is stored as a
    /// cleanup and invoked before the next re-execution.
    Effect,
    /// Derived value: the result is written into the signal (useMemo).
    Memo(SignalId),
    /// Dynamic child: the expression may return DOM nodes or text.
    DynamicChild { slot: web_sys::Element },
}

struct Binding {
    expr: js_sys::Function,
    target: BindingTarget,
    cleanup: Option<js_sys::Function>,
}

#[derive(Default)]
struct Runtime {
    graph: DepGraph,
    values: Vec<JsValue>,
    bindings: Vec<Binding>,
    /// Per context: stack of active provider values.
    contexts: Vec<Vec<JsValue>>,
    /// Pending layout effects: fired once mounting finishes.
    layout_queue: Vec<js_sys::Function>,
}

thread_local! {
    static RUNTIME: RefCell<Runtime> = RefCell::new(Runtime::default());
}

pub fn create_signal(initial: JsValue) -> SignalId {
    RUNTIME.with(|rt| {
        let mut rt = rt.borrow_mut();
        rt.values.push(initial);
        rt.graph.add_signal()
    })
}

/// Reads the current value and, if a binding is being evaluated, registers the dependency.
pub fn read_signal(id: SignalId) -> JsValue {
    RUNTIME.with(|rt| {
        let mut rt = rt.borrow_mut();
        rt.graph.track_read(id);
        rt.values.get(id).cloned().unwrap_or(JsValue::UNDEFINED)
    })
}

/// Reads the current value without registering a dependency (for dispatch/internal use).
pub fn peek_signal(id: SignalId) -> JsValue {
    RUNTIME.with(|rt| {
        rt.borrow()
            .values
            .get(id)
            .cloned()
            .unwrap_or(JsValue::UNDEFINED)
    })
}

/// Runs `f` with tracking suppressed: inner reads do not subscribe.
pub fn untracked<T>(f: impl FnOnce() -> T) -> T {
    RUNTIME.with(|rt| rt.borrow_mut().graph.begin_tracking(UNTRACKED));
    let out = f();
    RUNTIME.with(|rt| rt.borrow_mut().graph.end_tracking());
    out
}

/// Writes the signal and re-executes its bindings. Does not notify if the
/// value did not change (`Object.is` comparison).
pub fn write_signal(id: SignalId, value: JsValue) {
    let dependents = RUNTIME.with(|rt| {
        let mut rt = rt.borrow_mut();
        let Some(slot) = rt.values.get_mut(id) else {
            crate::trace::log_error(&format!("chroma: signal {id} does not exist"));
            return Vec::new();
        };
        if js_sys::Object::is(slot, &value) {
            return Vec::new();
        }
        *slot = value;
        rt.graph.subscriber_snapshot(id)
    });

    for binding in dependents {
        run_binding(binding);
    }
}

/// Registers a reactive binding and runs it for the first time.
pub fn create_binding(expr: js_sys::Function, target: BindingTarget) {
    let id = RUNTIME.with(|rt| {
        let mut rt = rt.borrow_mut();
        rt.bindings.push(Binding {
            expr,
            target,
            cleanup: None,
        });
        rt.graph.add_binding()
    });
    run_binding(id);
}

fn run_binding(id: BindingId) {
    // Reentrancy guard: a binding's own expression (or one of the `deps`
    // getters it reads while tracking, see `hooks::reactive_expr`) can write
    // to a signal it is itself subscribed to — e.g. passing a `useCallback`
    // result as a dependency calls it as if it were a getter, running its
    // body and, if that body calls a setter, writing back into the same
    // signal mid-evaluation. That write immediately re-triggers this exact
    // binding before it has finished its first run, which would re-trigger
    // it again, and so on: unbounded Rust-side recursion ending in a stack
    // overflow that surfaces in the browser as an opaque wasm "unreachable"
    // trap, with no indication of which component or binding caused it.
    // Detecting the binding is already on the tracking stack turns that
    // crash into a single, traceable diagnostic instead.
    if RUNTIME.with(|rt| rt.borrow().graph.is_evaluating(id)) {
        crate::trace::log_error(&format!(
            "chroma: update loop — binding #{id} wrote to a signal it depends on while still \
             evaluating, re-triggering itself before finishing. Skipped the re-entrant run to \
             avoid a stack overflow. Likely cause: a setter called unconditionally inside a \
             memo/effect body or one of its `deps` getters (e.g. a `useCallback` result passed \
             as a dependency — calling it to \"read\" it actually runs its body)."
        ));
        return;
    }

    let Some((expr, target, cleanup)) = RUNTIME.with(|rt| {
        let mut rt = rt.borrow_mut();
        rt.bindings
            .get_mut(id)
            .map(|b| (b.expr.clone(), b.target.clone(), b.cleanup.take()))
    }) else {
        return;
    };

    // Cleanup of the previous effect, outside any tracking scope.
    if let Some(cleanup) = cleanup
        && let Err(err) = untracked(|| cleanup.call0(&JsValue::NULL))
    {
        crate::trace::log_error_with("chroma: error in effect cleanup:", &err);
    }

    // Evaluate the JS expression with the tracking scope open: every getter
    // called inside registers its dependency.
    RUNTIME.with(|rt| rt.borrow_mut().graph.begin_tracking(id));
    let result = expr.call0(&JsValue::NULL);
    RUNTIME.with(|rt| rt.borrow_mut().graph.end_tracking());

    match result {
        Ok(value) => apply_result(id, &target, value),
        Err(err) => {
            crate::trace::log_error_with("chroma: error evaluating a binding:", &err);
        }
    }
}

fn apply_result(id: BindingId, target: &BindingTarget, value: JsValue) {
    match target {
        BindingTarget::Attribute { element, name } => {
            // Dynamic attribute semantics: false/null/undefined remove it.
            if value.is_null() || value.is_undefined() || value == JsValue::FALSE {
                element.remove_attribute(name).ok();
            } else if element
                .set_attribute(name, &to_display_string(&value))
                .is_err()
            {
                crate::trace::log_error(&format!("chroma: failed to set attribute '{name}'"));
            }
        }
        BindingTarget::Effect => {
            if value.is_function() {
                RUNTIME.with(|rt| {
                    if let Some(binding) = rt.borrow_mut().bindings.get_mut(id) {
                        binding.cleanup = Some(value.unchecked_into());
                    }
                });
            }
        }
        BindingTarget::Memo(signal) => write_signal(*signal, value),
        BindingTarget::DynamicChild { slot } => {
            if let Some(doc) = slot.owner_document() {
                crate::dom::replace_slot_content(&doc, slot, &value);
            }
        }
    }
}

/// Queues a layout effect; it will run once `render` finishes mounting.
pub fn queue_layout_effect(expr: js_sys::Function) {
    RUNTIME.with(|rt| rt.borrow_mut().layout_queue.push(expr));
}

/// Fires the pending layout effects (with the DOM already mounted). The loop
/// covers effects queued by components created inside another effect.
pub fn flush_layout_effects() {
    loop {
        let pending = RUNTIME.with(|rt| std::mem::take(&mut rt.borrow_mut().layout_queue));
        if pending.is_empty() {
            return;
        }
        for expr in pending {
            create_binding(expr, BindingTarget::Effect);
        }
    }
}

// --- Contexts (createContext / useContext) ----------------------------------

pub fn create_context_slot() -> usize {
    RUNTIME.with(|rt| {
        let mut rt = rt.borrow_mut();
        rt.contexts.push(Vec::new());
        rt.contexts.len() - 1
    })
}

pub fn push_context(id: usize, value: JsValue) {
    RUNTIME.with(|rt| {
        if let Some(stack) = rt.borrow_mut().contexts.get_mut(id) {
            stack.push(value);
        }
    });
}

pub fn pop_context(id: usize) {
    RUNTIME.with(|rt| {
        if let Some(stack) = rt.borrow_mut().contexts.get_mut(id) {
            stack.pop();
        }
    });
}

/// Value of the nearest active provider, if there is one.
pub fn read_context(id: usize) -> Option<JsValue> {
    RUNTIME.with(|rt| rt.borrow().contexts.get(id).and_then(|s| s.last().cloned()))
}

/// Text coercion for nodes and attributes: null/undefined render as empty.
pub fn to_display_string(value: &JsValue) -> String {
    if value.is_null() || value.is_undefined() {
        String::new()
    } else if let Some(s) = value.as_string() {
        s
    } else if let Some(n) = value.as_f64() {
        format!("{n}")
    } else if let Some(b) = value.as_bool() {
        b.to_string()
    } else {
        js_sys::JSON::stringify(value)
            .ok()
            .and_then(|s| s.as_string())
            .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    use std::rc::Rc;
    use wasm_bindgen_test::*;

    wasm_bindgen_test_configure!(run_in_browser);

    /// Binding whose expression reads `source` (registering a dependency) and
    /// increments `counter` every time it runs.
    fn counting_binding(counter: Rc<Cell<u32>>, source: SignalId) -> js_sys::Function {
        Closure::<dyn Fn() -> JsValue>::new(move || {
            read_signal(source);
            counter.set(counter.get() + 1);
            JsValue::UNDEFINED
        })
        .into_js_value()
        .unchecked_into()
    }

    #[wasm_bindgen_test]
    fn read_signal_returns_the_stored_value() {
        let id = create_signal(JsValue::from_f64(42.0));
        assert_eq!(read_signal(id).as_f64(), Some(42.0));
    }

    #[wasm_bindgen_test]
    fn write_signal_reruns_subscribed_bindings() {
        let id = create_signal(JsValue::from_f64(0.0));
        let counter = Rc::new(Cell::new(0));
        create_binding(counting_binding(counter.clone(), id), BindingTarget::Effect);
        assert_eq!(counter.get(), 1); // initial run on creation

        write_signal(id, JsValue::from_f64(1.0));
        assert_eq!(counter.get(), 2);
    }

    #[wasm_bindgen_test]
    fn write_signal_with_an_object_is_equal_value_does_not_notify() {
        let id = create_signal(JsValue::from_f64(7.0));
        let counter = Rc::new(Cell::new(0));
        create_binding(counting_binding(counter.clone(), id), BindingTarget::Effect);
        assert_eq!(counter.get(), 1);

        write_signal(id, JsValue::from_f64(7.0)); // Object.is-equal to the current value
        assert_eq!(counter.get(), 1);
    }

    #[wasm_bindgen_test]
    fn peek_signal_does_not_register_a_dependency() {
        let id = create_signal(JsValue::from_f64(1.0));
        let counter = Rc::new(Cell::new(0));
        let c = counter.clone();
        let expr: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            peek_signal(id); // read without tracking
            c.set(c.get() + 1);
            JsValue::UNDEFINED
        })
        .into_js_value()
        .unchecked_into();
        create_binding(expr, BindingTarget::Effect);
        assert_eq!(counter.get(), 1);

        write_signal(id, JsValue::from_f64(2.0));
        assert_eq!(counter.get(), 1); // never subscribed, so it never reruns
    }

    #[wasm_bindgen_test]
    fn untracked_suppresses_dependency_registration() {
        let id = create_signal(JsValue::from_f64(1.0));
        let counter = Rc::new(Cell::new(0));
        let c = counter.clone();
        let expr: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            untracked(|| read_signal(id));
            c.set(c.get() + 1);
            JsValue::UNDEFINED
        })
        .into_js_value()
        .unchecked_into();
        create_binding(expr, BindingTarget::Effect);
        assert_eq!(counter.get(), 1);

        write_signal(id, JsValue::from_f64(2.0));
        assert_eq!(counter.get(), 1);
    }

    #[wasm_bindgen_test]
    fn run_binding_skips_a_reentrant_self_trigger_instead_of_recursing_forever() {
        let id = create_signal(JsValue::from_f64(0.0));
        let counter = Rc::new(Cell::new(0));
        let c = counter.clone();
        let expr: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            c.set(c.get() + 1);
            // Reads `id` (subscribing this binding), then immediately writes
            // back to it — the shape of a `useCallback` result mistakenly
            // passed as a `useMemo`/`useEffect` dependency: calling it to
            // "read" it runs its body, which may write a signal the binding
            // also depends on. Without the reentrancy guard this recurses
            // until the Rust stack overflows.
            read_signal(id);
            write_signal(id, JsValue::from_f64(1.0));
            JsValue::UNDEFINED
        })
        .into_js_value()
        .unchecked_into();

        create_binding(expr, BindingTarget::Effect);

        // Exactly one run: the write from inside the expression re-triggers
        // the same binding, which the guard detects and skips instead of
        // recursing.
        assert_eq!(counter.get(), 1);
    }

    #[wasm_bindgen_test]
    fn memo_binding_writes_its_result_into_the_target_signal() {
        let source = create_signal(JsValue::from_f64(2.0));
        let memo_signal = create_signal(JsValue::UNDEFINED);
        let expr: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            JsValue::from_f64(read_signal(source).as_f64().unwrap() * 2.0)
        })
        .into_js_value()
        .unchecked_into();
        create_binding(expr, BindingTarget::Memo(memo_signal));
        assert_eq!(read_signal(memo_signal).as_f64(), Some(4.0));

        write_signal(source, JsValue::from_f64(5.0));
        assert_eq!(read_signal(memo_signal).as_f64(), Some(10.0));
    }

    #[wasm_bindgen_test]
    fn effect_cleanup_runs_before_each_re_execution() {
        let id = create_signal(JsValue::from_f64(0.0));
        let cleanups = Rc::new(Cell::new(0));
        let c = cleanups.clone();
        let expr: js_sys::Function = Closure::<dyn Fn() -> JsValue>::new(move || {
            read_signal(id);
            let c = c.clone();
            Closure::once_into_js(move || {
                c.set(c.get() + 1);
            })
        })
        .into_js_value()
        .unchecked_into();
        create_binding(expr, BindingTarget::Effect);
        assert_eq!(cleanups.get(), 0);

        write_signal(id, JsValue::from_f64(1.0));
        assert_eq!(cleanups.get(), 1); // cleanup returned by the initial run

        write_signal(id, JsValue::from_f64(2.0));
        assert_eq!(cleanups.get(), 2);
    }

    #[wasm_bindgen_test]
    fn context_stack_pushes_pops_and_reads_the_nearest_active_value() {
        let id = create_context_slot();
        assert_eq!(read_context(id), None);

        push_context(id, JsValue::from_str("outer"));
        assert_eq!(read_context(id).and_then(|v| v.as_string()), Some("outer".into()));

        push_context(id, JsValue::from_str("inner"));
        assert_eq!(read_context(id).and_then(|v| v.as_string()), Some("inner".into()));

        pop_context(id);
        assert_eq!(read_context(id).and_then(|v| v.as_string()), Some("outer".into()));

        pop_context(id);
        assert_eq!(read_context(id), None);
    }

    #[wasm_bindgen_test]
    fn to_display_string_covers_every_value_kind() {
        assert_eq!(to_display_string(&JsValue::NULL), "");
        assert_eq!(to_display_string(&JsValue::UNDEFINED), "");
        assert_eq!(to_display_string(&JsValue::from_str("hi")), "hi");
        assert_eq!(to_display_string(&JsValue::from_f64(3.5)), "3.5");
        assert_eq!(to_display_string(&JsValue::from_bool(true)), "true");
    }
}
