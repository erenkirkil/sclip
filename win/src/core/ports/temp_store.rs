use std::fmt;

use crate::core::model::Entry;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TempStoreError(pub String);

impl fmt::Display for TempStoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for TempStoreError {}

/// Temp materialization port (`B-8.4`). Never called for `is_sensitive` entries (`B-8.4.4`).
pub trait TempStore {
    fn materialize(&self, entry: &Entry) -> Result<Vec<String>, TempStoreError>;
    fn delete(&self, entry: &Entry);
    fn prune_all(&self);
}
