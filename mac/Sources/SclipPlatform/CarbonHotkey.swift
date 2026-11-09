import Carbon.HIToolbox
import Foundation
import SclipCore

public final class CarbonHotkey: HotkeyRegistrar {
    private static let signature: OSType = 0x5343_4C50 // 'SCLP'
    private static let hotKeyIDValue: UInt32 = 1

    private let onPress: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var activeCombo: HotkeyCombo?
    private var suspendedCombo: HotkeyCombo?

    public init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
        installEventHandlerIfNeeded()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    public func register(_ c: HotkeyCombo) -> Bool {
        guard c.isValid else { return false }

        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
            activeCombo = nil
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyIDValue)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(c.keyCode),
            Self.carbonModifiers(for: c.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        guard status == noErr, let newRef else {
            return false
        }

        hotKeyRef = newRef
        activeCombo = c
        suspendedCombo = nil
        return true
    }

    public func unregister() {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        activeCombo = nil
        suspendedCombo = nil
    }

    public func suspend() {
        if let activeCombo {
            suspendedCombo = activeCombo
        }
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        activeCombo = nil
    }

    public func resume() {
        guard hotKeyRef == nil, let combo = suspendedCombo else { return }
        _ = register(combo)
    }

    private func installEventHandlerIfNeeded() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var handlerRef: EventHandlerRef?

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr,
                  hotKeyID.signature == CarbonHotkey.signature,
                  hotKeyID.id == CarbonHotkey.hotKeyIDValue
            else {
                return OSStatus(eventNotHandledErr)
            }

            let instance = Unmanaged<CarbonHotkey>.fromOpaque(userData).takeUnretainedValue()
            let handler = instance.onPress
            DispatchQueue.main.async {
                handler()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )
        eventHandlerRef = handlerRef
    }

    private static func carbonModifiers(for modifiers: Set<Modifier>) -> UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { mask |= UInt32(shiftKey) }
        if modifiers.contains(.option) { mask |= UInt32(optionKey) }
        if modifiers.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }
}
