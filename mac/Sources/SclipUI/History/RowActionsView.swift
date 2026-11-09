import AppKit

public enum RowSubFocus: Equatable, Sendable {
    case none
    case row
    case primaryAction
    case deleteAction
}

@MainActor
public final class RowActionsView: NSView {
    public var onPrimaryAction: (() -> Void)?
    public var onDeleteAction: (() -> Void)?

    public let primaryButton = ActionIconButton(frame: .zero)
    public let deleteButton = ActionIconButton(frame: .zero)
    private let stackView = NSStackView()

    public private(set) var hasPrimaryAction = false

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        primaryButton.target = self
        primaryButton.action = #selector(handlePrimaryClick)
        deleteButton.target = self
        deleteButton.action = #selector(handleDeleteClick)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(primaryButton)
        stackView.addArrangedSubview(deleteButton)

        addSubview(stackView)

        NSLayoutConstraint.activate([
            primaryButton.widthAnchor.constraint(equalToConstant: Metrics.rowButton),
            primaryButton.heightAnchor.constraint(equalToConstant: Metrics.rowButton),
            deleteButton.widthAnchor.constraint(equalToConstant: Metrics.rowButton),
            deleteButton.heightAnchor.constraint(equalToConstant: Metrics.rowButton),

            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public func configure(
        primarySymbol: String?,
        primaryTooltip: String?,
        deleteSymbol: String = "trash",
        deleteTooltip: String
    ) {
        if let primarySymbol, let primaryTooltip {
            hasPrimaryAction = true
            primaryButton.isHidden = false
            primaryButton.configure(symbolName: primarySymbol, tooltip: primaryTooltip)
        } else {
            hasPrimaryAction = false
            primaryButton.isHidden = true
        }
        deleteButton.configure(symbolName: deleteSymbol, tooltip: deleteTooltip)
    }

    public func setSubFocus(_ subFocus: RowSubFocus) {
        primaryButton.isKeyboardFocused = (subFocus == .primaryAction)
        deleteButton.isKeyboardFocused = (subFocus == .deleteAction)
    }

    @objc private func handlePrimaryClick() {
        onPrimaryAction?()
    }

    @objc private func handleDeleteClick() {
        onDeleteAction?()
    }
}

@MainActor
public final class ActionIconButton: NSButton {
    public var isKeyboardFocused = false {
        didSet {
            if oldValue != isKeyboardFocused {
                needsDisplay = true
            }
        }
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        // B-6.2.6: Row action buttons do not participate in Tab order.
        refusesFirstResponder = true
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public func configure(symbolName: String, tooltip: String) {
        let config = NSImage.SymbolConfiguration(pointSize: Metrics.rowButtonIcon, weight: .regular)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        contentTintColor = .secondaryLabelColor
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
    }

    override public func draw(_ dirtyRect: NSRect) {
        if isKeyboardFocused {
            let accent = NSColor.controlAccentColor
            let rect = bounds.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            accent.withAlphaComponent(Metrics.rowFocusAlpha).setFill()
            path.fill()
            path.lineWidth = Metrics.rowFocusBorderWidth
            accent.setStroke()
            path.stroke()
        }
        super.draw(dirtyRect)
    }
}
