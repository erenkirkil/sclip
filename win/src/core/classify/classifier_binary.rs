use crate::core::model::{CanonicalFormat, ImageFormat, ImageItem, RawItem};

const ORDER: &[(CanonicalFormat, ImageFormat)] = &[
    (CanonicalFormat::Png, ImageFormat::Png),
    (CanonicalFormat::Jpeg, ImageFormat::Jpeg),
    (CanonicalFormat::Gif, ImageFormat::Gif),
    (CanonicalFormat::Webp, ImageFormat::Webp),
];

const PNG_SIG: &[u8] = &[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const JPEG_SIG: &[u8] = &[0xFF, 0xD8, 0xFF];
const GIF87A: &[u8] = b"GIF87a";
const GIF89A: &[u8] = b"GIF89a";
const RIFF: &[u8] = b"RIFF";
const WEBP: &[u8] = b"WEBP";

/// Image binary probes (`B-8.3.2`, `S8.3`): order is png -> jpeg -> gif -> webp; verifies magic bytes.
pub struct BinaryProbe;

impl BinaryProbe {
    pub fn images(item: &RawItem) -> Vec<ImageItem> {
        let mut out = Vec::new();
        for &(canonical, format) in ORDER {
            if let Some(data) = item.formats.get(&canonical) {
                if Self::matches(data, format) {
                    out.push(ImageItem::new(data.clone(), format));
                }
            }
        }
        out
    }

    pub fn matches(data: &[u8], format: ImageFormat) -> bool {
        match format {
            ImageFormat::Png => data.starts_with(PNG_SIG),
            ImageFormat::Jpeg => data.starts_with(JPEG_SIG),
            ImageFormat::Gif => data.starts_with(GIF87A) || data.starts_with(GIF89A),
            ImageFormat::Webp => {
                data.len() >= 12 && data.starts_with(RIFF) && data[8..].starts_with(WEBP)
            }
        }
    }
}
