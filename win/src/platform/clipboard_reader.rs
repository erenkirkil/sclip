use core::slice;
use std::cell::Cell;
use std::collections::{BTreeSet, HashMap};
use std::thread;
use std::time::{Duration, Instant};

use crate::core::model::{CanonicalFormat, ClipFlag, EntryId, RawClip, RawItem};
use crate::core::ports::{ClipboardSource, ClipboardState};
use crate::platform::clipboard_formats::{extract_cf_html_fragment, ClipboardFormats};
use crate::platform::image_transcoder;
use crate::platform::sys::{
    CloseClipboard, DragQueryFileW, GetClipboardData, GetClipboardSequenceNumber, GlobalLock,
    GlobalSize, GlobalUnlock, IsClipboardFormatAvailable, OpenClipboard, CF_DIB, CF_DIBV5,
    CF_HDROP, CF_UNICODETEXT, HANDLE, HWND, UINT,
};

pub const OPEN_CLIPBOARD_RETRIES: usize = 5;
pub const OPEN_CLIPBOARD_RETRY_DELAY_MS: u64 = 12;
pub const FORMAT_READ_TIMEOUT: Duration = Duration::from_secs(10);

/// RAII guard that closes the Win32 clipboard on drop (`B-8.8.2`).
pub struct ClipboardGuard;

impl Drop for ClipboardGuard {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseClipboard();
        }
    }
}

/// Attempts `OpenClipboard(hwnd)` up to 5 times with 12 ms backoff (`B-8.8.2`).
pub fn open_clipboard_with_retry(hwnd: HWND) -> Option<ClipboardGuard> {
    for attempt in 0..OPEN_CLIPBOARD_RETRIES {
        if attempt > 0 {
            thread::sleep(Duration::from_millis(OPEN_CLIPBOARD_RETRY_DELAY_MS));
        }
        if unsafe { OpenClipboard(hwnd) } != 0 {
            return Some(ClipboardGuard);
        }
    }
    None
}

/// Pure sensitivity evaluator for unit testing (`B-8.8.7`, `E31`).
pub fn evaluate_sensitivity(
    viewer_ignore_present: bool,
    exclude_monitoring_bytes: Option<&[u8]>,
    can_include_in_history_bytes: Option<&[u8]>,
    open_failed_when_marker_present: bool,
) -> bool {
    if viewer_ignore_present || open_failed_when_marker_present {
        return true;
    }
    if let Some(bytes) = exclude_monitoring_bytes {
        if bytes.is_empty() {
            return true;
        }
        if bytes.len() >= 4 {
            let val = u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
            if val != 0 {
                return true;
            }
        } else if bytes.iter().any(|&b| b != 0) {
            return true;
        }
    }
    if let Some(bytes) = can_include_in_history_bytes {
        if bytes.len() >= 4 {
            let val = u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
            if val == 0 {
                return true;
            }
        }
    }
    false
}

/// Win32 clipboard reader implementing `ClipboardSource` (`B-8.8.2`, `B-8.8.4`, `B-8.8.6`, `B-8.8.7`, `B-8.3.9`).
pub struct ClipboardReader {
    hwnd: HWND,
    last_checked_seq: Cell<Option<i64>>,
    cached_sensitive: Cell<bool>,
}

impl Default for ClipboardReader {
    fn default() -> Self {
        Self::new(0)
    }
}

impl ClipboardReader {
    pub const fn new(hwnd: HWND) -> Self {
        Self {
            hwnd,
            last_checked_seq: Cell::new(None),
            cached_sensitive: Cell::new(false),
        }
    }

    fn probe_sensitivity(&self, seq: i64) -> bool {
        if self.last_checked_seq.get() == Some(seq) {
            return self.cached_sensitive.get();
        }
        let fmt = ClipboardFormats::get();
        let viewer_ignore =
            fmt.viewer_ignore != 0 && unsafe { IsClipboardFormatAvailable(fmt.viewer_ignore) } != 0;
        if viewer_ignore {
            self.last_checked_seq.set(Some(seq));
            self.cached_sensitive.set(true);
            return true;
        }

        let has_exclude = fmt.exclude_monitoring != 0
            && unsafe { IsClipboardFormatAvailable(fmt.exclude_monitoring) } != 0;
        let has_history = fmt.can_include_in_history != 0
            && unsafe { IsClipboardFormatAvailable(fmt.can_include_in_history) } != 0;

        if !has_exclude && !has_history {
            self.last_checked_seq.set(Some(seq));
            self.cached_sensitive.set(false);
            return false;
        }

        let Some(_guard) = open_clipboard_with_retry(self.hwnd) else {
            // B-8.8.7 / E31: Fail-closed when clipboard cannot be opened after 5 retries.
            return true;
        };

        let exclude_bytes = if has_exclude {
            Some(read_raw_format_bytes(fmt.exclude_monitoring).unwrap_or_default())
        } else {
            None
        };
        let history_bytes = if has_history {
            read_raw_format_bytes(fmt.can_include_in_history)
        } else {
            None
        };

        let sensitive = evaluate_sensitivity(
            false,
            exclude_bytes.as_deref(),
            history_bytes.as_deref(),
            false,
        );
        self.last_checked_seq.set(Some(seq));
        self.cached_sensitive.set(sensitive);
        sensitive
    }
}

impl ClipboardSource for ClipboardReader {
    fn current_state(&self) -> ClipboardState {
        let seq = unsafe { GetClipboardSequenceNumber() } as i64;
        let sensitive = self.probe_sensitivity(seq);
        let has_files = unsafe { IsClipboardFormatAvailable(CF_HDROP) } != 0;
        ClipboardState::new(seq, sensitive, has_files)
    }

    fn read_files(&self, _destination: Option<EntryId>) -> Vec<String> {
        let deadline = Instant::now() + FORMAT_READ_TIMEOUT;
        let Some(_guard) = open_clipboard_with_retry(self.hwnd) else {
            return Vec::new();
        };
        read_hdrop_files_locked(deadline)
    }

    fn read_clip(&self) -> RawClip {
        let deadline = Instant::now() + FORMAT_READ_TIMEOUT;
        let fmt = ClipboardFormats::get();
        let Some(_guard) = open_clipboard_with_retry(self.hwnd) else {
            let mut flags = BTreeSet::new();
            flags.insert(ClipFlag::Concealed);
            return RawClip::new(Vec::new(), Vec::new(), flags);
        };

        let mut flags = BTreeSet::new();
        let viewer_ignore =
            fmt.viewer_ignore != 0 && unsafe { IsClipboardFormatAvailable(fmt.viewer_ignore) } != 0;
        let exclude_bytes = if fmt.exclude_monitoring != 0
            && unsafe { IsClipboardFormatAvailable(fmt.exclude_monitoring) } != 0
        {
            Some(read_raw_format_bytes(fmt.exclude_monitoring).unwrap_or_default())
        } else {
            None
        };
        let history_bytes = if fmt.can_include_in_history != 0
            && unsafe { IsClipboardFormatAvailable(fmt.can_include_in_history) } != 0
        {
            read_raw_format_bytes(fmt.can_include_in_history)
        } else {
            None
        };
        if evaluate_sensitivity(
            viewer_ignore,
            exclude_bytes.as_deref(),
            history_bytes.as_deref(),
            false,
        ) {
            flags.insert(ClipFlag::Concealed);
        }

        let mut formats = HashMap::new();

        if Instant::now() < deadline {
            if let Some(text) = read_unicode_text() {
                formats.insert(CanonicalFormat::PlainText, text.into_bytes());
            }
        }
        if Instant::now() < deadline && fmt.html != 0 {
            if let Some(raw_html) = read_raw_format_bytes(fmt.html) {
                if let Some(fragment) = extract_cf_html_fragment(&raw_html) {
                    if !fragment.is_empty() {
                        formats.insert(CanonicalFormat::Html, fragment.into_bytes());
                    }
                }
            }
        }
        if Instant::now() < deadline && fmt.rtf != 0 {
            if let Some(rtf_bytes) = read_trimmed_format_bytes(fmt.rtf) {
                formats.insert(CanonicalFormat::Rtf, rtf_bytes);
            }
        }
        if Instant::now() < deadline {
            if let Some(png) = read_first_available(&[fmt.png, fmt.image_png]) {
                formats.insert(CanonicalFormat::Png, png);
            }
        }
        if Instant::now() < deadline {
            if let Some(jpeg) = read_first_available(&[fmt.jfif, fmt.jpeg, fmt.image_jpeg]) {
                formats.insert(CanonicalFormat::Jpeg, jpeg);
            }
        }
        if Instant::now() < deadline {
            if let Some(gif) = read_first_available(&[fmt.gif, fmt.image_gif]) {
                formats.insert(CanonicalFormat::Gif, gif);
            }
        }
        if Instant::now() < deadline {
            if let Some(webp) = read_first_available(&[fmt.webp, fmt.image_webp]) {
                formats.insert(CanonicalFormat::Webp, webp);
            }
        }
        if Instant::now() < deadline && fmt.svg != 0 {
            if let Some(svg) = read_trimmed_format_bytes(fmt.svg) {
                formats.insert(CanonicalFormat::Svg, svg);
            }
        }
        if Instant::now() < deadline {
            if let Some(pdf) = read_first_available(&[fmt.app_pdf, fmt.pdf]) {
                formats.insert(CanonicalFormat::Pdf, pdf);
            }
        }

        let has_direct_raster = formats.contains_key(&CanonicalFormat::Png)
            || formats.contains_key(&CanonicalFormat::Jpeg)
            || formats.contains_key(&CanonicalFormat::Gif)
            || formats.contains_key(&CanonicalFormat::Webp);

        if !has_direct_raster && Instant::now() < deadline {
            if let Some(dibv5) = read_raw_format_bytes(CF_DIBV5) {
                if let Some(png) = image_transcoder::dib_to_png(&dibv5, true) {
                    formats.insert(CanonicalFormat::Png, png);
                }
            } else if let Some(dib) = read_raw_format_bytes(CF_DIB) {
                if let Some(png) = image_transcoder::dib_to_png(&dib, false) {
                    formats.insert(CanonicalFormat::Png, png);
                }
            }
        }

        let files = if Instant::now() < deadline {
            read_hdrop_files_locked(deadline)
        } else {
            Vec::new()
        };

        let items = if formats.is_empty() {
            Vec::new()
        } else {
            vec![RawItem::new(formats)]
        };
        RawClip::new(items, files, flags)
    }
}

fn read_first_available(candidates: &[UINT]) -> Option<Vec<u8>> {
    for &fmt in candidates {
        if fmt != 0 {
            if let Some(bytes) = read_raw_format_bytes(fmt) {
                if !bytes.is_empty() {
                    return Some(bytes);
                }
            }
        }
    }
    None
}

fn read_raw_format_bytes(format: UINT) -> Option<Vec<u8>> {
    if format == 0 || unsafe { IsClipboardFormatAvailable(format) } == 0 {
        return None;
    }
    let handle: HANDLE = unsafe { GetClipboardData(format) };
    if handle.is_null() {
        return None;
    }
    let size = unsafe { GlobalSize(handle) };
    if size == 0 {
        return Some(Vec::new());
    }
    let ptr = unsafe { GlobalLock(handle) } as *const u8;
    if ptr.is_null() {
        return None;
    }
    let data = unsafe { slice::from_raw_parts(ptr, size) }.to_vec();
    unsafe {
        let _ = GlobalUnlock(handle);
    }
    Some(data)
}

fn read_trimmed_format_bytes(format: UINT) -> Option<Vec<u8>> {
    let mut bytes = read_raw_format_bytes(format)?;
    while bytes.last() == Some(&0) {
        bytes.pop();
    }
    Some(bytes)
}

fn read_unicode_text() -> Option<String> {
    if unsafe { IsClipboardFormatAvailable(CF_UNICODETEXT) } == 0 {
        return None;
    }
    let handle: HANDLE = unsafe { GetClipboardData(CF_UNICODETEXT) };
    if handle.is_null() {
        return None;
    }
    let byte_size = unsafe { GlobalSize(handle) };
    let u16_len = byte_size / 2;
    if u16_len == 0 {
        return None;
    }
    let ptr = unsafe { GlobalLock(handle) } as *const u16;
    if ptr.is_null() {
        return None;
    }
    let wide = unsafe { slice::from_raw_parts(ptr, u16_len) };
    let actual_len = wide.iter().position(|&c| c == 0).unwrap_or(wide.len());
    let text = String::from_utf16_lossy(&wide[..actual_len]);
    unsafe {
        let _ = GlobalUnlock(handle);
    }
    Some(text)
}

fn read_hdrop_files_locked(deadline: Instant) -> Vec<String> {
    if unsafe { IsClipboardFormatAvailable(CF_HDROP) } == 0 {
        return Vec::new();
    }
    let handle = unsafe { GetClipboardData(CF_HDROP) };
    if handle.is_null() {
        return Vec::new();
    }
    let count = unsafe { DragQueryFileW(handle, 0xFFFF_FFFF, core::ptr::null_mut(), 0) };
    let mut paths = Vec::with_capacity(count as usize);
    for i in 0..count {
        if Instant::now() >= deadline {
            break;
        }
        let len = unsafe { DragQueryFileW(handle, i, core::ptr::null_mut(), 0) };
        if len == 0 {
            continue;
        }
        let mut buf = vec![0u16; (len as usize) + 1];
        let written = unsafe { DragQueryFileW(handle, i, buf.as_mut_ptr(), len + 1) };
        if written == 0 {
            continue;
        }
        let path = String::from_utf16_lossy(&buf[..written as usize]);
        if !path.is_empty() {
            paths.push(path);
        }
    }
    paths
}
