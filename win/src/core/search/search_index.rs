use std::collections::HashSet;

use crate::core::model::{Entry, FileName, Payload};
use crate::core::search::SearchNormalizer;

/// Search index (`behavior.md` `B-6.5.5`). `dosya`, `resim`, `pdf`, `svg` are contract constants.
pub struct SearchIndex;

impl SearchIndex {
    pub const MAX_UNITS: usize = 8192;

    pub fn text(entry: &Entry) -> String {
        let src = Self::source(&entry.payload);
        let cut_src = Self::cut(&src);
        SearchNormalizer::normalize(&cut_src)
    }

    pub fn source(payload: &Payload) -> String {
        match payload {
            Payload::Text(s) => s.clone(),
            Payload::RichText { plain, .. } => plain.clone(),
            Payload::Color { original, .. } => original.clone(),
            Payload::Url { uri, display, .. } => {
                if display.chars().eq(uri.chars()) {
                    display.clone()
                } else {
                    format!("{} {}", display, uri)
                }
            }
            Payload::Files(urls) => {
                let mut parts = Vec::with_capacity(urls.len() + 1);
                parts.push("dosya".to_string());
                for u in urls {
                    parts.push(FileName::basename(u));
                }
                parts.join(" ")
            }
            Payload::Image(item) => format!("resim {}", item.format.raw_value()),
            Payload::ImageSet(items) => {
                let mut seen = HashSet::new();
                let mut parts = Vec::with_capacity(items.len() + 1);
                parts.push("resim");
                for item in items {
                    if seen.insert(item.format) {
                        parts.push(item.format.raw_value());
                    }
                }
                parts.join(" ")
            }
            Payload::Pdf(_) => "pdf".to_string(),
            Payload::Svg(_) => "svg".to_string(),
        }
    }

    /// First 8192 UTF-16 code units; drops trailing dangling high surrogate (`L7`).
    pub fn cut(s: &str) -> String {
        let units: Vec<u16> = s.encode_utf16().collect();
        if units.len() <= Self::MAX_UNITS {
            return s.to_string();
        }
        let mut end = Self::MAX_UNITS;
        let last = end - 1;
        if (0xD800..=0xDBFF).contains(&units[last]) {
            end = last;
        }
        String::from_utf16(&units[..end]).unwrap_or_else(|_| s.to_string())
    }
}
