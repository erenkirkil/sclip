#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum CanonicalFormat {
    PlainText,
    Html,
    Rtf,
    Png,
    Jpeg,
    Gif,
    Webp,
    Svg,
    Pdf,
}

impl CanonicalFormat {
    pub const ALL: &'static [CanonicalFormat] = &[
        Self::PlainText,
        Self::Html,
        Self::Rtf,
        Self::Png,
        Self::Jpeg,
        Self::Gif,
        Self::Webp,
        Self::Svg,
        Self::Pdf,
    ];

    pub fn raw_value(self) -> &'static str {
        match self {
            Self::PlainText => "text/plain",
            Self::Html => "text/html",
            Self::Rtf => "text/rtf",
            Self::Png => "image/png",
            Self::Jpeg => "image/jpeg",
            Self::Gif => "image/gif",
            Self::Webp => "image/webp",
            Self::Svg => "image/svg+xml",
            Self::Pdf => "application/pdf",
        }
    }

    pub fn from_raw(raw: &str) -> Option<Self> {
        match raw {
            "text/plain" => Some(Self::PlainText),
            "text/html" => Some(Self::Html),
            "text/rtf" => Some(Self::Rtf),
            "image/png" => Some(Self::Png),
            "image/jpeg" => Some(Self::Jpeg),
            "image/gif" => Some(Self::Gif),
            "image/webp" => Some(Self::Webp),
            "image/svg+xml" => Some(Self::Svg),
            "application/pdf" => Some(Self::Pdf),
            _ => None,
        }
    }
}
