use crate::core::detect::{
    ColorParser, ContactDetector, ParsedColor, SvgMarkupHeuristic, TextWhitespace, UrlDetector,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TextDetection {
    Url { uri: String },
    Color(ParsedColor),
    Email { uri: String },
    Phone { uri: String },
    Svg,
    None,
}

impl TextDetection {
    /// Trims raw text with Dart `trim()` set; order is url -> color -> email -> phone -> svg (`B-8.2`).
    pub fn detect(raw: &str) -> TextDetection {
        let trimmed = TextWhitespace::trim(raw);
        if trimmed.is_empty() {
            return TextDetection::None;
        }
        if let Some(uri) = UrlDetector::detect(&trimmed) {
            return TextDetection::Url { uri };
        }
        if let Some(color) = ColorParser::parse(&trimmed) {
            return TextDetection::Color(color);
        }
        if let Some(uri) = ContactDetector::mailto(&trimmed) {
            return TextDetection::Email { uri };
        }
        if let Some(uri) = ContactDetector::tel(&trimmed) {
            return TextDetection::Phone { uri };
        }
        if SvgMarkupHeuristic::looks_like_svg(&trimmed) {
            return TextDetection::Svg;
        }
        TextDetection::None
    }
}
