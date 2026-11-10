use std::fmt;
use std::fs::{self, File};
use std::io::Read;
use std::path::Path;

use crate::core::model::FileName;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileReadError(pub String);

impl fmt::Display for FileReadError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for FileReadError {}

/// File reading port for `FileListClassifier` (`B-8.3.8`).
pub trait FileReading {
    fn size(&self, url_or_path: &str) -> Option<usize>;
    fn read(&self, url_or_path: &str) -> Result<Vec<u8>, FileReadError>;
    fn read_up_to(&self, url_or_path: &str, max_bytes: usize) -> Result<Vec<u8>, FileReadError> {
        let data = self.read(url_or_path)?;
        let cap = max_bytes.min(data.len());
        Ok(data[..cap].to_vec())
    }
}

#[derive(Debug, Clone, Copy, Default)]
pub struct DiskFileReading;

impl DiskFileReading {
    pub const fn new() -> Self {
        Self
    }

    fn resolve_path(url_or_path: &str) -> Option<String> {
        if url_or_path.contains("://")
            && !url_or_path
                .get(..7)
                .map(|s| s.eq_ignore_ascii_case("file://"))
                .unwrap_or(false)
        {
            return None;
        }
        Some(FileName::local_path(url_or_path))
    }
}

impl FileReading for DiskFileReading {
    fn size(&self, url_or_path: &str) -> Option<usize> {
        let local = Self::resolve_path(url_or_path)?;
        let meta = fs::metadata(Path::new(&local)).ok()?;
        if !meta.is_file() {
            return None;
        }
        usize::try_from(meta.len()).ok()
    }

    fn read(&self, url_or_path: &str) -> Result<Vec<u8>, FileReadError> {
        let local = Self::resolve_path(url_or_path)
            .ok_or_else(|| FileReadError("not a file URL".to_string()))?;
        fs::read(Path::new(&local)).map_err(|e| FileReadError(e.to_string()))
    }

    fn read_up_to(&self, url_or_path: &str, max_bytes: usize) -> Result<Vec<u8>, FileReadError> {
        let local = Self::resolve_path(url_or_path)
            .ok_or_else(|| FileReadError("not a file URL".to_string()))?;
        let file = File::open(Path::new(&local)).map_err(|e| FileReadError(e.to_string()))?;
        let mut out = Vec::new();
        file.take(max_bytes as u64)
            .read_to_end(&mut out)
            .map_err(|e| FileReadError(e.to_string()))?;
        Ok(out)
    }
}
