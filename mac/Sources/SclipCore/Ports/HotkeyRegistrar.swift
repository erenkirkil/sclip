import Foundation

/// Global kisayol kayit portu (B-6.8.1 – B-6.8.5, E12).
public protocol HotkeyRegistrar: AnyObject {
    func register(_ c: HotkeyCombo) -> Bool
    func unregister()
    func suspend()
    func resume()
}
