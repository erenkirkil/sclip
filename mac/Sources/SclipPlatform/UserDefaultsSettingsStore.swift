import CoreFoundation
import Foundation
import SclipCore

public final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func value(_ k: SettingKey) -> SettingValue? {
        guard let raw = defaults.object(forKey: k.rawValue) else {
            return nil
        }

        switch k {
        case .toggleHotkey, .themeMode:
            guard let str = raw as? String else { return nil }
            return .string(str)

        case .maxItems, .pollingIntervalMs:
            guard let num = raw as? NSNumber,
                  CFGetTypeID(num) != CFBooleanGetTypeID()
            else {
                return nil
            }
            return .int(num.intValue)

        case .sensitiveFilter,
             .clearOnScreenLock,
             .autoHideOnBlur,
             .alwaysOnTopDefault,
             .clearOnStartup,
             .alwaysPastePlainText:
            guard let num = raw as? NSNumber,
                  CFGetTypeID(num) == CFBooleanGetTypeID()
            else {
                return nil
            }
            return .bool(num.boolValue)
        }
    }

    public func set(_ v: SettingValue, for k: SettingKey) {
        switch v {
        case let .bool(b):
            defaults.set(b, forKey: k.rawValue)
        case let .int(n):
            defaults.set(n, forKey: k.rawValue)
        case let .string(s):
            defaults.set(s, forKey: k.rawValue)
        }
    }

    public func removeAll() {
        for key in SettingKey.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
