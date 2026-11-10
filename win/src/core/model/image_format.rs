#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ImageFormat {
    Png,
    Jpeg,
    Gif,
    Webp,
}

impl ImageFormat {
    pub const ALL: &'static [ImageFormat] = &[
        Self::Png,
        Self::Jpeg,
        Self::Gif,
        Self::Webp,
    ];

    pub fn raw_value(self) -> &'static str {
        match self {
            Self::Png => "png",
            Self::Jpeg => "jpeg",
            Self::Gif => "gif",
            Self::Webp => "webp",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImageItem {
    pub data: Vec<u8>,
    pub format: ImageFormat,
}

impl ImageItem {
    pub fn new(data: Vec<u8>, format: ImageFormat) -> Self {
        Self { data, format }
    }
}
