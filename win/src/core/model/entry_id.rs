use std::fmt;
use std::sync::atomic::{AtomicU64, Ordering};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct EntryId {
    pub raw: u64,
}

impl EntryId {
    pub const fn new(raw: u64) -> Self {
        Self { raw }
    }
}

impl fmt::Display for EntryId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "e{}", self.raw)
    }
}

#[derive(Debug)]
pub struct EntryIdGenerator {
    last: AtomicU64,
}

impl Default for EntryIdGenerator {
    fn default() -> Self {
        Self::new()
    }
}

impl EntryIdGenerator {
    pub const fn new() -> Self {
        Self {
            last: AtomicU64::new(0),
        }
    }

    pub fn next(&self) -> EntryId {
        let next = self.last.fetch_add(1, Ordering::Relaxed) + 1;
        EntryId::new(next)
    }
}
