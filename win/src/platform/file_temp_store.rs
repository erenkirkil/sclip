use std::fs;
use std::path::{Path, PathBuf};

use crate::core::model::{Entry, EntryId, FileName, ImageFormat, Payload};
use crate::core::ports::{TempStore, TempStoreError};

/// `<root>/sclip/<entryId>/` temporary file store (`B-8.4.1`..`B-8.4.4`, `E29`).
pub struct FileTempStore {
    root: PathBuf,
    is_on_pasteboard: Box<dyn Fn(&Entry) -> bool>,
}

impl FileTempStore {
    pub fn new<F>(root: PathBuf, is_on_pasteboard: F) -> Self
    where
        F: Fn(&Entry) -> bool + 'static,
    {
        Self {
            root,
            is_on_pasteboard: Box::new(is_on_pasteboard),
        }
    }

    pub fn with_default_root<F>(is_on_pasteboard: F) -> Self
    where
        F: Fn(&Entry) -> bool + 'static,
    {
        Self::new(std::env::temp_dir(), is_on_pasteboard)
    }

    pub fn sclip_root_dir(&self) -> PathBuf {
        self.root.join("sclip")
    }

    pub fn entry_dir(&self, id: EntryId) -> PathBuf {
        self.sclip_root_dir().join(id.to_string())
    }

    pub fn file_extension(format: ImageFormat) -> &'static str {
        match format {
            ImageFormat::Png => "png",
            ImageFormat::Jpeg => "jpg",
            ImageFormat::Gif => "gif",
            ImageFormat::Webp => "webp",
        }
    }

    fn fresh_entry_dir(&self, id: EntryId) -> Result<PathBuf, TempStoreError> {
        let dir = self.entry_dir(id);
        if dir.exists() {
            let _ = fs::remove_dir_all(&dir);
        }
        fs::create_dir_all(&dir).map_err(|e| TempStoreError::Io(e.to_string()))?;
        Ok(dir)
    }

    fn write_atomic(dir: &Path, filename: &str, bytes: &[u8]) -> Result<String, TempStoreError> {
        let tmp_path = dir.join(format!(".tmp_{}", filename));
        let final_path = dir.join(filename);
        fs::write(&tmp_path, bytes).map_err(|e| TempStoreError::Io(e.to_string()))?;
        fs::rename(&tmp_path, &final_path).map_err(|e| TempStoreError::Io(e.to_string()))?;
        Ok(final_path.to_string_lossy().into_owned())
    }
}

impl TempStore for FileTempStore {
    fn materialize(&self, entry: &Entry) -> Result<Vec<String>, TempStoreError> {
        if entry.is_sensitive {
            return Err(TempStoreError::SensitiveEntry);
        }

        let dir = self.fresh_entry_dir(entry.id)?;
        match &entry.payload {
            Payload::Svg(xml) => {
                let path = Self::write_atomic(&dir, "clipboard.svg", xml.as_bytes())?;
                Ok(vec![path])
            }
            Payload::Pdf(data) => {
                let path = Self::write_atomic(&dir, "clipboard.pdf", data)?;
                Ok(vec![path])
            }
            Payload::Image(item) => {
                let ext = Self::file_extension(item.format);
                let name = format!("clipboard.{}", ext);
                let path = Self::write_atomic(&dir, &name, &item.data)?;
                Ok(vec![path])
            }
            Payload::ImageSet(items) => {
                let mut paths = Vec::with_capacity(items.len());
                for (index, item) in items.iter().enumerate() {
                    let ext = Self::file_extension(item.format);
                    let name = format!("{:03}.{}", index + 1, ext);
                    let path = Self::write_atomic(&dir, &name, &item.data)?;
                    paths.push(path);
                }
                Ok(paths)
            }
            Payload::Text(_)
            | Payload::Url { .. }
            | Payload::Color { .. }
            | Payload::Files(_)
            | Payload::RichText { .. } => Err(TempStoreError::UnsupportedPayload),
        }
    }

    fn delete(&self, entry: &Entry) {
        if (self.is_on_pasteboard)(entry) {
            return;
        }
        let dir = self.entry_dir(entry.id);
        let _ = fs::remove_dir_all(dir);
    }

    fn prune_all(&self) {
        let _ = fs::remove_dir_all(self.sclip_root_dir());
    }
}

/// Converts a local Windows path into a `file:///` URI.
pub fn path_to_file_uri(path: &Path) -> String {
    let raw = path.to_string_lossy();
    let normalized = raw.replace('\\', "/");
    let mut encoded = String::with_capacity(normalized.len() + 16);
    if !normalized.starts_with('/') {
        encoded.push_str("file:///");
    } else {
        encoded.push_str("file://");
    }
    for b in normalized.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' | b'/' | b':' => {
                encoded.push(b as char);
            }
            _ => {
                encoded.push_str(&format!("%{:02X}", b));
            }
        }
    }
    encoded
}

/// Resolves a `file://` URI or local path string into a Windows `PathBuf`.
pub fn file_uri_to_path(uri_or_path: &str) -> PathBuf {
    let decoded = FileName::local_path(uri_or_path);
    let bytes = decoded.as_bytes();
    let stripped = if bytes.len() >= 3
        && (bytes[0] == b'/' || bytes[0] == b'\\')
        && bytes[1].is_ascii_alphabetic()
        && bytes[2] == b':'
    {
        &decoded[1..]
    } else {
        &decoded[..]
    };
    PathBuf::from(stripped.replace('/', "\\"))
}
