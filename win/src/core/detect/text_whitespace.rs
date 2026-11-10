/// Normative whitespace sets and helpers (`B-6.4.5`, `B-8.2.x`).
pub struct TextWhitespace;

impl TextWhitespace {
    pub fn is_collapse_set(scalar: u32) -> bool {
        match scalar {
            0x09..=0x0D => true,
            0x20 | 0xA0 | 0x1680 => true,
            0x2000..=0x200A => true,
            0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000 | 0xFEFF => true,
            _ => false,
        }
    }

    pub fn is_trim_set(scalar: u32) -> bool {
        scalar == 0x85 || Self::is_collapse_set(scalar)
    }

    pub fn collapse(s: &str) -> String {
        let mut out = String::with_capacity(s.len());
        let mut in_space = false;
        for ch in s.chars() {
            if Self::is_collapse_set(ch as u32) {
                if !in_space {
                    out.push(' ');
                    in_space = true;
                }
            } else {
                in_space = false;
                out.push(ch);
            }
        }
        out
    }

    pub fn trim(s: &str) -> String {
        let trimmed_start = s.trim_start_matches(|ch: char| Self::is_trim_set(ch as u32));
        let trimmed = trimmed_start.trim_end_matches(|ch: char| Self::is_trim_set(ch as u32));
        trimmed.to_string()
    }

    pub fn trim_leading(s: &str) -> String {
        s.trim_start_matches(|ch: char| Self::is_trim_set(ch as u32))
            .to_string()
    }

    pub fn ascii_lowercased(s: &str) -> String {
        let mut out = String::with_capacity(s.len());
        for ch in s.chars() {
            out.push(ch.to_ascii_lowercase());
        }
        out
    }
}
