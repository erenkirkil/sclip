import AppKit

@MainActor
public final class FirstMouseButton: NSButton {
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
public final class ModalDialogView: NSView {
    public let titleLabel = NSTextField(labelWithString: "")
    public let bodyLabel = NSTextField(wrappingLabelWithString: "")
    public let cancelButton = FirstMouseButton(frame: .zero)
    public let confirmButton = FirstMouseButton(frame: .zero)

    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    public init(
        title: String,
        body: String,
        confirmTitle: String,
        cancelTitle: String,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.stringValue = body
        bodyLabel.font = .systemFont(ofSize: 11)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.alignment = .center
        bodyLabel.maximumNumberOfLines = 4
        bodyLabel.preferredMaxLayoutWidth = 190
        bodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.title = cancelTitle
        cancelButton.target = self
        cancelButton.action = #selector(handleCancel)
        cancelButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        confirmButton.bezelStyle = .rounded
        confirmButton.controlSize = .small
        confirmButton.title = confirmTitle
        confirmButton.keyEquivalent = "\r"
        confirmButton.bezelColor = .controlAccentColor
        confirmButton.target = self
        confirmButton.action = #selector(handleConfirm)
        confirmButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [cancelButton, confirmButton])
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 6
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, bodyLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var acceptsFirstResponder: Bool { true }

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onConfirm()
            return
        }
        if event.keyCode == 53 {
            onCancel()
            return
        }
        super.keyDown(with: event)
    }

    @objc private func handleConfirm() {
        onConfirm()
    }

    @objc private func handleCancel() {
        onCancel()
    }
}
