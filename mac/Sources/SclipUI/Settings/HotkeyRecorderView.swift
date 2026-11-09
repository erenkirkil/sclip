import AppKit
import SclipCore
import SclipViewModels

@MainActor
public final class HotkeyRecorderView: NSView {
    public var onCancel: (() -> Void)?
    public var onSave: ((HotkeyCombo) -> Void)?

    public let titleLabel = NSTextField(labelWithString: "")
    public let bodyLabel = NSTextField(wrappingLabelWithString: "")
    public let comboDisplayButton = FirstMouseButton(frame: .zero)
    public let errorLabel = NSTextField(wrappingLabelWithString: "")
    public let cancelButton = FirstMouseButton(frame: .zero)
    public let saveButton = FirstMouseButton(frame: .zero)

    private let strings: Strings
    private var capturedCombo: HotkeyCombo?
    private var isArmed = true

    public init(strings: Strings, initialCombo: HotkeyCombo?) {
        self.strings = strings
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupViews(initialCombo: initialCombo)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var acceptsFirstResponder: Bool { true }

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleKey(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override public func keyDown(with event: NSEvent) {
        if handleKey(event) {
            return
        }
        super.keyDown(with: event)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        if event.keyCode == 53 { // Escape
            onCancel?()
            return true
        }

        // B-6.2.17: Once a valid combo is captured, Tab and Return can activate Save.
        if !isArmed {
            if event.keyCode == 36 || event.keyCode == 76, let combo = capturedCombo {
                onSave?(combo)
                return true
            }
            if event.keyCode == 48 { // Tab
                return false
            }
        }

        // Ignore standalone modifier key presses
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeyCodes.contains(event.keyCode) {
            return true
        }

        let mods = Self.extractModifiers(from: event.modifierFlags)
        let candidate = HotkeyCombo(modifiers: mods, keyCode: event.keyCode)
        if !candidate.isValid {
            errorLabel.stringValue = strings[.settingsHotkeyErrorMinModifiers]
            errorLabel.isHidden = false
            return true
        }

        capturedCombo = candidate
        isArmed = false
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
        comboDisplayButton.title = HotkeyFormatter.format(candidate)
        bodyLabel.stringValue = strings[.hotkeyRecorderRerecord]
        saveButton.isEnabled = true
        return true
    }

    private func setupViews(initialCombo: HotkeyCombo?) {
        titleLabel.stringValue = strings[.hotkeyRecorderTitle]
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.stringValue = strings[.hotkeyRecorderBody]
        bodyLabel.font = .systemFont(ofSize: 11)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.alignment = .center
        bodyLabel.preferredMaxLayoutWidth = 190
        bodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        comboDisplayButton.bezelStyle = .rounded
        comboDisplayButton.controlSize = .small
        comboDisplayButton.title = HotkeyFormatter.format(initialCombo)
        comboDisplayButton.target = self
        comboDisplayButton.action = #selector(handleReArm)
        comboDisplayButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        comboDisplayButton.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.font = .systemFont(ofSize: 10.5)
        errorLabel.textColor = .systemRed
        errorLabel.alignment = .center
        errorLabel.preferredMaxLayoutWidth = 190
        errorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.title = strings[.commonCancel]
        cancelButton.target = self
        cancelButton.action = #selector(handleCancel)
        cancelButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .small
        saveButton.title = strings[.hotkeyRecorderSave]
        saveButton.keyEquivalent = "\r"
        saveButton.bezelColor = .controlAccentColor
        saveButton.isEnabled = false
        saveButton.target = self
        saveButton.action = #selector(handleSave)
        saveButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 6
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, bodyLabel, comboDisplayButton, errorLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func handleReArm() {
        isArmed = true
        capturedCombo = nil
        saveButton.isEnabled = false
        bodyLabel.stringValue = strings[.hotkeyRecorderBody]
        errorLabel.isHidden = true
        window?.makeFirstResponder(self)
    }

    @objc private func handleCancel() {
        onCancel?()
    }

    @objc private func handleSave() {
        guard let combo = capturedCombo else { return }
        onSave?(combo)
    }

    private static func extractModifiers(from flags: NSEvent.ModifierFlags) -> Set<Modifier> {
        var result: Set<Modifier> = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }
}
