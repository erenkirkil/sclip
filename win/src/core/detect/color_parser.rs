use crate::core::detect::TextWhitespace;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedColor {
    pub normalized: String,
    pub argb: u32,
}

impl ParsedColor {
    pub fn new(normalized: impl Into<String>, argb: u32) -> Self {
        Self {
            normalized: normalized.into(),
            argb,
        }
    }
}

/// CSS color parser (`behavior.md` `B-8.2.2`..`B-8.2.5`).
pub struct ColorParser;

impl ColorParser {
    pub fn parse(trimmed: &str) -> Option<ParsedColor> {
        let text = TextWhitespace::ascii_lowercased(trimmed);
        if let Some(hex_body) = text.strip_prefix('#') {
            let argb = parse_hex(hex_body)?;
            return Some(ParsedColor::new(text, argb));
        }
        if let Some(inner) = strip_func(&text, "rgba(").or_else(|| strip_func(&text, "rgb(")) {
            let argb = parse_rgb(inner)?;
            return Some(ParsedColor::new(text, argb));
        }
        if let Some(inner) = strip_func(&text, "hsla(").or_else(|| strip_func(&text, "hsl(")) {
            let argb = parse_hsl(inner)?;
            return Some(ParsedColor::new(text, argb));
        }
        None
    }
}

fn strip_func<'a>(s: &'a str, open: &str) -> Option<&'a str> {
    if s.starts_with(open) && s.ends_with(')') {
        Some(&s[open.len()..s.len() - 1])
    } else {
        None
    }
}

fn parse_hex(digits: &str) -> Option<u32> {
    let count = digits.len();
    if !matches!(count, 3 | 4 | 6 | 8) {
        return None;
    }
    if !digits.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    let expanded = if count <= 4 {
        let mut s = String::with_capacity(count * 2);
        for ch in digits.chars() {
            s.push(ch);
            s.push(ch);
        }
        s
    } else {
        digits.to_string()
    };
    let val = u32::from_str_radix(&expanded, 16).ok()?;
    if expanded.len() == 8 {
        Some((val << 24) | (val >> 8))
    } else {
        Some(0xFF00_0000 | val)
    }
}

fn split_args(body: &str) -> Vec<String> {
    body.split(',')
        .map(|part| {
            let trimmed_start =
                part.trim_start_matches(|ch: char| TextWhitespace::is_collapse_set(ch as u32));
            trimmed_start
                .trim_end_matches(|ch: char| TextWhitespace::is_collapse_set(ch as u32))
                .to_string()
        })
        .collect()
}

fn parse_rgb(body: &str) -> Option<u32> {
    let args = split_args(body);
    if args.len() != 3 && args.len() != 4 {
        return None;
    }
    let r = parse_channel_int(&args[0])?;
    let g = parse_channel_int(&args[1])?;
    let b = parse_channel_int(&args[2])?;
    let a = if args.len() == 4 {
        parse_alpha(&args[3])?
    } else {
        255
    };
    Some((a << 24) | (r << 16) | (g << 8) | b)
}

fn parse_hsl(body: &str) -> Option<u32> {
    let args = split_args(body);
    if args.len() != 3 && args.len() != 4 {
        return None;
    }
    let hue = parse_hue(&args[0])?;
    let sat = parse_percent(&args[1])?;
    let lig = parse_percent(&args[2])?;
    let a = if args.len() == 4 {
        parse_alpha(&args[3])?
    } else {
        255
    };
    let h = (hue % 360.0) / 360.0;
    let s = (sat / 100.0).clamp(0.0, 1.0);
    let l = (lig / 100.0).clamp(0.0, 1.0);
    let (r, g, b) = hsl_to_rgb(h, s, l);
    Some((a << 24) | (r << 16) | (g << 8) | b)
}

fn hsl_to_rgb(h: f64, s: f64, l: f64) -> (u32, u32, u32) {
    if s == 0.0 {
        let v = round_byte(l * 255.0);
        return (v, v, v);
    }
    let q = if l < 0.5 {
        l * (1.0 + s)
    } else {
        l + s - l * s
    };
    let p = 2.0 * l - q;
    let r = round_byte(hue_to_rgb(p, q, h + 1.0 / 3.0) * 255.0);
    let g = round_byte(hue_to_rgb(p, q, h) * 255.0);
    let b = round_byte(hue_to_rgb(p, q, h - 1.0 / 3.0) * 255.0);
    (r, g, b)
}

fn hue_to_rgb(p: f64, q: f64, mut t: f64) -> f64 {
    if t < 0.0 {
        t += 1.0;
    }
    if t > 1.0 {
        t -= 1.0;
    }
    if t < 1.0 / 6.0 {
        return p + (q - p) * 6.0 * t;
    }
    if t < 1.0 / 2.0 {
        return q;
    }
    if t < 2.0 / 3.0 {
        return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    }
    p
}

fn parse_channel_int(s: &str) -> Option<u32> {
    if s.is_empty() || s.len() > 3 || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let val = s.parse::<u32>().ok()?;
    Some(val.min(255))
}

fn parse_alpha(s: &str) -> Option<u32> {
    if s == "0" {
        return Some(0);
    }
    if s == "1" {
        return Some(255);
    }
    let frac = if let Some(rest) = s.strip_prefix("0.") {
        rest
    } else {
        s.strip_prefix('.')?
    };
    if frac.is_empty() || !frac.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let normalized = if s.starts_with('.') {
        format!("0{}", s)
    } else {
        s.to_string()
    };
    let val = normalized.parse::<f64>().ok()?;
    Some(round_byte(val * 255.0))
}

fn parse_hue(s: &str) -> Option<f64> {
    let num_str = s.strip_suffix("deg").unwrap_or(s);
    parse_3digit_float(num_str)
}

fn parse_percent(s: &str) -> Option<f64> {
    let num_str = s.strip_suffix('%')?;
    parse_3digit_float(num_str)
}

fn parse_3digit_float(s: &str) -> Option<f64> {
    if let Some((int_part, frac_part)) = s.split_once('.') {
        if int_part.is_empty()
            || int_part.len() > 3
            || !int_part.bytes().all(|b| b.is_ascii_digit())
            || frac_part.is_empty()
            || !frac_part.bytes().all(|b| b.is_ascii_digit())
        {
            return None;
        }
    } else if s.is_empty() || s.len() > 3 || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse::<f64>().ok()
}

fn round_byte(x: f64) -> u32 {
    let r = (x + 0.5).floor();
    if r <= 0.0 {
        0
    } else if r >= 255.0 {
        255
    } else {
        r as u32
    }
}
