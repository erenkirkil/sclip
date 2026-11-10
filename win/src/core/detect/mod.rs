pub mod color_parser;
pub mod contact_detector;
pub mod svg_markup_heuristic;
pub mod text_detection;
pub mod text_whitespace;
pub mod url_detector;

pub use color_parser::{ColorParser, ParsedColor};
pub use contact_detector::ContactDetector;
pub use svg_markup_heuristic::SvgMarkupHeuristic;
pub use text_detection::TextDetection;
pub use text_whitespace::TextWhitespace;
pub use url_detector::UrlDetector;
