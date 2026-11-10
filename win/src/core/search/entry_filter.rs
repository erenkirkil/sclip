use crate::core::model::Entry;
use crate::core::search::{SearchIndex, SearchNormalizer};

/// Derived search filter (`behavior.md` `B-6.5.4`, `B-6.5.6`). Never mutates the store.
pub struct EntryFilter;

impl EntryFilter {
    pub fn filter(entries: &[Entry], query: &str) -> Vec<Entry> {
        let needle = SearchNormalizer::normalize(query);
        if needle.is_empty() {
            return entries.to_vec();
        }
        entries
            .iter()
            .filter(|entry| SearchIndex::text(entry).contains(&needle))
            .cloned()
            .collect()
    }
}
