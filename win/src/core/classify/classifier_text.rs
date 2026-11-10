use crate::core::classify::{Classification, DropReason, ItemChain};
use crate::core::detect::{TextDetection, TextWhitespace};
use crate::core::model::{CanonicalFormat, Payload};
use crate::core::security::SvgSanitizer;

impl<'a> ItemChain<'a> {
    /// Text legs (`B-8.3.3`..`B-8.3.5`): non-empty plain text, otherwise HTML only.
    pub fn text_legs(&mut self, plain: Option<&str>) -> Classification {
        let Some(plain) = plain.filter(|s| !s.is_empty()) else {
            return self.html_only();
        };
        if plain.encode_utf16().count() > self.caps.text_chars {
            return Classification::Drop(DropReason::TextTooLarge);
        }
        Classification::Payload(self.plain_text(plain))
    }

    fn plain_text(&self, raw: &str) -> Payload {
        let trimmed = TextWhitespace::trim(raw);
        match TextDetection::detect(raw) {
            TextDetection::Url { uri }
            | TextDetection::Email { uri }
            | TextDetection::Phone { uri } => {
                return Payload::Url {
                    original: trimmed.clone(),
                    uri,
                    display: trimmed,
                };
            }
            TextDetection::Color(color) => {
                return Payload::Color {
                    original: trimmed,
                    normalized: color.normalized,
                    argb: color.argb,
                };
            }
            TextDetection::Svg => {
                if SvgSanitizer::is_safe(raw.as_bytes(), &self.caps) {
                    return Payload::Svg(raw.to_string());
                }
            }
            TextDetection::None => {}
        }
        if let Some(html) = self.html() {
            if html != raw && html.encode_utf16().count() <= self.caps.text_chars {
                return Payload::RichText {
                    plain: raw.to_string(),
                    html,
                    rtf: self.rtf_companion(),
                };
            }
        }
        Payload::Text(raw.to_string())
    }

    fn html_only(&self) -> Classification {
        let Some(html) = self.html() else {
            return Classification::None;
        };
        if html.encode_utf16().count() > self.caps.text_chars {
            return Classification::Drop(DropReason::TextTooLarge);
        }
        let plain = HtmlStrip::plain_text(&html);
        if plain.is_empty() {
            return Classification::None;
        }
        Classification::Payload(Payload::RichText {
            plain,
            html,
            rtf: self.rtf_companion(),
        })
    }

    fn html(&self) -> Option<String> {
        let data = self.item.formats.get(&CanonicalFormat::Html)?;
        if data.is_empty() {
            return None;
        }
        Some(TextDecoding::utf8(data))
    }

    fn rtf_companion(&self) -> Option<Vec<u8>> {
        let rtf = self.item.formats.get(&CanonicalFormat::Rtf)?;
        if rtf.is_empty() || rtf.len() > self.caps.rtf_bytes {
            return None;
        }
        Some(rtf.clone())
    }
}

/// Lossy UTF-8 decoding with `U+FFFD` replacement (`spec/vectors/README.md`).
pub struct TextDecoding;

impl TextDecoding {
    pub fn utf8(data: &[u8]) -> String {
        String::from_utf8_lossy(data).into_owned()
    }
}

/// `<[^>]*>` tag stripping + `B-6.4.5` whitespace collapse and trim.
pub struct HtmlStrip;

impl HtmlStrip {
    pub fn plain_text(html: &str) -> String {
        let scalars: Vec<char> = html.chars().collect();
        let mut out = String::with_capacity(html.len());
        let mut i = 0;
        while i < scalars.len() {
            if scalars[i] == '<' {
                let Some(rel_close) = scalars[i + 1..].iter().position(|&c| c == '>') else {
                    for &c in &scalars[i..] {
                        out.push(c);
                    }
                    break;
                };
                i = i + 1 + rel_close + 1;
                continue;
            }
            out.push(scalars[i]);
            i += 1;
        }
        TextWhitespace::trim(&TextWhitespace::collapse(&out))
    }
}
