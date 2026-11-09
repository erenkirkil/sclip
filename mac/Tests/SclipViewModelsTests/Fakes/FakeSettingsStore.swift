import SclipCore

final class FakeSettingsStore: SettingsStore {
    struct WriteRecord: Equatable {
        let key: SettingKey
        let value: SettingValue
    }

    private var storage: [SettingKey: SettingValue] = [:]
    private(set) var writes: [WriteRecord] = []
    private(set) var writtenRawKeys: [String] = []
    private(set) var removeAllCount = 0

    init(initial: [SettingKey: SettingValue] = [:]) {
        self.storage = initial
    }

    func value(_ key: SettingKey) -> SettingValue? {
        storage[key]
    }

    func set(_ value: SettingValue, for key: SettingKey) {
        storage[key] = value
        writes.append(WriteRecord(key: key, value: value))
        writtenRawKeys.append(key.rawValue)
    }

    func removeAll() {
        storage.removeAll()
        removeAllCount += 1
    }
}
