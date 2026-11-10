use crate::core::detect::TextWhitespace;

/// Heuristic for SVG markup pasted as plain text (`B-8.3.9`).
pub struct SvgMarkupHeuristic;

impl SvgMarkupHeuristic {
    pub fn looks_like_svg(text: &str) -> bool {
        let trimmed = TextWhitespace::trim_leading(text);
        if trimmed.is_empty() {
            return false;
        }
        let head_units: Vec<u16> = trimmed.encode_utf16().take(512).collect();
        let head_decoded: String = char::decode_utf16(head_units)
            .map(|r| r.unwrap_or('\u{FFFD}'))
            .collect();
        let head = head_decoded.to_lowercase();
        let has_svg_root =
            head.starts_with("<svg") || (head.starts_with("<?xml") && head.contains("<svg"));
        if !has_svg_root {
            return false;
        }
        trimmed.to_lowercase().contains("</svg>")
    }
}
