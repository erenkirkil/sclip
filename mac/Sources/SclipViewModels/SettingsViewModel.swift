import Combine
import Foundation
import SclipCore

/// Ayarlar gorunum modeli (B-6.6.1 – B-6.6.16, B-6.8.1 – B-6.8.4, E11, E12, E15).
@MainActor
public final class SettingsViewModel: ObservableObject {
    public static let allowedMaxItems = [10, 30, 50, 100]
    public static let defaultMaxItems = 30
    public static let allowedPollingIntervals = [250, 500, 1000]
    public static let defaultPollingIntervalMs = 250

    @Published public private(set) var registeredHotkey: HotkeyCombo?
    @Published public var themeMode: ThemeMode {
        didSet { persist(.string(themeMode.rawValue), for: .themeMode) }
    }
    @Published public var maxItems: Int {
        didSet {
            if !Self.allowedMaxItems.contains(maxItems) {
                maxItems = Self.defaultMaxItems
                return
            }
            persist(.int(maxItems), for: .maxItems)
        }
    }
    @Published public var sensitiveFilter: Bool {
        didSet { persist(.bool(sensitiveFilter), for: .sensitiveFilter) }
    }
    @Published public var clearOnScreenLock: Bool {
        didSet { persist(.bool(clearOnScreenLock), for: .clearOnScreenLock) }
    }
    @Published public var autoHideOnBlur: Bool {
        didSet { persist(.bool(autoHideOnBlur), for: .autoHideOnBlur) }
    }
    @Published public var alwaysOnTopDefault: Bool {
        didSet { persist(.bool(alwaysOnTopDefault), for: .alwaysOnTopDefault) }
    }
    @Published public var pollingIntervalMs: Int {
        didSet {
            if !Self.allowedPollingIntervals.contains(pollingIntervalMs) {
                pollingIntervalMs = Self.defaultPollingIntervalMs
                return
            }
            persist(.int(pollingIntervalMs), for: .pollingIntervalMs)
        }
    }
    @Published public var clearOnStartup: Bool {
        didSet { persist(.bool(clearOnStartup), for: .clearOnStartup) }
    }
    @Published public var alwaysPastePlainText: Bool {
        didSet { persist(.bool(alwaysPastePlainText), for: .alwaysPastePlainText) }
    }

    private let store: SettingsStore
    private let hotkeys: HotkeyRegistrar
    private var suppressPersistence = false

    public init(store: SettingsStore, hotkeys: HotkeyRegistrar) {
        self.store = store
        self.hotkeys = hotkeys
        self.themeMode = Self.readThemeMode(from: store)
        self.maxItems = Self.readAllowedInt(
            from: store, key: .maxItems,
            allowed: Self.allowedMaxItems, fallback: Self.defaultMaxItems
        )
        self.sensitiveFilter = Self.readBool(from: store, key: .sensitiveFilter, fallback: true)
        self.clearOnScreenLock = Self.readBool(from: store, key: .clearOnScreenLock, fallback: false)
        self.autoHideOnBlur = Self.readBool(from: store, key: .autoHideOnBlur, fallback: true)
        self.alwaysOnTopDefault = Self.readBool(from: store, key: .alwaysOnTopDefault, fallback: false)
        self.pollingIntervalMs = Self.readAllowedInt(
            from: store, key: .pollingIntervalMs,
            allowed: Self.allowedPollingIntervals, fallback: Self.defaultPollingIntervalMs
        )
        self.clearOnStartup = Self.readBool(from: store, key: .clearOnStartup, fallback: false)
        self.alwaysPastePlainText = Self.readBool(
            from: store, key: .alwaysPastePlainText, fallback: false
        )
    }

    // MARK: - Hotkey

    /// B-6.8.1, B-6.8.4: kayitli tercih -> macDefaults sirasiyla dener; ilk basariliyi `registeredHotkey` yapar.
    public func registerInitialHotkey() {
        var candidates: [HotkeyCombo] = []
        if case .string(let raw)? = store.value(.toggleHotkey),
           let stored = HotkeyCombo(storageString: raw)
        {
            candidates.append(stored)
        }
        for fallback in HotkeyCombo.macDefaults where !candidates.contains(fallback) {
            candidates.append(fallback)
        }

        for candidate in candidates {
            if hotkeys.register(candidate) {
                registeredHotkey = candidate
                return
            }
        }
        registeredHotkey = nil
    }

    /// B-6.6.3, B-6.6.15, B-6.8.2: >= 2 modifiyer zorunlu; basarisizsa onceki kayda geri doner.
    @discardableResult
    public func changeHotkey(_ c: HotkeyCombo) -> Bool {
        guard c.isValid else { return false }
        let previous = registeredHotkey
        if previous != nil {
            hotkeys.unregister()
        }
        if hotkeys.register(c) {
            registeredHotkey = c
            store.set(.string(c.storageString), for: .toggleHotkey)
            return true
        }
        if let previous, hotkeys.register(previous) {
            registeredHotkey = previous
        } else {
            registeredHotkey = nil
        }
        return false
    }

    public func beginRecording() {
        hotkeys.suspend()
    }

    public func endRecording() {
        hotkeys.resume()
    }

    // MARK: - Sifirla

    /// B-6.6.13, E11: tum ayarlari varsayilana dondurur ve varsayilan hotkey zincirini yeniden kaydeder.
    @discardableResult
    public func resetToDefaults() -> Bool {
        suppressPersistence = true
        defer { suppressPersistence = false }

        store.removeAll()
        themeMode = .system
        maxItems = Self.defaultMaxItems
        sensitiveFilter = true
        clearOnScreenLock = false
        autoHideOnBlur = true
        alwaysOnTopDefault = false
        pollingIntervalMs = Self.defaultPollingIntervalMs
        clearOnStartup = false
        alwaysPastePlainText = false

        hotkeys.unregister()
        registerInitialHotkey()
        return registeredHotkey != nil
    }

    // MARK: - Yardimcilar

    private func persist(_ value: SettingValue, for key: SettingKey) {
        guard !suppressPersistence else { return }
        store.set(value, for: key)
    }

    private static func readBool(from store: SettingsStore, key: SettingKey, fallback: Bool) -> Bool {
        guard case .bool(let v)? = store.value(key) else { return fallback }
        return v
    }

    private static func readAllowedInt(
        from store: SettingsStore, key: SettingKey, allowed: [Int], fallback: Int
    ) -> Int {
        guard case .int(let v)? = store.value(key), allowed.contains(v) else { return fallback }
        return v
    }

    private static func readThemeMode(from store: SettingsStore) -> ThemeMode {
        guard case .string(let raw)? = store.value(.themeMode),
              let mode = ThemeMode(rawValue: raw)
        else {
            return .system
        }
        return mode
    }
}
