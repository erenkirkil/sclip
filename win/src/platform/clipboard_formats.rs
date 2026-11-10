use std::sync::OnceLock;

use crate::platform::sys::{
    to_wide_null, RegisterClipboardFormatW, CF_DIB, CF_DIBV5, CF_HDROP, CF_UNICODETEXT, UINT,
};

/// Registered and standard Win32 clipboard format identifiers (`B-8.3.9`, `B-8.8.7`, `B-8.9.7`).
#[derive(Debug, Clone, Copy)]
pub struct ClipboardFormats {
    pub unicode_text: UINT,
    pub hdrop: UINT,
    pub dib: UINT,
    pub dibv5: UINT,
    pub png: UINT,
    pub image_png: UINT,
    pub jfif: UINT,
    pub jpeg: UINT,
    pub image_jpeg: UINT,
    pub gif: UINT,
    pub image_gif: UINT,
    pub webp: UINT,
    pub image_webp: UINT,
    pub svg: UINT,
    pub app_pdf: UINT,
    pub pdf: UINT,
    pub html: UINT,
    pub rtf: UINT,
    pub exclude_monitoring: UINT,
    pub can_include_in_history: UINT,
    pub viewer_ignore: UINT,
}

impl ClipboardFormats {
    pub fn get() -> &'static Self {
        static FORMATS: OnceLock<ClipboardFormats> = OnceLock::new();
        FORMATS.get_or_init(|| Self {
            unicode_text: CF_UNICODETEXT,
            hdrop: CF_HDROP,
            dib: CF_DIB,
            dibv5: CF_DIBV5,
            png: register_format("PNG"),
            image_png: register_format("image/png"),
            jfif: register_format("JFIF"),
            jpeg: register_format("JPEG"),
            image_jpeg: register_format("image/jpeg"),
            gif: register_format("GIF"),
            image_gif: register_format("image/gif"),
            webp: register_format("WEBP"),
            image_webp: register_format("image/webp"),
            svg: register_format("image/svg+xml"),
            app_pdf: register_format("Application/pdf"),
            pdf: register_format("PDF"),
            html: register_format("HTML Format"),
            rtf: register_format("Rich Text Format"),
            exclude_monitoring: register_format("ExcludeClipboardContentFromMonitoring"),
            can_include_in_history: register_format("CanIncludeInClipboardHistory"),
            viewer_ignore: register_format("Clipboard Viewer Ignore"),
        })
    }
}

pub fn register_format(name: &str) -> UINT {
    let wide = to_wide_null(name);
    unsafe { RegisterClipboardFormatW(wide.as_ptr()) }
}

/// Extracts the `StartFragment`..`EndFragment` byte slice from a Windows `HTML Format` payload (`B-8.3.9`).
/// Returns `None` if headers or offsets are missing, negative, or out of bounds.
pub fn extract_cf_html_fragment(raw: &[u8]) -> Option<String> {
    let trimmed = match raw.iter().rposition(|&b| b != 0) {
        Some(last) => &raw[..=last],
        None => return None,
    };
    let header_scan_len = trimmed.len().min(1024);
    let header_str = core::str::from_utf8(&trimmed[..header_scan_len]).ok()?;

    let mut start_fragment: Option<usize> = None;
    let mut end_fragment: Option<usize> = None;

    for line in header_str.lines() {
        let line = line.trim();
        if line.starts_with('<') {
            break;
        }
        if let Some(rest) = strip_prefix_ci(line, "StartFragment:") {
            start_fragment = Some(parse_positive_offset(rest.trim())?);
        } else if let Some(rest) = strip_prefix_ci(line, "EndFragment:") {
            end_fragment = Some(parse_positive_offset(rest.trim())?);
        }
    }

    let start = start_fragment?;
    let end = end_fragment?;
    if start == 0 || start > end || end > trimmed.len() {
        return None;
    }

    let slice = &trimmed[start..end];
    Some(String::from_utf8_lossy(slice).into_owned())
}

/// Builds a standard Windows `HTML Format` byte payload with 10-digit zero-padded byte offsets (`B-8.9.7`).
pub fn build_cf_html_payload(fragment: &str) -> Vec<u8> {
    const HEADER_LEN: usize = 105;
    const PREFIX: &str = "<html>\r\n<body>\r\n<!--StartFragment-->";
    const SUFFIX: &str = "<!--EndFragment-->\r\n</body>\r\n</html>";

    let start_html = HEADER_LEN;
    let start_fragment = start_html + PREFIX.len();
    let end_fragment = start_fragment + fragment.len();
    let end_html = end_fragment + SUFFIX.len();

    let formatted = format!(
        "Version:0.9\r\nStartHTML:{:010}\r\nEndHTML:{:010}\r\nStartFragment:{:010}\r\nEndFragment:{:010}\r\n{}{}{}",
        start_html, end_html, start_fragment, end_fragment, PREFIX, fragment, SUFFIX
    );
    formatted.into_bytes()
}

fn strip_prefix_ci<'a>(s: &'a str, prefix: &str) -> Option<&'a str> {
    if s.len() < prefix.len() {
        return None;
    }
    if s.as_bytes()[..prefix.len()].eq_ignore_ascii_case(prefix.as_bytes()) {
        s.get(prefix.len()..)
    } else {
        None
    }
}

fn parse_positive_offset(s: &str) -> Option<usize> {
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse::<usize>().ok()
}
