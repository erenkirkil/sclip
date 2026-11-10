use crate::core::hash::Sha256;
use crate::core::model::{ImageItem, Payload};

const HEX_LOWER: &[u8; 16] = b"0123456789abcdef";

/// Content hash calculator (`B-8.1.5`..`B-8.1.7`). Hex is always lowercase first 16 chars (8 bytes).
pub struct ContentHash;

impl ContentHash {
    pub fn text(prefix: &str, value: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(prefix.as_bytes());
        hasher.update(b":");
        hasher.update(value.as_bytes());
        let digest = hasher.finalize();
        format!("{}:{}", prefix, hex16(&digest))
    }

    pub fn bytes(prefix: &str, data: &[u8]) -> String {
        let digest = Sha256::digest(data);
        format!("{}:{}:{}", prefix, data.len(), hex16(&digest))
    }

    pub fn image_set(items: &[ImageItem]) -> String {
        let parts: Vec<String> = items
            .iter()
            .map(|item| {
                let d = Sha256::digest(&item.data);
                format!("{}:{}", item.data.len(), hex16(&d))
            })
            .collect();
        let joined = parts.join("|");
        let digest = Sha256::digest(joined.as_bytes());
        format!("is:{}:{}", items.len(), hex16(&digest))
    }

    pub fn of(payload: &Payload) -> String {
        match payload {
            Payload::Text(s) => Self::text("t", s),
            Payload::Url { original, .. } => Self::text("u", original),
            Payload::Color { normalized, .. } => Self::text("c", normalized),
            Payload::Svg(xml) => Self::text("s", xml),
            Payload::RichText { plain, html, .. } => {
                let mut combined = String::with_capacity(plain.len() + 1 + html.len());
                combined.push_str(plain);
                combined.push('\0');
                combined.push_str(html);
                Self::text("r", &combined)
            }
            Payload::Files(urls) => Self::text("f", &urls.join("|")),
            Payload::Image(item) => Self::bytes("i", &item.data),
            Payload::Pdf(data) => Self::bytes("p", data),
            Payload::ImageSet(items) => Self::image_set(items),
        }
    }
}

fn hex16(digest: &[u8; 32]) -> String {
    let mut out = String::with_capacity(16);
    for &b in &digest[..8] {
        out.push(HEX_LOWER[(b >> 4) as usize] as char);
        out.push(HEX_LOWER[(b & 0x0f) as usize] as char);
    }
    out
}
