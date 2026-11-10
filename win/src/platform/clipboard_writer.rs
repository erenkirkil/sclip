use core::mem::size_of;
use core::ptr;
use std::rc::Rc;

use crate::core::hash::ContentHash;
use crate::core::model::{Entry, ImageFormat, ImageItem, Payload};
use crate::core::ports::{ClipboardSink, ClipboardWriteError, TempStore, WriteReceipt};
use crate::platform::clipboard_formats::{build_cf_html_payload, ClipboardFormats};
use crate::platform::clipboard_reader::open_clipboard_with_retry;
use crate::platform::file_temp_store::file_uri_to_path;
use crate::platform::image_transcoder;
use crate::platform::sys::{
    EmptyClipboard, GetClipboardSequenceNumber, GlobalAlloc, GlobalFree, GlobalLock, GlobalUnlock,
    SetClipboardData, CF_DIBV5, CF_HDROP, CF_UNICODETEXT, DROPFILES, FALSE, GMEM_MOVEABLE,
    GMEM_ZEROINIT, HGLOBAL, HWND, POINT, TRUE, UINT,
};

/// RAII wrapper for `HGLOBAL` allocated before `EmptyClipboard()` (`B-8.9.8`, `E28`).
pub struct GlobalMemGuard {
    handle: HGLOBAL,
}

impl GlobalMemGuard {
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, ClipboardWriteError> {
        let alloc_size = bytes.len().max(1);
        let handle = unsafe { GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, alloc_size) };
        if handle.is_null() {
            return Err(ClipboardWriteError("GlobalAlloc failed".to_string()));
        }
        if !bytes.is_empty() {
            let dst = unsafe { GlobalLock(handle) } as *mut u8;
            if dst.is_null() {
                unsafe {
                    let _ = GlobalFree(handle);
                }
                return Err(ClipboardWriteError("GlobalLock failed".to_string()));
            }
            unsafe {
                ptr::copy_nonoverlapping(bytes.as_ptr(), dst, bytes.len());
                let _ = GlobalUnlock(handle);
            }
        }
        Ok(Self { handle })
    }

    pub fn from_bytes_null_terminated(bytes: &[u8]) -> Result<Self, ClipboardWriteError> {
        let mut buf = Vec::with_capacity(bytes.len() + 1);
        buf.extend_from_slice(bytes);
        buf.push(0);
        Self::from_bytes(&buf)
    }

    pub fn from_wide_str(s: &str) -> Result<Self, ClipboardWriteError> {
        let mut wide: Vec<u16> = s.encode_utf16().collect();
        wide.push(0);
        let byte_len = wide.len() * size_of::<u16>();
        let handle = unsafe { GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, byte_len) };
        if handle.is_null() {
            return Err(ClipboardWriteError("GlobalAlloc wide failed".to_string()));
        }
        let dst = unsafe { GlobalLock(handle) } as *mut u16;
        if dst.is_null() {
            unsafe {
                let _ = GlobalFree(handle);
            }
            return Err(ClipboardWriteError("GlobalLock wide failed".to_string()));
        }
        unsafe {
            ptr::copy_nonoverlapping(wide.as_ptr(), dst, wide.len());
            let _ = GlobalUnlock(handle);
        }
        Ok(Self { handle })
    }

    pub fn from_hdrop_paths(paths: &[String]) -> Result<Self, ClipboardWriteError> {
        let mut wide_paths: Vec<Vec<u16>> = Vec::with_capacity(paths.len());
        for p in paths {
            let resolved = file_uri_to_path(p);
            let s = resolved.to_string_lossy();
            if !s.is_empty() {
                wide_paths.push(s.encode_utf16().collect());
            }
        }
        if wide_paths.is_empty() {
            return Err(ClipboardWriteError("no valid file paths".to_string()));
        }

        let mut u16_count = 1usize; // final terminating NUL
        for wp in &wide_paths {
            u16_count += wp.len() + 1;
        }
        let header_bytes = size_of::<DROPFILES>();
        let total_bytes = header_bytes + u16_count * size_of::<u16>();

        let handle = unsafe { GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, total_bytes) };
        if handle.is_null() {
            return Err(ClipboardWriteError("GlobalAlloc HDROP failed".to_string()));
        }
        let base = unsafe { GlobalLock(handle) } as *mut u8;
        if base.is_null() {
            unsafe {
                let _ = GlobalFree(handle);
            }
            return Err(ClipboardWriteError("GlobalLock HDROP failed".to_string()));
        }

        unsafe {
            let drop_ptr = base as *mut DROPFILES;
            (*drop_ptr).pFiles = header_bytes as u32;
            (*drop_ptr).pt = POINT { x: 0, y: 0 };
            (*drop_ptr).fNC = FALSE;
            (*drop_ptr).fWide = TRUE;

            let mut cursor = base.add(header_bytes) as *mut u16;
            for wp in &wide_paths {
                ptr::copy_nonoverlapping(wp.as_ptr(), cursor, wp.len());
                cursor = cursor.add(wp.len());
                *cursor = 0;
                cursor = cursor.add(1);
            }
            *cursor = 0;
            let _ = GlobalUnlock(handle);
        }
        Ok(Self { handle })
    }

    pub fn as_raw(&self) -> HGLOBAL {
        self.handle
    }

    pub fn into_raw(mut self) -> HGLOBAL {
        let h = self.handle;
        self.handle = ptr::null_mut();
        h
    }
}

impl Drop for GlobalMemGuard {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe {
                let _ = GlobalFree(self.handle);
            }
        }
    }
}

struct PreparedFormat {
    format: UINT,
    mem: GlobalMemGuard,
}

/// Win32 clipboard writer implementing `ClipboardSink` (`B-8.9.1`..`B-8.9.8`, `E21`, `E28`, `E30`).
pub struct ClipboardWriter {
    hwnd: HWND,
    temp: Rc<dyn TempStore>,
}

impl ClipboardWriter {
    pub fn new(hwnd: HWND, temp: Rc<dyn TempStore>) -> Self {
        Self { hwnd, temp }
    }

    fn prepare_image(item: &ImageItem) -> Result<Vec<PreparedFormat>, ClipboardWriteError> {
        let fmt = ClipboardFormats::get();
        let mut out = Vec::new();
        let primary_fmt = match item.format {
            ImageFormat::Png => fmt.png,
            ImageFormat::Jpeg => fmt.jfif,
            ImageFormat::Gif => fmt.gif,
            ImageFormat::Webp => fmt.webp,
        };
        if primary_fmt == 0 {
            return Err(ClipboardWriteError(
                "clipboard image format registration failed".to_string(),
            ));
        }
        out.push(PreparedFormat {
            format: primary_fmt,
            mem: GlobalMemGuard::from_bytes(&item.data)?,
        });
        if let Some(dibv5) = image_transcoder::png_to_dibv5(&item.data) {
            out.push(PreparedFormat {
                format: CF_DIBV5,
                mem: GlobalMemGuard::from_bytes(&dibv5)?,
            });
        }
        Ok(out)
    }

    /// Prepares all `HGLOBAL` blocks and temp files prior to `EmptyClipboard()` (`B-8.9.8`, `E28`).
    fn prepare_entry(
        &self,
        entry: &Entry,
        plain_only: bool,
        image_index: Option<usize>,
    ) -> Result<(Vec<PreparedFormat>, String), ClipboardWriteError> {
        let fmt = ClipboardFormats::get();
        let mut prepared = Vec::new();
        let signature: String;

        match &entry.payload {
            Payload::Text(s)
            | Payload::Url { original: s, .. }
            | Payload::Color { original: s, .. } => {
                prepared.push(PreparedFormat {
                    format: CF_UNICODETEXT,
                    mem: GlobalMemGuard::from_wide_str(s)?,
                });
                signature = entry.content_hash.clone();
            }
            Payload::RichText { plain, html, rtf } => {
                if plain_only {
                    prepared.push(PreparedFormat {
                        format: CF_UNICODETEXT,
                        mem: GlobalMemGuard::from_wide_str(plain)?,
                    });
                    signature = ContentHash::text("t", plain);
                } else {
                    prepared.push(PreparedFormat {
                        format: CF_UNICODETEXT,
                        mem: GlobalMemGuard::from_wide_str(plain)?,
                    });
                    if fmt.html != 0 {
                        let cf_html = build_cf_html_payload(html);
                        prepared.push(PreparedFormat {
                            format: fmt.html,
                            mem: GlobalMemGuard::from_bytes_null_terminated(&cf_html)?,
                        });
                    }
                    if let Some(rtf_bytes) = rtf {
                        if !rtf_bytes.is_empty() && fmt.rtf != 0 {
                            prepared.push(PreparedFormat {
                                format: fmt.rtf,
                                mem: GlobalMemGuard::from_bytes(rtf_bytes)?,
                            });
                        }
                    }
                    signature = entry.content_hash.clone();
                }
            }
            Payload::Svg(xml) => {
                if !entry.is_sensitive {
                    if let Ok(paths) = self.temp.materialize(entry) {
                        if !paths.is_empty() {
                            prepared.push(PreparedFormat {
                                format: CF_HDROP,
                                mem: GlobalMemGuard::from_hdrop_paths(&paths)?,
                            });
                        }
                    }
                }
                if fmt.svg != 0 {
                    prepared.push(PreparedFormat {
                        format: fmt.svg,
                        mem: GlobalMemGuard::from_bytes(xml.as_bytes())?,
                    });
                }
                prepared.push(PreparedFormat {
                    format: CF_UNICODETEXT,
                    mem: GlobalMemGuard::from_wide_str(xml)?,
                });
                signature = entry.content_hash.clone();
            }
            Payload::Pdf(data) => {
                if !entry.is_sensitive {
                    if let Ok(paths) = self.temp.materialize(entry) {
                        if !paths.is_empty() {
                            prepared.push(PreparedFormat {
                                format: CF_HDROP,
                                mem: GlobalMemGuard::from_hdrop_paths(&paths)?,
                            });
                        }
                    }
                }
                if fmt.app_pdf != 0 {
                    prepared.push(PreparedFormat {
                        format: fmt.app_pdf,
                        mem: GlobalMemGuard::from_bytes(data)?,
                    });
                }
                signature = entry.content_hash.clone();
            }
            Payload::Image(item) => {
                prepared.extend(Self::prepare_image(item)?);
                signature = entry.content_hash.clone();
            }
            Payload::ImageSet(items) => {
                if let Some(index) = image_index {
                    let Some(chosen) = items.get(index) else {
                        return Err(ClipboardWriteError("invalid image index".to_string()));
                    };
                    prepared.extend(Self::prepare_image(chosen)?);
                    signature = ContentHash::bytes("i", &chosen.data);
                } else if entry.is_sensitive {
                    let Some(first) = items.first() else {
                        return Err(ClipboardWriteError("empty image set".to_string()));
                    };
                    prepared.extend(Self::prepare_image(first)?);
                    signature = entry.content_hash.clone();
                } else {
                    let paths = self
                        .temp
                        .materialize(entry)
                        .map_err(|e| ClipboardWriteError(e.to_string()))?;
                    prepared.push(PreparedFormat {
                        format: CF_HDROP,
                        mem: GlobalMemGuard::from_hdrop_paths(&paths)?,
                    });
                    signature = entry.content_hash.clone();
                }
            }
            Payload::Files(urls) => {
                prepared.push(PreparedFormat {
                    format: CF_HDROP,
                    mem: GlobalMemGuard::from_hdrop_paths(urls)?,
                });
                signature = entry.content_hash.clone();
            }
        }

        if prepared.is_empty() {
            return Err(ClipboardWriteError("no clipboard formats prepared".to_string()));
        }
        Ok((prepared, signature))
    }
}

impl ClipboardSink for ClipboardWriter {
    fn write(
        &self,
        entry: &Entry,
        plain_only: bool,
        image_index: Option<usize>,
    ) -> Result<WriteReceipt, ClipboardWriteError> {
        let (prepared, signature) = self.prepare_entry(entry, plain_only, image_index)?;

        let _guard = open_clipboard_with_retry(self.hwnd)
            .ok_or_else(|| ClipboardWriteError("OpenClipboard failed".to_string()))?;

        if unsafe { EmptyClipboard() } == 0 {
            return Err(ClipboardWriteError("EmptyClipboard failed".to_string()));
        }

        for item in prepared {
            let placed = unsafe { SetClipboardData(item.format, item.mem.as_raw()) };
            if placed.is_null() {
                return Err(ClipboardWriteError("SetClipboardData failed".to_string()));
            }
            let _ = item.mem.into_raw();
        }

        drop(_guard);
        let change = unsafe { GetClipboardSequenceNumber() } as i64;
        Ok(WriteReceipt::new(change, signature))
    }
}
