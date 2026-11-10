#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EntryKind {
    Text,
    Url,
    Color,
    Image,
    ImageSet,
    Svg,
    Files,
    Pdf,
    RichText,
}

impl EntryKind {
    pub const ALL: &'static [EntryKind] = &[
        Self::Text,
        Self::Url,
        Self::Color,
        Self::Image,
        Self::ImageSet,
        Self::Svg,
        Self::Files,
        Self::Pdf,
        Self::RichText,
    ];

    pub fn raw_value(self) -> &'static str {
        match self {
            Self::Text => "text",
            Self::Url => "url",
            Self::Color => "color",
            Self::Image => "image",
            Self::ImageSet => "imageSet",
            Self::Svg => "svg",
            Self::Files => "files",
            Self::Pdf => "pdf",
            Self::RichText => "richText",
        }
    }

    pub fn from_raw(raw: &str) -> Option<Self> {
        match raw {
            "text" => Some(Self::Text),
            "url" => Some(Self::Url),
            "color" => Some(Self::Color),
            "image" => Some(Self::Image),
            "imageSet" => Some(Self::ImageSet),
            "svg" => Some(Self::Svg),
            "files" => Some(Self::Files),
            "pdf" => Some(Self::Pdf),
            "richText" => Some(Self::RichText),
            _ => None,
        }
    }
}
