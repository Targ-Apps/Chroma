//! Signal ↔ binding dependency graph.
//!
//! It knows nothing about values or the DOM: only ids and subscriptions. This
//! makes it natively testable, without a browser or wasm.

pub type SignalId = usize;
pub type BindingId = usize;

/// Sentinel binding for untracked scopes: it does not exist in `dependencies`,
/// so every read made under it is discarded without subscribing.
pub const UNTRACKED: BindingId = BindingId::MAX;

#[derive(Default)]
pub struct DepGraph {
    /// Per signal: subscribed bindings.
    subscribers: Vec<Vec<BindingId>>,
    /// Per binding: signals it read during its last evaluation.
    dependencies: Vec<Vec<SignalId>>,
    /// Stack of bindings under evaluation (the top one registers reads).
    tracking: Vec<BindingId>,
}

impl DepGraph {
    pub fn add_signal(&mut self) -> SignalId {
        self.subscribers.push(Vec::new());
        self.subscribers.len() - 1
    }

    pub fn add_binding(&mut self) -> BindingId {
        self.dependencies.push(Vec::new());
        self.dependencies.len() - 1
    }

    /// Registers a signal read by the binding under evaluation, if any.
    pub fn track_read(&mut self, signal: SignalId) {
        let Some(&binding) = self.tracking.last() else {
            return;
        };
        let Some(deps) = self.dependencies.get_mut(binding) else {
            return;
        };
        // Consecutive duplicate reads are common; skip the linear scan.
        if deps.last() == Some(&signal) {
            return;
        }
        if !deps.contains(&signal) {
            deps.push(signal);
            if let Some(subs) = self.subscribers.get_mut(signal) {
                subs.push(binding);
            }
        }
    }

    /// Opens a binding's tracking scope, discarding its dependencies from the
    /// previous evaluation (they may have changed).
    pub fn begin_tracking(&mut self, binding: BindingId) {
        if let Some(deps) = self.dependencies.get_mut(binding) {
            for signal in std::mem::take(deps) {
                if let Some(subs) = self.subscribers.get_mut(signal) {
                    subs.retain(|&b| b != binding);
                }
            }
        }
        self.tracking.push(binding);
    }

    pub fn end_tracking(&mut self) {
        self.tracking.pop();
    }

    /// Whether `binding` is anywhere on the tracking stack right now, i.e.
    /// its expression is currently mid-evaluation (possibly nested inside
    /// another binding's evaluation via a reentrant signal write).
    pub fn is_evaluating(&self, binding: BindingId) -> bool {
        self.tracking.contains(&binding)
    }

    /// Snapshot of bindings to notify after a signal write (cloned so notification
    /// can run bindings without holding the runtime borrow).
    pub(crate) fn subscriber_snapshot(&self, signal: SignalId) -> Vec<BindingId> {
        self.subscribers.get(signal).cloned().unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn subscribers_snapshot(g: &DepGraph, signal: SignalId) -> Vec<BindingId> {
        g.subscriber_snapshot(signal)
    }

    #[test]
    fn add_signal_should_return_incrementing_ids() {
        let mut g = DepGraph::default();
        assert_eq!((g.add_signal(), g.add_signal()), (0, 1));
    }

    #[test]
    fn track_read_outside_tracking_scope_should_not_subscribe() {
        let mut g = DepGraph::default();
        let s = g.add_signal();
        g.track_read(s);
        assert!(subscribers_snapshot(&g, s).is_empty());
    }

    #[test]
    fn track_read_inside_tracking_scope_should_subscribe_binding() {
        let mut g = DepGraph::default();
        let s = g.add_signal();
        let b = g.add_binding();
        g.begin_tracking(b);
        g.track_read(s);
        g.end_tracking();
        assert_eq!(subscribers_snapshot(&g, s), vec![b]);
    }

    #[test]
    fn track_read_twice_should_subscribe_once() {
        let mut g = DepGraph::default();
        let s = g.add_signal();
        let b = g.add_binding();
        g.begin_tracking(b);
        g.track_read(s);
        g.track_read(s);
        g.end_tracking();
        assert_eq!(subscribers_snapshot(&g, s), vec![b]);
    }

    #[test]
    fn begin_tracking_should_clear_previous_dependencies() {
        let mut g = DepGraph::default();
        let s1 = g.add_signal();
        let s2 = g.add_signal();
        let b = g.add_binding();

        // First evaluation: reads s1.
        g.begin_tracking(b);
        g.track_read(s1);
        g.end_tracking();

        // Second evaluation: now it only reads s2.
        g.begin_tracking(b);
        g.track_read(s2);
        g.end_tracking();

        assert!(subscribers_snapshot(&g, s1).is_empty());
        assert_eq!(subscribers_snapshot(&g, s2), vec![b]);
    }

    #[test]
    fn untracked_scope_should_suppress_subscription() {
        let mut g = DepGraph::default();
        let s = g.add_signal();
        let b = g.add_binding();

        g.begin_tracking(b);
        g.begin_tracking(UNTRACKED);
        g.track_read(s);
        g.end_tracking();
        g.end_tracking();

        assert!(subscribers_snapshot(&g, s).is_empty());
    }

    #[test]
    fn nested_tracking_should_attribute_reads_to_innermost_binding() {
        let mut g = DepGraph::default();
        let s = g.add_signal();
        let outer = g.add_binding();
        let inner = g.add_binding();

        g.begin_tracking(outer);
        g.begin_tracking(inner);
        g.track_read(s);
        g.end_tracking();
        g.end_tracking();

        assert_eq!(subscribers_snapshot(&g, s), vec![inner]);
    }

    #[test]
    fn is_evaluating_is_true_only_while_a_binding_is_on_the_tracking_stack() {
        let mut g = DepGraph::default();
        let b = g.add_binding();

        assert!(!g.is_evaluating(b));
        g.begin_tracking(b);
        assert!(g.is_evaluating(b));
        g.end_tracking();
        assert!(!g.is_evaluating(b));
    }

    #[test]
    fn is_evaluating_detects_reentrant_nesting_of_the_same_binding() {
        let mut g = DepGraph::default();
        let b = g.add_binding();

        g.begin_tracking(b);
        // A reentrant call for the exact same binding (e.g. its own
        // evaluation wrote a signal it also reads) must be detectable
        // before a second `begin_tracking(b)` is even attempted.
        assert!(g.is_evaluating(b));
        g.end_tracking();
    }

    #[test]
    fn multiple_bindings_should_all_subscribe_to_shared_signal() {
        let mut g = DepGraph::default();
        let s = g.add_signal();
        let b1 = g.add_binding();
        let b2 = g.add_binding();

        g.begin_tracking(b1);
        g.track_read(s);
        g.end_tracking();
        g.begin_tracking(b2);
        g.track_read(s);
        g.end_tracking();

        assert_eq!(subscribers_snapshot(&g, s), vec![b1, b2]);
    }
}
