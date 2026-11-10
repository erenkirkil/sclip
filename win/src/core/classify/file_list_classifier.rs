use crate::core::model::{FileName, ImageFormat, ImageItem, Payload};
use crate::core::ports::FileReading;
use crate::core::security::SizeCaps;

/// File list classifier (`B-8.3.8`, `B-8.6.5`).
pub struct FileListClassifier<'a> {
    pub caps: SizeCaps,
    pub files: &'a dyn FileReading,
}

impl<'a> FileListClassifier<'a> {
    pub fn new(caps: SizeCaps, files: &'a dyn FileReading) -> Self {
        Self { caps, files }
    }

    pub fn classify(&self, urls: &[String]) -> Payload {
        let Some( mut images) = self.read_images(urls) else {
            return Payload::Files(urls.to_vec());
        };
        if images.len() == 1 {
            Payload::Image(images.remove(0))
        } else {
            Payload::ImageSet(images)
        }
    }

    fn read_images(&self, urls: &[String]) -> Option<Vec<ImageItem>> {
        let limit = self.caps.file_image_bytes;
        let mut formats = Vec::with_capacity(urls.len());
        let mut total: usize = 0;
        for url in urls {
            let format = Self::image_format(url)?;
            let size = self.files.size(url)?;
            if size < 1 || size > limit {
                return None;
            }
            total = total.checked_add(size)?;
            if total > limit {
                return None;
            }
            formats.push(format);
        }

        let mut items = Vec::with_capacity(urls.len());
        let mut read_total: usize = 0;
        let read_cap = limit.saturating_add(1);
        for (url, format) in urls.iter().zip(formats.into_iter()) {
            let data = self.files.read_up_to(url, read_cap).ok()?;
            if data.is_empty() || data.len() > limit {
                return None;
            }
            read_total = read_total.checked_add(data.len())?;
            if read_total > limit {
                return None;
            }
            items.push(ImageItem::new(data, format));
        }
        if items.is_empty() {
            None
        } else {
            Some(items)
        }
    }

    pub fn image_format(url: &str) -> Option<ImageFormat> {
        let name = FileName::basename(url);
        let dot = name.rfind('.')?;
        if dot == 0 {
            return None;
        }
        let ext = name[dot + 1..].to_ascii_lowercase();
        match ext.as_str() {
            "png" => Some(ImageFormat::Png),
            "jpg" | "jpeg" => Some(ImageFormat::Jpeg),
            "gif" => Some(ImageFormat::Gif),
            "webp" => Some(ImageFormat::Webp),
            _ => None,
        }
    }
}
