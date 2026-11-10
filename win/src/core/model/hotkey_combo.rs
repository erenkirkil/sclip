use std::collections::BTreeSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Modifier {
    Command,
    Control,
    Option,
    Shift,
}

impl Modifier {
    pub const ALL: &'static [Modifier] = &[
        Self::Command,
        Self::Control,
        Self::Option,
        Self::Shift,
    ];

    pub fn raw_value(self) -> &'static str {
        match self {
            Self::Command => "command",
            Self::Control => "control",
            Self::Option => "option",
            Self::Shift => "shift",
        }
    }

    pub fn from_raw(raw: &str) -> Option<Self> {
        match raw {
            "command" => Some(Self::Command),
            "control" => Some(Self::Control),
            "option" => Some(Self::Option),
            "shift" => Some(Self::Shift),
            _ => None,
        }
    }
}

/// Global shortcut combination (`B-6.6.3`, `B-6.6.15`, `B-6.8.1`).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct HotkeyCombo {
    pub modifiers: BTreeSet<Modifier>,
    pub key_code: u16,
}

impl HotkeyCombo {
    pub const V_KEY_CODE: u16 = 9;

    pub fn new<I>(modifiers: I, key_code: u16) -> Self
    where
        I: IntoIterator<Item = Modifier>,
    {
        Self {
            modifiers: modifiers.into_iter().collect(),
            key_code,
        }
    }

    /// `B-6.8.1`: macOS default fallback chain (`Cmd+Shift+V`, `Cmd+Opt+V`, `Ctrl+Cmd+V`).
    pub fn mac_defaults() -> Vec<HotkeyCombo> {
        vec![
            HotkeyCombo::new([Modifier::Command, Modifier::Shift], Self::V_KEY_CODE),
            HotkeyCombo::new([Modifier::Command, Modifier::Option], Self::V_KEY_CODE),
            HotkeyCombo::new([Modifier::Control, Modifier::Command], Self::V_KEY_CODE),
        ]
    }

    /// `B-6.8.1`: Windows default fallback chain (`Alt+Shift+V`, `Ctrl+Alt+V`, `Ctrl+Shift+V`).
    pub fn win_defaults() -> Vec<HotkeyCombo> {
        vec![
            HotkeyCombo::new([Modifier::Option, Modifier::Shift], Self::V_KEY_CODE),
            HotkeyCombo::new([Modifier::Control, Modifier::Option], Self::V_KEY_CODE),
            HotkeyCombo::new([Modifier::Control, Modifier::Shift], Self::V_KEY_CODE),
        ]
    }

    /// `B-6.6.15`: at least 2 modifiers required.
    pub fn is_valid(&self) -> bool {
        self.modifiers.len() >= 2
    }

    /// Canonical storage format: `"command+shift:9"` in `Modifier::ALL` order.
    pub fn storage_string(&self) -> String {
        let mod_part: Vec<&str> = Modifier::ALL
            .iter()
            .copied()
            .filter(|m| self.modifiers.contains(m))
            .map(|m| m.raw_value())
            .collect();
        format!("{}:{}", mod_part.join("+"), self.key_code)
    }

    pub fn from_storage_string(storage_string: &str) -> Option<Self> {
        let parts: Vec<&str> = storage_string.split(':').collect();
        if parts.len() != 2 || parts[0].is_empty() {
            return None;
        }
        let code = parts[1].parse::<u16>().ok()?;
        let mut parsed = BTreeSet::new();
        for token in parts[0].split('+') {
            let m = Modifier::from_raw(token)?;
            if !parsed.insert(m) {
                return None;
            }
        }
        let combo = Self::new(parsed, code);
        if combo.is_valid() {
            Some(combo)
        } else {
            None
        }
    }
}
