use std::fmt;

use crate::core::model::Entry;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TempStoreError {
    SensitiveEntry,
    UnsupportedPayload,
    Io(String),
}

impl fmt::Display for TempStoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::SensitiveEntry => f.write_str("sensitive entry cannot be materialized"),
            Self::UnsupportedPayload => f.write_str("unsupported payload for temp store"),
            Self::Io(msg) => f.write_str(msg),
        }
    }
}

impl std::error::Error for TempStoreError {}

/// Temp materialization port (`B-8.4`). Never called for `is_sensitive` entries (`B-8.4.4`).
pub trait TempStore {
    fn materialize(&self, entry: &Entry) -> Result<Vec<String>, TempStoreError>;
    fn delete(&self, entry: &Entry);
    fn prune_all(&self);
}
