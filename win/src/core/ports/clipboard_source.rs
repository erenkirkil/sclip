use crate::core::model::{EntryId, RawClip};

/// Cheap clipboard poll state (`B-8.8.1`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ClipboardState {
    pub change: i64,
    pub sensitive: bool,
    pub has_files: bool,
}

impl ClipboardState {
    pub const fn new(change: i64, sensitive: bool, has_files: bool) -> Self {
        Self {
            change,
            sensitive,
            has_files,
        }
    }
}

/// Platform clipboard reading port.
pub trait ClipboardSource {
    fn current_state(&self) -> ClipboardState;
    fn read_files(&self, destination: Option<EntryId>) -> Vec<String>;
    fn read_clip(&self) -> RawClip;
}
