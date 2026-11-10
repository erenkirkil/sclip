use crate::core::detect::TextWhitespace;

const PREFIXES: &[&str] = &["https://", "http://", "ftp://", "mailto:"];

/// URL detector (`B-8.2.1`). Input is assumed to be already trimmed.
pub struct UrlDetector;

impl UrlDetector {
    pub fn detect(trimmed: &str) -> Option<String> {
        let head: String = trimmed.chars().take(8).collect();
        let lower_head = TextWhitespace::ascii_lowercased(&head);
        let matched = PREFIXES.iter().copied().find(|&p| lower_head.starts_with(p))?;
        if trimmed.chars().count() <= matched.len() {
            return None;
        }
        if trimmed.chars().any(|ch| TextWhitespace::is_collapse_set(ch as u32)) {
            return None;
        }
        Some(trimmed.to_string())
    }
}
