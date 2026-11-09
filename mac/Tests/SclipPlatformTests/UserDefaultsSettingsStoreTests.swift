import Foundation
import SclipCore
import SclipPlatform
import XCTest

final class UserDefaultsSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.erenkirkil.sclip.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRoundTripsEachSettingKey() {
        let store = UserDefaultsSettingsStore(defaults: defaults)

        for key in SettingKey.allCases {
            XCTAssertNil(store.value(key), "Expected nil initially for \(key)")
        }

        let samples: [(SettingKey, SettingValue)] = [
            (.toggleHotkey, .string("command+shift:9")),
            (.themeMode, .string("dark")),
            (.maxItems, .int(50)),
            (.sensitiveFilter, .bool(false)),
            (.clearOnScreenLock, .bool(false)),
            (.autoHideOnBlur, .bool(true)),
            (.alwaysOnTopDefault, .bool(true)),
            (.pollingIntervalMs, .int(500)),
            (.clearOnStartup, .bool(true)),
            (.alwaysPastePlainText, .bool(true)),
        ]

        XCTAssertEqual(Set(samples.map(\.0)), Set(SettingKey.allCases))

        for (key, value) in samples {
            store.set(value, for: key)
            XCTAssertEqual(store.value(key), value, "Round-trip failed for \(key)")
        }

        store.removeAll()
        for key in SettingKey.allCases {
            XCTAssertNil(store.value(key), "Expected nil after removeAll for \(key)")
        }
    }

    func testIgnoresUnknownKeys() {
        let store = UserDefaultsSettingsStore(defaults: defaults)

        // Write an unrelated key directly into UserDefaults
        defaults.set("unrelated", forKey: "some.foreign.key")
        // Write wrong value types under known keys
        defaults.set(12345, forKey: SettingKey.toggleHotkey.rawValue)
        defaults.set("not-an-int", forKey: SettingKey.maxItems.rawValue)
        defaults.set("not-a-bool", forKey: SettingKey.sensitiveFilter.rawValue)

        XCTAssertNil(store.value(.toggleHotkey))
        XCTAssertNil(store.value(.maxItems))
        XCTAssertNil(store.value(.sensitiveFilter))

        store.removeAll()
        // Unrelated key in the same UserDefaults domain should remain untouched by removeAll()
        XCTAssertEqual(defaults.string(forKey: "some.foreign.key"), "unrelated")
    }
}
