/// Filename extraction (`behavior.md` `B-6.4.6`).
pub struct FileName;

impl FileName {
    pub fn local_path(url_or_path: &str) -> String {
        if let Some(rest) = strip_ascii_prefix_ci(url_or_path, "file://") {
            let after_host = if let Some(stripped) = strip_ascii_prefix_ci(rest, "localhost") {
                if stripped.starts_with('/') {
                    stripped
                } else {
                    rest
                }
            } else {
                rest
            };
            percent_decode(after_host)
        } else {
            url_or_path.to_string()
        }
    }

    pub fn basename(url_or_path: &str) -> String {
        if strip_ascii_prefix_ci(url_or_path, "file://").is_some() {
            let path = Self::local_path(url_or_path);
            Self::basename_path(&path)
        } else {
            Self::basename_path(url_or_path)
        }
    }

    /// Strips trailing `/` and `\`, returns last component; if nothing remains, returns full `path`.
    pub fn basename_path(path: &str) -> String {
        let units: Vec<u16> = path.encode_utf16().collect();
        let is_sep = |u: u16| u == 0x2F || u == 0x5C;
        let Some(last) = units.iter().rposition(|&u| !is_sep(u)) else {
            return path.to_string();
        };
        let start = units[..=last]
            .iter()
            .rposition(|&u| is_sep(u))
            .map(|i| i + 1)
            .unwrap_or(0);
        String::from_utf16_lossy(&units[start..=last])
    }
}

fn strip_ascii_prefix_ci<'a>(s: &'a str, prefix: &str) -> Option<&'a str> {
    if s.len() < prefix.len() {
        return None;
    }
    let head = &s.as_bytes()[..prefix.len()];
    for (&a, &b) in head.iter().zip(prefix.as_bytes().iter()) {
        if !a.eq_ignore_ascii_case(&b) {
            return None;
        }
    }
    s.get(prefix.len()..)
}

fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(hi), Some(lo)) = (hex_val(bytes[i + 1]), hex_val(bytes[i + 2])) {
                out.push((hi << 4) | lo);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}
