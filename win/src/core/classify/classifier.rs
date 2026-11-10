use std::rc::Rc;

use crate::core::classify::{BinaryProbe, FileListClassifier, RtfGate, TextDecoding};
use crate::core::detect::TextWhitespace;
use crate::core::model::{CanonicalFormat, EntryKind, ImageItem, Payload, RawClip, RawItem};
use crate::core::ports::{DiskFileReading, FileReading};
use crate::core::security::{SizeCaps, SvgSanitizer};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DropReason {
    TextTooLarge,
    OverCap(EntryKind),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Classification {
    Payload(Payload),
    Drop(DropReason),
    None,
}

/// Clipboard snapshot classifier (`behavior.md` `B-8.3`, `B-8.6`).
#[derive(Clone)]
pub struct Classifier {
    pub caps: SizeCaps,
    files: Rc<dyn FileReading>,
}

impl Default for Classifier {
    fn default() -> Self {
        Self::new()
    }
}

impl Classifier {
    pub fn new() -> Self {
        Self {
            caps: SizeCaps::DEFAULT,
            files: Rc::new(DiskFileReading::new()),
        }
    }

    pub fn with_caps(caps: SizeCaps) -> Self {
        Self {
            caps,
            files: Rc::new(DiskFileReading::new()),
        }
    }

    pub fn with_caps_and_files(caps: SizeCaps, files: Rc<dyn FileReading>) -> Self {
        Self { caps, files }
    }

    pub fn classify(&self, clip: &RawClip) -> Classification {
        if !clip.files.is_empty() {
            return Classification::Payload(
                FileListClassifier::new(self.caps, self.files.as_ref()).classify(&clip.files),
            );
        }
        match clip.items.len() {
            0 => Classification::None,
            1 => self.classify_item(&clip.items[0]),
            _ => self.classify_many(&clip.items),
        }
    }

    pub fn classify_item(&self, item: &RawItem) -> Classification {
        let mut chain = ItemChain::new(self.caps, item);
        chain.run()
    }

    fn classify_many(&self, items: &[RawItem]) -> Classification {
        if let Some(images) = self.all_images(items) {
            if let Some(group) = self.image_group(images) {
                return Classification::Payload(group);
            }
        }
        let mut best: Option<Payload> = None;
        let mut first_drop: Option<DropReason> = None;
        for item in items {
            match self.classify_item(item) {
                Classification::Payload(p) => {
                    let replace = best
                        .as_ref()
                        .map(|b| Self::rank(&p) > Self::rank(b))
                        .unwrap_or(true);
                    if replace {
                        best = Some(p);
                    }
                }
                Classification::Drop(reason) => {
                    if first_drop.is_none() {
                        first_drop = Some(reason);
                    }
                }
                Classification::None => {}
            }
        }
        if let Some(best) = best {
            return Classification::Payload(best);
        }
        first_drop
            .map(Classification::Drop)
            .unwrap_or(Classification::None)
    }

    fn all_images(&self, items: &[RawItem]) -> Option<Vec<ImageItem>> {
        let mut out = Vec::with_capacity(items.len());
        for item in items {
            if RtfGate::is_open(item) {
                return None;
            }
            let candidates = BinaryProbe::images(item);
            let pick = candidates
                .iter()
                .find(|i| i.data.len() <= self.caps.image_bytes)
                .or_else(|| candidates.first())?;
            out.push(pick.clone());
        }
        Some(out)
    }

    fn image_group(&self, images: Vec<ImageItem>) -> Option<Payload> {
        let mut fitting: Vec<ImageItem> = images
            .into_iter()
            .filter(|i| i.data.len() <= self.caps.image_bytes)
            .collect();
        let total: usize = fitting.iter().map(|i| i.data.len()).sum();
        if fitting.len() >= 2 && total <= self.caps.image_bytes {
            return Some(Payload::ImageSet(fitting));
        }
        if fitting.is_empty() {
            None
        } else {
            Some(Payload::Image(fitting.remove(0)))
        }
    }

    pub fn rank(payload: &Payload) -> usize {
        match payload {
            Payload::Image(_) | Payload::ImageSet(_) => 6,
            Payload::Svg(_) => 5,
            Payload::Pdf(_) => 4,
            Payload::RichText { .. } => 3,
            Payload::Url { .. } => 2,
            Payload::Color { .. } => 1,
            Payload::Text(_) | Payload::Files(_) => 0,
        }
    }
}

pub struct ItemChain<'a> {
    pub caps: SizeCaps,
    pub item: &'a RawItem,
    pub pending_drop: Option<DropReason>,
}

impl<'a> ItemChain<'a> {
    pub fn new(caps: SizeCaps, item: &'a RawItem) -> Self {
        Self {
            caps,
            item,
            pending_drop: None,
        }
    }

    pub fn run(&mut self) -> Classification {
        let plain = self
            .item
            .formats
            .get(&CanonicalFormat::PlainText)
            .map(|d| TextDecoding::utf8(d));
        let gate_open = RtfGate::is_open(self.item);
        let plain_blank = plain
            .as_deref()
            .map(|s| TextWhitespace::trim(s).is_empty())
            .unwrap_or(true);
        if !gate_open {
            if let Some(payload) = self.binary(plain_blank) {
                return Classification::Payload(payload);
            }
        }
        let text = self.text_legs(plain.as_deref());
        match &text {
            Classification::Payload(_) => return text,
            Classification::Drop(_) if !plain.as_deref().unwrap_or("").is_empty() => return text,
            Classification::Drop(_) | Classification::None => {}
        }
        if gate_open {
            if let Some(payload) = self.binary(true) {
                return Classification::Payload(payload);
            }
        }
        if matches!(text, Classification::Drop(_)) {
            return text;
        }
        self.pending_drop
            .map(Classification::Drop)
            .unwrap_or(Classification::None)
    }

    pub fn note(&mut self, reason: DropReason) {
        if self.pending_drop.is_none() {
            self.pending_drop = Some(reason);
        }
    }

    fn binary(&mut self, allow_pdf: bool) -> Option<Payload> {
        for image in BinaryProbe::images(self.item) {
            if image.data.len() <= self.caps.image_bytes {
                return Some(Payload::Image(image));
            }
            self.note(DropReason::OverCap(EntryKind::Image));
        }
        if let Some(svg) = self.svg_bytes() {
            return Some(Payload::Svg(svg));
        }
        if allow_pdf {
            if let Some(data) = self.item.formats.get(&CanonicalFormat::Pdf) {
                if !data.is_empty() {
                    if data.len() <= self.caps.pdf_bytes {
                        return Some(Payload::Pdf(data.clone()));
                    }
                    self.note(DropReason::OverCap(EntryKind::Pdf));
                }
            }
        }
        None
    }

    fn svg_bytes(&mut self) -> Option<String> {
        let data = self.item.formats.get(&CanonicalFormat::Svg)?;
        if data.is_empty() {
            return None;
        }
        if data.len() > self.caps.svg_bytes {
            self.note(DropReason::OverCap(EntryKind::Svg));
            return None;
        }
        if !SvgSanitizer::is_safe(data, &self.caps) {
            return None;
        }
        let xml = String::from_utf8_lossy(data).into_owned();
        if TextWhitespace::trim(&xml).is_empty() {
            None
        } else {
            Some(xml)
        }
    }
}
