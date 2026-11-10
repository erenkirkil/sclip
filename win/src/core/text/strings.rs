use std::collections::HashMap;
use std::fmt;
use std::fs;
use std::ops::Index;
use std::path::Path;

use crate::core::text::{JsonValue, StringKey};

const EMBEDDED_TR_JSON: &str = include_str!("../../../../spec/strings.tr.json");

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StringsError {
    Io(String),
    InvalidJson(String),
}

impl fmt::Display for StringsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io(s) => write!(f, "IO error: {}", s),
            Self::InvalidJson(s) => write!(f, "Invalid strings JSON: {}", s),
        }
    }
}

impl std::error::Error for StringsError {}

#[derive(Debug, Clone)]
pub struct Strings {
    table: HashMap<String, String>,
}

impl Default for Strings {
    fn default() -> Self {
        Self::load_bundled()
    }
}

impl Strings {
    pub fn new(table: HashMap<String, String>) -> Self {
        Self { table }
    }

    pub fn empty() -> Self {
        Self {
            table: HashMap::new(),
        }
    }

    pub fn load<P: AsRef<Path>>(path: P) -> Result<Self, StringsError> {
        let content = fs::read_to_string(path.as_ref()).map_err(|e| StringsError::Io(e.to_string()))?;
        Self::from_json_str(&content)
    }

    pub fn load_bundled() -> Self {
        Self::from_json_str(EMBEDDED_TR_JSON).unwrap_or_else(|_| Self::empty())
    }

    pub fn from_json_bytes(bytes: &[u8]) -> Result<Self, StringsError> {
        let s = std::str::from_utf8(bytes).map_err(|e| StringsError::InvalidJson(e.to_string()))?;
        Self::from_json_str(s)
    }

    pub fn from_json_str(content: &str) -> Result<Self, StringsError> {
        let parsed = JsonValue::parse(content).map_err(|e| StringsError::InvalidJson(e.to_string()))?;
        let obj = parsed
            .as_object()
            .ok_or_else(|| StringsError::InvalidJson("root is not an object".to_string()))?;
        let mut table = HashMap::with_capacity(obj.len());
        for (k, v) in obj {
            let s = v
                .as_str()
                .ok_or_else(|| StringsError::InvalidJson(format!("non-string value for key {}", k)))?;
            table.insert(k.clone(), s.to_string());
        }
        Ok(Self { table })
    }

    pub fn get(&self, key: StringKey) -> &str {
        let raw = key.raw_value();
        self.table.get(raw).map(|s| s.as_str()).unwrap_or(raw)
    }

    /// Single-pass `{name}` placeholder substitution (`Strings.swift`).
    pub fn format(&self, key: StringKey, args: &[(&str, &str)]) -> String {
        Self::substitute(self.get(key), args)
    }

    pub fn substitute(template: &str, args: &[(&str, &str)]) -> String {
        let mut result = String::with_capacity(template.len());
        let mut rest = template;
        while let Some(open) = rest.find('{') {
            result.push_str(&rest[..open]);
            let after_open = &rest[open + 1..];
            let Some(close) = after_open.find('}') else {
                rest = &rest[open..];
                break;
            };
            let name = &after_open[..close];
            if name.contains('{') {
                result.push('{');
                rest = after_open;
                continue;
            }
            if let Some((_, val)) = args.iter().find(|(k, _)| *k == name) {
                result.push_str(val);
            } else {
                result.push('{');
                result.push_str(name);
                result.push('}');
            }
            rest = &after_open[close + 1..];
        }
        result.push_str(rest);
        result
    }

    /// Turkish locale-aware uppercase conversion (`B-6.6.2`).
    pub fn tr_upper(input: &str) -> String {
        let mut out = String::with_capacity(input.len());
        for ch in input.chars() {
            match ch {
                'i' => out.push('\u{0130}'),
                '\u{0131}' => out.push('I'),
                '\u{015F}' => out.push('\u{015E}'),
                '\u{011F}' => out.push('\u{011E}'),
                '\u{00FC}' => out.push('\u{00DC}'),
                '\u{00F6}' => out.push('\u{00D6}'),
                '\u{00E7}' => out.push('\u{00C7}'),
                _ => {
                    for u in ch.to_uppercase() {
                        out.push(u);
                    }
                }
            }
        }
        out
    }
}

impl Index<StringKey> for Strings {
    type Output = str;

    fn index(&self, key: StringKey) -> &Self::Output {
        self.get(key)
    }
}
