import AppKit
import Combine
import SclipCore
import SclipViewModels

@MainActor
public final class BannerStackView: NSView {
    public var onOpenAccessibilitySettings: (() -> Void)?
    public var onOpenHotkeySettings: (() -> Void)?
    public var onDismissLockCleared: (() -> Void)?

    private let stackView = NSStackView()
    private let bannerViewModel: BannerViewModel
    private let strings: Strings
    private var cancellable: AnyCancellable?
    private var previousBanners: Set<Banner> = []

    public init(bannerViewModel: BannerViewModel, strings: Strings) {
        self.bannerViewModel = bannerViewModel
        self.strings = strings
        super.init(frame: .zero)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        cancellable = bannerViewModel.$banners.sink { [weak self] banners in
            self?.render(banners)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func render(_ banners: [Banner]) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        isHidden = banners.isEmpty

        for banner in banners {
            let item = makeBannerItem(for: banner)
            stackView.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

            if !previousBanners.contains(banner) {
                announceIfNeeded(banner)
            }
        }
        previousBanners = Set(banners)
    }

    private func announceIfNeeded(_ banner: Banner) {
        let message: String?
        switch banner {
        case .accessibility:
            message = strings[.bannerAccessibilityMessage]
        case .hotkey:
            message = strings[.bannerHotkeyMessage]
        case .lockCleared:
            message = nil
        }
        guard let message else { return }
        NSAccessibility.post(
            element: self,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func makeBannerItem(for banner: Banner) -> NSView {
        let message: String
        let actionText: String
        let handler: () -> Void

        switch banner {
        case .accessibility:
            message = strings[.bannerAccessibilityMessage]
            actionText = strings[.bannerAccessibilityAction]
            handler = { [weak self] in self?.onOpenAccessibilitySettings?() }
        case .hotkey:
            message = strings[.bannerHotkeyMessage]
            actionText = strings[.bannerHotkeyAction]
            handler = { [weak self] in self?.onOpenHotkeySettings?() }
        case .lockCleared:
            message = strings[.bannerLockClearedMessage]
            actionText = strings[.bannerLockClearedAction]
            handler = { [weak self] in self?.onDismissLockCleared?() }
        }

        return BannerStripItemView(message: message, actionText: actionText, onClick: handler)
    }
}

@MainActor
private final class BannerStripItemView: NSView {
    private let onClick: () -> Void

    init(message: String, actionText: String, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.16).cgColor

        let msgLabel = NSTextField(wrappingLabelWithString: message)
        msgLabel.font = .systemFont(ofSize: 10.5)
        msgLabel.textColor = .labelColor
        msgLabel.translatesAutoresizingMaskIntoConstraints = false

        let actionLabel = NSTextField(labelWithString: actionText)
        actionLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        actionLabel.textColor = .controlAccentColor
        actionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionLabel.setContentHuggingPriority(.required, for: .horizontal)
        actionLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(msgLabel)
        addSubview(actionLabel)

        NSLayoutConstraint.activate([
            msgLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            msgLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            msgLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            msgLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionLabel.leadingAnchor, constant: -6),

            actionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            actionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // B-6.9.5: Accessibility label is message + " " + action.
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(message) \(actionText)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            onClick()
        }
    }
}
