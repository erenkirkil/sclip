use crate::core::model::Payload;
use crate::core::security::SizeCaps;

/// Heavy budget weights (`B-8.6.6`, `B-8.6.7`).
pub struct MemoryBudget;

impl MemoryBudget {
    /// Weight of `payload` in the memory budget. Text weight is in UTF-16 code units; RTF is bytes.
    pub fn weight(payload: &Payload, caps: &SizeCaps) -> usize {
        match payload {
            Payload::Image(item) => item.data.len(),
            Payload::ImageSet(items) => items.iter().map(|i| i.data.len()).sum(),
            Payload::Pdf(data) => data.len(),
            Payload::Svg(markup) => Self::string_weight(markup.encode_utf16().count(), caps),
            Payload::Text(text) => Self::string_weight(text.encode_utf16().count(), caps),
            Payload::RichText { plain, html, rtf } => {
                let len = plain.encode_utf16().count()
                    + html.encode_utf16().count()
                    + rtf.as_ref().map(|d| d.len()).unwrap_or(0);
                Self::string_weight(len, caps)
            }
            Payload::Url { .. } | Payload::Color { .. } | Payload::Files(_) => 0,
        }
    }

    fn string_weight(length: usize, caps: &SizeCaps) -> usize {
        if length < caps.weight_floor_chars {
            0
        } else {
            length
        }
    }
}
