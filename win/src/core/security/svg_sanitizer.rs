use crate::core::security::SizeCaps;

const FORBIDDEN: &[&[u8]] = &[
    b"<!doctype",
    b"<!entity",
    b"<!attlist",
    b"xmlns:xi=",
    b"xinclude",
    b"<script",
    b"<foreignobject",
    b"@import",
];

const ACTIVE_ELEMENTS: &[&[u8]] = &[b"script", b"foreignobject"];
const HREF: &[u8] = b"href";
const URL_OPEN: &[u8] = b"url(";
const DATA_SCHEME: &[u8] = b"data:";
const XML_DECL: &[u8] = b"<?xml";
const DECL_END: &[u8] = b"?>";
const ENCODING_NAME: &[u8] = b"encoding";
const ALLOWED_ENCODINGS: &[&[u8]] = &[b"utf-8", b"us-ascii", b"ascii"];

/// SVG security check (`behavior.md` `B-8.10.x`, deviation `S8.10`).
pub struct SvgSanitizer;

impl SvgSanitizer {
    pub fn is_safe(data: &[u8], caps: &SizeCaps) -> bool {
        if data.len() > caps.svg_bytes {
            return false;
        }
        if has_nul_or_utf16_bom(data) {
            return false;
        }
        if std::str::from_utf8(data).is_err() {
            return false;
        }
        let mut bytes = data.to_vec();
        for b in &mut bytes {
            if *b >= 0x41 && *b <= 0x5A {
                *b += 0x20;
            }
        }
        if !encoding_is_safe(&bytes) {
            return false;
        }
        for token in FORBIDDEN {
            if find(&bytes, token, 0).is_some() {
                return false;
            }
        }
        if has_prefixed_active_element(&bytes) {
            return false;
        }
        css_urls_are_safe(&bytes) && hrefs_are_safe(&bytes)
    }
}

fn has_nul_or_utf16_bom(data: &[u8]) -> bool {
    let mut prev: u8 = 0x41;
    for &b in data {
        if b == 0x00 {
            return true;
        }
        if (prev == 0xFF && b == 0xFE) || (prev == 0xFE && b == 0xFF) {
            return true;
        }
        prev = b;
    }
    false
}

fn encoding_is_safe(b: &[u8]) -> bool {
    let n = b.len();
    let mut i = 0;
    if n >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF {
        i = 3;
    }
    while i < n && is_xml_space(b[i]) {
        i += 1;
    }
    if i >= n {
        return true;
    }
    if b[i] != 0x3C {
        return false;
    }
    if !matches_at(b, XML_DECL, i) || i + XML_DECL.len() >= n || !is_xml_space(b[i + XML_DECL.len()]) {
        return true;
    }
    let Some(end) = find(b, DECL_END, i + XML_DECL.len()) else {
        return false;
    };
    let mut k = i + XML_DECL.len();
    while let Some(at) = find(b, ENCODING_NAME, k) {
        if at >= end {
            break;
        }
        k = at + ENCODING_NAME.len();
        let mut j = k;
        while j < end && is_xml_space(b[j]) {
            j += 1;
        }
        if j >= end || b[j] != b'=' {
            return false;
        }
        j += 1;
        while j < end && is_xml_space(b[j]) {
            j += 1;
        }
        if j >= end || (b[j] != b'"' && b[j] != b'\'') {
            return false;
        }
        let quote = b[j];
        let start = j + 1;
        let mut v = start;
        while v < end && b[v] != quote {
            v += 1;
        }
        if v >= end {
            return false;
        }
        let enc = &b[start..v];
        if !ALLOWED_ENCODINGS.iter().any(|&allowed| allowed == enc) {
            return false;
        }
        k = v + 1;
    }
    true
}

fn is_xml_space(b: u8) -> bool {
    matches!(b, 0x20 | 0x09 | 0x0A | 0x0D)
}

fn is_name_byte(b: u8) -> bool {
    (b >= 0x61 && b <= 0x7A)
        || (b >= 0x30 && b <= 0x39)
        || matches!(b, b'_' | b'-' | b'.' | b':')
        || b >= 0x80
}

fn starts_with_data(b: &[u8], i: usize) -> bool {
    matches_at(b, DATA_SCHEME, i)
}

fn has_prefixed_active_element(b: &[u8]) -> bool {
    let n = b.len();
    let mut i = 0;
    while i < n {
        if b[i] != b'<' {
            i += 1;
            continue;
        }
        let mut k = i + 1;
        while k < n && !is_xml_space(b[k]) && b[k] != b'/' && b[k] != b'>' && b[k] != b'<' {
            if b[k] == b':' {
                for name in ACTIVE_ELEMENTS {
                    if matches_at(b, name, k + 1) {
                        return true;
                    }
                }
            }
            k += 1;
        }
        i = k;
    }
    false
}

fn css_urls_are_safe(b: &[u8]) -> bool {
    let n = b.len();
    let mut i = 0;
    while let Some(at) = find(b, URL_OPEN, i) {
        let mut j = at + URL_OPEN.len();
        while j < n && is_xml_space(b[j]) {
            j += 1;
        }
        if j < n && (b[j] == b'"' || b[j] == b'\'') {
            j += 1;
        }
        while j < n && is_xml_space(b[j]) {
            j += 1;
        }
        if j >= n || (b[j] != b'#' && !starts_with_data(b, j)) {
            return false;
        }
        i = at + URL_OPEN.len();
    }
    true
}

fn hrefs_are_safe(b: &[u8]) -> bool {
    let n = b.len();
    let last_double = b.iter().rposition(|&x| x == b'"');
    let last_single = b.iter().rposition(|&x| x == b'\'');
    let mut i = 0;
    while let Some(at) = find(b, HREF, i) {
        i = at + HREF.len();
        if !is_attribute_name(b, at) {
            continue;
        }
        let mut j = i;
        while j < n && is_xml_space(b[j]) {
            j += 1;
        }
        if j >= n || b[j] != b'=' {
            continue;
        }
        j += 1;
        while j < n && is_xml_space(b[j]) {
            j += 1;
        }
        if j >= n {
            return false;
        }
        let first = b[j];
        if first == b'"' || first == b'\'' {
            let last_quote = if first == b'"' { last_double } else { last_single };
            if !matches!(last_quote, Some(lq) if lq > j) {
                return false;
            }
            j += 1;
            while j < n && is_xml_space(b[j]) {
                j += 1;
            }
            if j >= n || b[j] == first {
                return false;
            }
        }
        if b[j] == b'>' {
            return false;
        }
        if b[j] != b'#' && !starts_with_data(b, j) {
            return false;
        }
    }
    true
}

fn is_attribute_name(b: &[u8], href_at: usize) -> bool {
    if href_at == 0 {
        return true;
    }
    let prev = b[href_at - 1];
    prev == b':' || !is_name_byte(prev)
}

fn matches_at(b: &[u8], needle: &[u8], i: usize) -> bool {
    i + needle.len() <= b.len() && &b[i..i + needle.len()] == needle
}

fn find(hay: &[u8], needle: &[u8], start: usize) -> Option<usize> {
    let n = hay.len();
    let m = needle.len();
    if m == 0 || n < m || start > n - m {
        return None;
    }
    let first = needle[0];
    let mut i = start;
    let last = n - m;
    while i <= last {
        if hay[i] == first && &hay[i..i + m] == needle {
            return Some(i);
        }
        i += 1;
    }
    None
}
