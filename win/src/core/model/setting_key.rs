/// `B-6.6.12`, `B-8.5.1`: Exclusive set of keys accepted by the settings store.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum SettingKey {
    ToggleHotkey,
    ThemeMode,
    MaxItems,
    SensitiveFilter,
    ClearOnScreenLock,
    AutoHideOnBlur,
    AlwaysOnTopDefault,
    PollingIntervalMs,
    ClearOnStartup,
    AlwaysPastePlainText,
}

impl SettingKey {
    pub const ALL: &'static [SettingKey] = &[
        Self::ToggleHotkey,
        Self::ThemeMode,
        Self::MaxItems,
        Self::SensitiveFilter,
        Self::ClearOnScreenLock,
        Self::AutoHideOnBlur,
        Self::AlwaysOnTopDefault,
        Self::PollingIntervalMs,
        Self::ClearOnStartup,
        Self::AlwaysPastePlainText,
    ];

    pub fn raw_value(self) -> &'static str {
        match self {
            Self::ToggleHotkey => "sclip.settings.toggleHotkey",
            Self::ThemeMode => "sclip.settings.themeMode",
            Self::MaxItems => "sclip.settings.maxItems",
            Self::SensitiveFilter => "sclip.settings.sensitiveFilter",
            Self::ClearOnScreenLock => "sclip.settings.clearOnScreenLock",
            Self::AutoHideOnBlur => "sclip.settings.autoHideOnBlur",
            Self::AlwaysOnTopDefault => "sclip.settings.alwaysOnTopDefault",
            Self::PollingIntervalMs => "sclip.settings.pollingIntervalMs",
            Self::ClearOnStartup => "sclip.settings.clearOnStartup",
            Self::AlwaysPastePlainText => "sclip.settings.alwaysPastePlainText",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SettingValue {
    Bool(bool),
    Int(i64),
    String(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ThemeMode {
    System,
    Light,
    Dark,
}

impl ThemeMode {
    pub const ALL: &'static [ThemeMode] = &[Self::System, Self::Light, Self::Dark];

    pub fn raw_value(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::Light => "light",
            Self::Dark => "dark",
        }
    }

    pub fn from_raw(raw: &str) -> Option<Self> {
        match raw {
            "system" => Some(Self::System),
            "light" => Some(Self::Light),
            "dark" => Some(Self::Dark),
            _ => None,
        }
    }
}
