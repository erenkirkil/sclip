/// Email (`mailto:`) and phone (`tel:`) detectors (`B-8.2.6`, `B-8.2.7`).
pub struct ContactDetector;

impl ContactDetector {
    pub fn mailto(trimmed: &str) -> Option<String> {
        let (local, domain) = trimmed.split_once('@')?;
        if domain.contains('@') || local.is_empty() || domain.is_empty() {
            return None;
        }
        if !local.bytes().all(is_local_char) {
            return None;
        }
        let labels: Vec<&str> = domain.split('.').collect();
        if labels.len() < 2 {
            return None;
        }
        for &label in &labels[..labels.len() - 1] {
            if label.is_empty() || !label.bytes().all(is_domain_char) {
                return None;
            }
        }
        let tld = labels[labels.len() - 1];
        if tld.len() < 2 || !tld.bytes().all(|b| b.is_ascii_alphabetic()) {
            return None;
        }
        Some(format!("mailto:{}", trimmed))
    }

    pub fn tel(trimmed: &str) -> Option<String> {
        let bytes = trimmed.as_bytes();
        if bytes.len() < 8 || bytes[0] != b'+' {
            return None;
        }
        if !matches!(bytes[1], b'1'..=b'9') {
            return None;
        }
        let tail = &bytes[2..];
        if tail.len() < 6 || tail.len() > 18 {
            return None;
        }
        let mut digits = String::with_capacity(16);
        digits.push(bytes[1] as char);
        for &b in tail {
            match b {
                b'0'..=b'9' => digits.push(b as char),
                b' ' | b'(' | b')' | b'.' | b'-' => {}
                _ => return None,
            }
        }
        if !(8..=15).contains(&digits.len()) {
            return None;
        }
        Some(format!("tel:+{}", digits))
    }
}

fn is_local_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'%' | b'+' | b'-')
}

fn is_domain_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'-'
}
