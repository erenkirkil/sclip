use crate::core::detect::TextWhitespace;
use crate::core::model::{Entry, FileName, Payload};
use crate::core::text::{StringKey, Strings};

impl Entry {
    /// Row preview string (`behavior.md` `B-6.4.3`).
    pub fn preview(&self, strings: &Strings) -> String {
        match &self.payload {
            Payload::Text(s) => PreviewText::cut(s),
            Payload::RichText { plain, .. } => PreviewText::cut(plain),
            Payload::Url { display, .. } => PreviewText::cut(display),
            Payload::Color { normalized, .. } => normalized.clone(),
            Payload::Image(item) => {
                let fmt = item.format.raw_value().to_ascii_uppercase();
                let size = SizeFormat::format(item.data.len(), strings);
                strings.format(StringKey::PreviewImage, &[("format", &fmt), ("size", &size)])
            }
            Payload::ImageSet(items) => {
                let total: usize = items.iter().map(|i| i.data.len()).sum();
                let n = items.len().to_string();
                let size = SizeFormat::format(total, strings);
                strings.format(StringKey::PreviewImageSet, &[("n", &n), ("size", &size)])
            }
            Payload::Svg(xml) => {
                let n = xml.encode_utf16().count().to_string();
                strings.format(StringKey::PreviewSvg, &[("n", &n)])
            }
            Payload::Pdf(data) => {
                let size = SizeFormat::format(data.len(), strings);
                strings.format(StringKey::PreviewPdf, &[("size", &size)])
            }
            Payload::Files(urls) => PreviewText::files(urls, strings),
        }
    }
}

/// Text preview (`B-6.4.5`, `E24`): collapse whitespace, trim, cap at 120 Unicode code points + ellipsis.
pub struct PreviewText;

impl PreviewText {
    pub const MAX_CODE_POINTS: usize = 120;

    pub fn cut(s: &str) -> String {
        let cleaned = TextWhitespace::trim(&TextWhitespace::collapse(s));
        let mut out = String::new();
        for (idx, ch) in cleaned.chars().enumerate() {
            if idx == Self::MAX_CODE_POINTS {
                out.push('\u{2026}');
                return out;
            }
            out.push(ch);
        }
        cleaned
    }

    pub fn files(urls: &[String], strings: &Strings) -> String {
        match urls.len() {
            0 => strings.get(StringKey::PreviewFilesNone).to_string(),
            1 => FileName::basename(&urls[0]),
            n => {
                let names: String = urls
                    .iter()
                    .take(3)
                    .map(|u| FileName::basename(u))
                    .collect::<Vec<_>>()
                    .join(", ");
                let n_str = n.to_string();
                let mut text = strings.format(
                    StringKey::PreviewFilesMulti,
                    &[("n", &n_str), ("names", &names)],
                );
                if n > 3 {
                    let k_str = (n - 3).to_string();
                    text.push_str(&strings.format(StringKey::PreviewFilesMore, &[("k", &k_str)]));
                }
                text
            }
        }
    }
}

/// Byte size formatter (`B-6.4.4`).
pub struct SizeFormat;

impl SizeFormat {
    pub const MEBIBYTE: usize = 1_048_576;

    pub fn format(bytes: usize, strings: &Strings) -> String {
        if bytes < Self::MEBIBYTE {
            let kb = (bytes / 1024).to_string();
            return strings.format(StringKey::SizeKilobytes, &[("n", &kb)]);
        }
        let tenths = (bytes * 10 + Self::MEBIBYTE / 2) / Self::MEBIBYTE;
        let mb = format!("{}.{}", tenths / 10, tenths % 10);
        strings.format(StringKey::SizeMegabytes, &[("n", &mb)])
    }
}
