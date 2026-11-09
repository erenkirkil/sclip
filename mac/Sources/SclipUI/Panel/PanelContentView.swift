import AppKit
import SclipViewModels

@MainActor
public final class PanelContentView: NSVisualEffectView {
    public let contentView: NSView
    public let settingsView: NSView
    private let modalBackdrop = ModalBackdropView()
    private var activeModalCleanup: (() -> Void)?

    public var hasActiveModal: Bool {
        !modalBackdrop.isHidden
    }

    public init(content: NSView, settings: NSView) {
        self.contentView = content
        self.settingsView = settings
        super.init(frame: NSRect(origin: .zero, size: Metrics.panelDefaultSize))

        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true

        content.translatesAutoresizingMaskIntoConstraints = false
        settings.translatesAutoresizingMaskIntoConstraints = false
        settings.isHidden = true

        modalBackdrop.translatesAutoresizingMaskIntoConstraints = false
        modalBackdrop.isHidden = true

        addSubview(content)
        addSubview(settings)
        addSubview(modalBackdrop)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.titlebarHeight),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),

            settings.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.titlebarHeight),
            settings.leadingAnchor.constraint(equalTo: leadingAnchor),
            settings.trailingAnchor.constraint(equalTo: trailingAnchor),
            settings.bottomAnchor.constraint(equalTo: bottomAnchor),

            modalBackdrop.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.titlebarHeight),
            modalBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            modalBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            modalBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showPage(_ page: Page) {
        contentView.isHidden = (page != .history)
        settingsView.isHidden = (page != .settings)
    }

    public func presentModal(
        _ card: NSView,
        initialFirstResponder: NSView? = nil,
        onCancel: @escaping () -> Void
    ) {
        dismissModal(runCancel: true)
        activeModalCleanup = onCancel
        modalBackdrop.setCard(card)
        modalBackdrop.isHidden = false
        window?.makeFirstResponder(initialFirstResponder ?? card)
    }

    public func dismissModal(runCancel: Bool = true) {
        let cleanup = activeModalCleanup
        activeModalCleanup = nil
        modalBackdrop.clearCard()
        modalBackdrop.isHidden = true
        if runCancel {
            cleanup?()
        }
    }
}

@MainActor
private final class ModalBackdropView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCard(_ card: NSView) {
        clearCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(card)

        let lead = card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14)
        lead.priority = .defaultHigh
        let trail = card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        trail.priority = .defaultHigh

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            lead,
            trail,
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 232),
        ])
    }

    func clearCard() {
        subviews.forEach { $0.removeFromSuperview() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}
