//! Bounded poison-set (spec §4.3): remembers (tool, selector) pairs that reproducibly crashed the
//! worker, so an identical later request is rejected up-front without a third/fourth respawn. Bounded
//! LRU (evicts oldest) so a stubborn agent spamming distinct payloads can't grow it without limit.

use lru::LruCache;
use std::num::NonZeroUsize;

/// Default LRU bound (spec §9.5).
pub const DEFAULT_POISON_CAPACITY: usize = 64;

pub struct PoisonSet {
    cache: LruCache<String, ()>,
}

impl PoisonSet {
    pub fn new(capacity: usize) -> Self {
        Self {
            cache: LruCache::new(NonZeroUsize::new(capacity.max(1)).unwrap()),
        }
    }

    /// The key for a tool call. `\u{1}` cannot appear in a tool name and is vanishingly unlikely in a
    /// selector, so it is a safe separator (avoids `tool="a", sel="b"` colliding with `tool="a b"`).
    pub fn key(tool: &str, selector: &str) -> String {
        format!("{tool}\u{1}{selector}")
    }

    /// Record a poison key (marks it terminal). Touches LRU recency.
    pub fn insert(&mut self, tool: &str, selector: &str) {
        self.cache.put(Self::key(tool, selector), ());
    }

    /// True if this exact (tool, selector) is known-poison. Touches recency so hot poisons stay.
    pub fn contains(&mut self, tool: &str, selector: &str) -> bool {
        self.cache.get(&Self::key(tool, selector)).is_some()
    }

    pub fn len(&self) -> usize {
        self.cache.len()
    }

    pub fn is_empty(&self) -> bool {
        self.cache.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remembers_then_short_circuits_same_selector() {
        let mut p = PoisonSet::new(64);
        assert!(!p.contains("inspect_function", "boom"));
        p.insert("inspect_function", "boom");
        assert!(p.contains("inspect_function", "boom"));
        // A different selector or tool is not poisoned.
        assert!(!p.contains("inspect_function", "safe"));
        assert!(!p.contains("attach_program", "boom"));
    }

    #[test]
    fn eviction_bounds_the_set() {
        let mut p = PoisonSet::new(2);
        p.insert("t", "a");
        p.insert("t", "b");
        p.insert("t", "c"); // evicts the least-recently-used ("a")
        assert_eq!(p.len(), 2);
        assert!(!p.contains("t", "a"));
        assert!(p.contains("t", "c"));
    }

    #[test]
    fn key_separator_avoids_collision() {
        assert_ne!(PoisonSet::key("a", "b"), PoisonSet::key("a b", ""));
    }
}
