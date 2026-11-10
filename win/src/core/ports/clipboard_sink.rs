use std::fmt;

use crate::core::model::Entry;

/// Receipt of a clipboard write-back (`B-8.8.8`, `E30`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WriteReceipt {
    pub change: i64,
    pub signature: String,
}

impl WriteReceipt {
    pub fn new(change: i64, signature: impl Into<String>) -> Self {
        Self {
            change,
            signature: signature.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipboardWriteError(pub String);

impl fmt::Display for ClipboardWriteError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ClipboardWriteError {}

/// Platform clipboard write port.
pub trait ClipboardSink {
    fn write(
        &self,
        entry: &Entry,
        plain_only: bool,
        image_index: Option<usize>,
    ) -> Result<WriteReceipt, ClipboardWriteError>;
}
