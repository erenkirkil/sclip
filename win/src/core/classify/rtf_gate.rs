use crate::core::model::{CanonicalFormat, RawItem};

/// RTF gate (`B-8.3.1`): when both plain text and RTF formats are present (even if empty),
/// skip binary probes on the first pass.
pub struct RtfGate;

impl RtfGate {
    pub fn is_open(item: &RawItem) -> bool {
        item.formats.contains_key(&CanonicalFormat::PlainText)
            && item.formats.contains_key(&CanonicalFormat::Rtf)
    }
}
