import Foundation

/// B-6.6.12, B-8.5.1: Ayar deposunun kabul ettigi tek anahtar kumesi.
public enum SettingKey: String, Sendable, CaseIterable {
    case toggleHotkey = "sclip.settings.toggleHotkey"
    case themeMode = "sclip.settings.themeMode"
    case maxItems = "sclip.settings.maxItems"
    case sensitiveFilter = "sclip.settings.sensitiveFilter"
    case clearOnScreenLock = "sclip.settings.clearOnScreenLock"
    case autoHideOnBlur = "sclip.settings.autoHideOnBlur"
    case alwaysOnTopDefault = "sclip.settings.alwaysOnTopDefault"
    case pollingIntervalMs = "sclip.settings.pollingIntervalMs"
    case clearOnStartup = "sclip.settings.clearOnStartup"
    case alwaysPastePlainText = "sclip.settings.alwaysPastePlainText"
}

public enum SettingValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case string(String)
}

public enum ThemeMode: String, Sendable, CaseIterable {
    case system
    case light
    case dark
}
