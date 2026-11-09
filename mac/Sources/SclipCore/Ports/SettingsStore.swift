import Foundation

/// B-8.5.1: Yalniz tipli `SettingKey` degerlerini okur/yazar; pano icerigi yazacak imzasi yoktur.
public protocol SettingsStore: AnyObject {
    func value(_ k: SettingKey) -> SettingValue?
    func set(_ v: SettingValue, for k: SettingKey)
    func removeAll()
}
