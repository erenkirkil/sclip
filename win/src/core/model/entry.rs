use crate::core::hash::ContentHash;
use crate::core::model::{EntryId, Payload};

/// Entry in history (`B-8.1.4`). `content_hash` is computed at creation and preserved across `touched`.
#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub id: EntryId,
    pub created_at: f64,
    pub payload: Payload,
    pub is_sensitive: bool,
    pub content_hash: String,
}

impl Eq for Entry {}

impl Entry {
    pub fn new(id: EntryId, created_at: f64, payload: Payload, is_sensitive: bool) -> Self {
        let content_hash = ContentHash::of(&payload);
        Self {
            id,
            created_at,
            payload,
            is_sensitive,
            content_hash,
        }
    }

    pub fn touched(&self, at: f64) -> Self {
        let mut copy = self.clone();
        copy.created_at = at;
        copy
    }
}
