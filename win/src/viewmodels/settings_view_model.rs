use std::rc::Rc;

use crate::core::model::{HotkeyCombo, SettingKey, SettingValue, ThemeMode};
use crate::core::ports::{HotkeyRegistrar, SettingsStore};
use crate::core::text::StringKey;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Platform {
    Windows,
    Mac,
}

/// Settings view model (`B-6.6.1`..`B-6.6.16`, `B-6.8.1`..`B-6.8.5`, `E11`, `E12`, `E15`).
pub struct SettingsViewModel {
    pub registered_hotkey: Option<HotkeyCombo>,
    pub hotkey_error: Option<StringKey>,
    theme_mode: ThemeMode,
    max_items: usize,
    sensitive_filter: bool,
    clear_on_screen_lock: bool,
    auto_hide_on_blur: bool,
    always_on_top_default: bool,
    polling_interval_ms: usize,
    clear_on_startup: bool,
    always_paste_plain_text: bool,

    store: Rc<dyn SettingsStore>,
    hotkeys: Rc<dyn HotkeyRegistrar>,
    platform: Platform,
    suppress_persistence: bool,
}

impl SettingsViewModel {
    pub const ALLOWED_MAX_ITEMS: &'static [usize] = &[10, 30, 50, 100];
    pub const DEFAULT_MAX_ITEMS: usize = 30;
    pub const ALLOWED_POLLING_INTERVALS: &'static [usize] = &[250, 500, 1000];
    pub const DEFAULT_POLLING_INTERVAL_MS: usize = 250;

    pub fn new(store: Rc<dyn SettingsStore>, hotkeys: Rc<dyn HotkeyRegistrar>) -> Self {
        Self::with_platform(store, hotkeys, Platform::Windows)
    }

    pub fn with_platform(
        store: Rc<dyn SettingsStore>,
        hotkeys: Rc<dyn HotkeyRegistrar>,
        platform: Platform,
    ) -> Self {
        let theme_mode = Self::read_theme_mode(store.as_ref());
        let max_items = Self::read_allowed_int(
            store.as_ref(),
            SettingKey::MaxItems,
            Self::ALLOWED_MAX_ITEMS,
            Self::DEFAULT_MAX_ITEMS,
        );
        let sensitive_filter = Self::read_bool(store.as_ref(), SettingKey::SensitiveFilter, true);
        let clear_on_screen_lock =
            Self::read_bool(store.as_ref(), SettingKey::ClearOnScreenLock, false);
        let auto_hide_on_blur = Self::read_bool(store.as_ref(), SettingKey::AutoHideOnBlur, true);
        let always_on_top_default =
            Self::read_bool(store.as_ref(), SettingKey::AlwaysOnTopDefault, false);
        let polling_interval_ms = Self::read_allowed_int(
            store.as_ref(),
            SettingKey::PollingIntervalMs,
            Self::ALLOWED_POLLING_INTERVALS,
            Self::DEFAULT_POLLING_INTERVAL_MS,
        );
        let clear_on_startup = Self::read_bool(store.as_ref(), SettingKey::ClearOnStartup, false);
        let always_paste_plain_text =
            Self::read_bool(store.as_ref(), SettingKey::AlwaysPastePlainText, false);

        Self {
            registered_hotkey: None,
            hotkey_error: None,
            theme_mode,
            max_items,
            sensitive_filter,
            clear_on_screen_lock,
            auto_hide_on_blur,
            always_on_top_default,
            polling_interval_ms,
            clear_on_startup,
            always_paste_plain_text,
            store,
            hotkeys,
            platform,
            suppress_persistence: false,
        }
    }

    pub fn theme_mode(&self) -> ThemeMode {
        self.theme_mode
    }

    pub fn set_theme_mode(&mut self, mode: ThemeMode) {
        self.theme_mode = mode;
        self.persist(
            SettingValue::String(mode.raw_value().to_string()),
            SettingKey::ThemeMode,
        );
    }

    pub fn max_items(&self) -> usize {
        self.max_items
    }

    pub fn set_max_items(&mut self, value: usize) {
        if !Self::ALLOWED_MAX_ITEMS.contains(&value) {
            self.max_items = Self::DEFAULT_MAX_ITEMS;
            return;
        }
        self.max_items = value;
        self.persist(SettingValue::Int(value as i64), SettingKey::MaxItems);
    }

    pub fn sensitive_filter(&self) -> bool {
        self.sensitive_filter
    }

    pub fn set_sensitive_filter(&mut self, value: bool) {
        self.sensitive_filter = value;
        self.persist(SettingValue::Bool(value), SettingKey::SensitiveFilter);
    }

    pub fn clear_on_screen_lock(&self) -> bool {
        self.clear_on_screen_lock
    }

    pub fn set_clear_on_screen_lock(&mut self, value: bool) {
        self.clear_on_screen_lock = value;
        self.persist(SettingValue::Bool(value), SettingKey::ClearOnScreenLock);
    }

    pub fn auto_hide_on_blur(&self) -> bool {
        self.auto_hide_on_blur
    }

    pub fn set_auto_hide_on_blur(&mut self, value: bool) {
        self.auto_hide_on_blur = value;
        self.persist(SettingValue::Bool(value), SettingKey::AutoHideOnBlur);
    }

    pub fn always_on_top_default(&self) -> bool {
        self.always_on_top_default
    }

    pub fn set_always_on_top_default(&mut self, value: bool) {
        self.always_on_top_default = value;
        self.persist(SettingValue::Bool(value), SettingKey::AlwaysOnTopDefault);
    }

    pub fn polling_interval_ms(&self) -> usize {
        self.polling_interval_ms
    }

    pub fn set_polling_interval_ms(&mut self, value: usize) {
        if !Self::ALLOWED_POLLING_INTERVALS.contains(&value) {
            self.polling_interval_ms = Self::DEFAULT_POLLING_INTERVAL_MS;
            return;
        }
        self.polling_interval_ms = value;
        self.persist(
            SettingValue::Int(value as i64),
            SettingKey::PollingIntervalMs,
        );
    }

    pub fn clear_on_startup(&self) -> bool {
        self.clear_on_startup
    }

    pub fn set_clear_on_startup(&mut self, value: bool) {
        self.clear_on_startup = value;
        self.persist(SettingValue::Bool(value), SettingKey::ClearOnStartup);
    }

    pub fn always_paste_plain_text(&self) -> bool {
        self.always_paste_plain_text
    }

    pub fn set_always_paste_plain_text(&mut self, value: bool) {
        self.always_paste_plain_text = value;
        self.persist(SettingValue::Bool(value), SettingKey::AlwaysPastePlainText);
    }

    pub fn default_hotkeys(&self) -> Vec<HotkeyCombo> {
        match self.platform {
            Platform::Windows => HotkeyCombo::win_defaults(),
            Platform::Mac => HotkeyCombo::mac_defaults(),
        }
    }

    /// `B-6.8.1`, `B-6.8.4`: tries stored preference -> platform defaults in order; first to succeed becomes `registered_hotkey`.
    pub fn register_initial_hotkey(&mut self) {
        let mut candidates = Vec::new();
        if let Some(SettingValue::String(raw)) = self.store.value(SettingKey::ToggleHotkey) {
            if let Some(stored) = HotkeyCombo::from_storage_string(&raw) {
                candidates.push(stored);
            }
        }
        for fallback in self.default_hotkeys() {
            if !candidates.contains(&fallback) {
                candidates.push(fallback);
            }
        }
        for candidate in candidates {
            if self.hotkeys.register(&candidate) {
                self.registered_hotkey = Some(candidate);
                self.hotkey_error = None;
                return;
            }
        }
        self.registered_hotkey = None;
    }

    /// `B-6.6.3`, `B-6.6.15`, `B-6.8.2`, `B-6.8.5`: requires >= 2 modifiers; restores previous on registration failure.
    pub fn change_hotkey(&mut self, combo: &HotkeyCombo) -> bool {
        if !combo.is_valid() {
            self.hotkey_error = Some(StringKey::SettingsHotkeyErrorMinModifiers);
            return false;
        }
        let previous = self.registered_hotkey.clone();
        if previous.is_some() {
            self.hotkeys.unregister();
        }
        if self.hotkeys.register(combo) {
            self.registered_hotkey = Some(combo.clone());
            self.hotkey_error = None;
            self.store.set(
                SettingValue::String(combo.storage_string()),
                SettingKey::ToggleHotkey,
            );
            return true;
        }
        if let Some(prev) = previous {
            if self.hotkeys.register(&prev) {
                self.registered_hotkey = Some(prev);
            } else {
                self.registered_hotkey = None;
            }
        } else {
            self.registered_hotkey = None;
        }
        if self.platform == Platform::Windows {
            self.hotkey_error = Some(StringKey::SettingsHotkeyErrorInUse);
        }
        false
    }

    pub fn begin_recording(&self) {
        self.hotkeys.suspend();
    }

    pub fn end_recording(&self) {
        self.hotkeys.resume();
    }

    /// `B-6.6.13`, `E11`: resets all settings to defaults and re-registers the default hotkey chain.
    pub fn reset_to_defaults(&mut self) -> bool {
        self.suppress_persistence = true;
        self.store.remove_all();
        self.theme_mode = ThemeMode::System;
        self.max_items = Self::DEFAULT_MAX_ITEMS;
        self.sensitive_filter = true;
        self.clear_on_screen_lock = false;
        self.auto_hide_on_blur = true;
        self.always_on_top_default = false;
        self.polling_interval_ms = Self::DEFAULT_POLLING_INTERVAL_MS;
        self.clear_on_startup = false;
        self.always_paste_plain_text = false;
        self.hotkey_error = None;
        self.suppress_persistence = false;

        self.hotkeys.unregister();
        self.register_initial_hotkey();
        self.registered_hotkey.is_some()
    }

    fn persist(&self, value: SettingValue, key: SettingKey) {
        if !self.suppress_persistence {
            self.store.set(value, key);
        }
    }

    fn read_bool(store: &dyn SettingsStore, key: SettingKey, fallback: bool) -> bool {
        match store.value(key) {
            Some(SettingValue::Bool(v)) => v,
            _ => fallback,
        }
    }

    fn read_allowed_int(
        store: &dyn SettingsStore,
        key: SettingKey,
        allowed: &[usize],
        fallback: usize,
    ) -> usize {
        match store.value(key) {
            Some(SettingValue::Int(v)) if v >= 0 && allowed.contains(&(v as usize)) => v as usize,
            _ => fallback,
        }
    }

    fn read_theme_mode(store: &dyn SettingsStore) -> ThemeMode {
        match store.value(SettingKey::ThemeMode) {
            Some(SettingValue::String(raw)) => {
                ThemeMode::from_raw(&raw).unwrap_or(ThemeMode::System)
            }
            _ => ThemeMode::System,
        }
    }
}
