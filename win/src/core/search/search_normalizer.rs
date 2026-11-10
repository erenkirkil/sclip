/// Search normalization (`behavior.md` `B-6.5.3`). All steps operate on Unicode scalars.
pub struct SearchNormalizer;

impl SearchNormalizer {
    pub fn normalize(s: &str) -> String {
        let mut out = String::with_capacity(s.len());
        let mut pending_space = false;
        for scalar in s.chars() {
            if matches!(scalar, 'I' | '\u{0130}' | '\u{0131}') {
                if pending_space {
                    if !out.is_empty() {
                        out.push(' ');
                    }
                    pending_space = false;
                }
                out.push('i');
                continue;
            }
            for lowered in scalar.to_lowercase() {
                if is_search_space(lowered as u32) {
                    pending_space = true;
                    continue;
                }
                if pending_space {
                    if !out.is_empty() {
                        out.push(' ');
                    }
                    pending_space = false;
                }
                out.push(fold(lowered));
            }
        }
        out
    }
}

fn is_search_space(v: u32) -> bool {
    v == 0x20 || (0x09..=0x0D).contains(&v) || v == 0xA0
}

fn fold(u: char) -> char {
    match u {
        '\u{015F}' => 's',
        '\u{011F}' => 'g',
        '\u{00FC}' | '\u{00FB}' => 'u',
        '\u{00F6}' => 'o',
        '\u{00E7}' => 'c',
        '\u{00E2}' => 'a',
        '\u{00EE}' => 'i',
        _ => u,
    }
}
