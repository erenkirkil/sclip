use crate::core::model::{EntryKind, ImageItem};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Payload {
    Text(String),
    Url {
        original: String,
        uri: String,
        display: String,
    },
    Color {
        original: String,
        normalized: String,
        argb: u32,
    },
    Image(ImageItem),
    ImageSet(Vec<ImageItem>),
    Svg(String),
    Files(Vec<String>),
    Pdf(Vec<u8>),
    RichText {
        plain: String,
        html: String,
        rtf: Option<Vec<u8>>,
    },
}

impl Payload {
    pub fn kind(&self) -> EntryKind {
        match self {
            Self::Text(_) => EntryKind::Text,
            Self::Url { .. } => EntryKind::Url,
            Self::Color { .. } => EntryKind::Color,
            Self::Image(_) => EntryKind::Image,
            Self::ImageSet(_) => EntryKind::ImageSet,
            Self::Svg(_) => EntryKind::Svg,
            Self::Files(_) => EntryKind::Files,
            Self::Pdf(_) => EntryKind::Pdf,
            Self::RichText { .. } => EntryKind::RichText,
        }
    }
}
