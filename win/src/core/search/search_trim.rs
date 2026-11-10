use crate::core::detect::TextWhitespace;
use crate::core::search::SearchNormalizer;

impl SearchNormalizer {
    /// Trims display query with Dart `String.trim()` set (`B-6.5.7`), preserving case and inner whitespace.
    pub fn trimmed_for_display(s: &str) -> String {
        TextWhitespace::trim(s)
    }
}
