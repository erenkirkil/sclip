import AppKit
import SclipCore

@MainActor
public final class HistoryRowView: NSTableCellView {
    public var onPaste: (() -> Void)?
    public var onOpenURL: (() -> Void)?
    public var onDelete: (() -> Void)?

    public let badgeView = RowBadgeView(frame: .zero)
    public let previewLabel = NSTextField(labelWithString: "")
    public let timeLabel = NSTextField(labelWithString: "")
    public let actionsView = RowActionsView(frame: .zero)

    public var subFocus: RowSubFocus = .none {
        didSet {
            actionsView.setSubFocus(subFocus)
            needsDisplay = true
        }
    }

    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }

    private var trackingArea: NSTrackingArea?
    private var entry: Entry?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        badgeView.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        actionsView.translatesAutoresizingMaskIntoConstraints = false

        previewLabel.font = .systemFont(ofSize: Metrics.previewFont)
        previewLabel.textColor = .labelColor
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.maximumNumberOfLines = 1
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previewLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        timeLabel.font = .systemFont(ofSize: Metrics.timeFont)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(badgeView)
        addSubview(previewLabel)
        addSubview(timeLabel)
        addSubview(actionsView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 32),

            badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            badgeView.centerYAnchor.constraint(equalTo: centerYAnchor),

            previewLabel.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 6),
            previewLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: previewLabel.trailingAnchor, constant: 6),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionsView.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 4),
            actionsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            actionsView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        actionsView.onPrimaryAction = { [weak self] in
            self?.onOpenURL?()
        }
        actionsView.onDeleteAction = { [weak self] in
            self?.onDelete?()
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(
        entry: Entry,
        strings: Strings,
        now: Date,
        cache: ThumbnailCache,
        subFocus: RowSubFocus
    ) {
        self.entry = entry
        self.subFocus = subFocus

        badgeView.configure(with: entry, cache: cache)
        let preview = entry.preview(strings)
        let time = RelativeTime.label(from: entry.createdAt, now: now, strings: strings)
        previewLabel.stringValue = preview
        timeLabel.stringValue = time

        if entry.payload.kind == .url {
            actionsView.configure(
                primarySymbol: "arrow.up.right.square",
                primaryTooltip: strings[.rowOpen],
                deleteTooltip: strings[.rowDelete]
            )
        } else {
            actionsView.configure(
                primarySymbol: nil,
                primaryTooltip: nil,
                deleteTooltip: strings[.rowDelete]
            )
        }

        let kindLabel = Self.accessibilityKindLabel(for: entry.payload.kind, strings: strings)
        setAccessibilityLabel("\(kindLabel), \(preview), \(time)")
    }

    public func refreshTimeLabel(now: Date, strings: Strings) {
        guard let entry else { return }
        let time = RelativeTime.label(from: entry.createdAt, now: now, strings: strings)
        timeLabel.stringValue = time
        let kindLabel = Self.accessibilityKindLabel(for: entry.payload.kind, strings: strings)
        setAccessibilityLabel("\(kindLabel), \( previewLabel.stringValue), \(time)")
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override public func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if actionsView.frame.contains(local) {
            return actionsView.hitTest(local)
        }
        return self
    }

    override public func mouseDown(with event: NSEvent) {}

    override public func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard bounds.contains(pt) else { return }
        let actionsPt = actionsView.convert(pt, from: self)
        if actionsView.bounds.contains(actionsPt) {
            return
        }
        onPaste?()
    }

    override public func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let drawRect = bounds.insetBy(dx: 2, dy: 1)
        let path = NSBezierPath(
            roundedRect: drawRect,
            xRadius: Metrics.rowCornerRadius,
            yRadius: Metrics.rowCornerRadius
        )

        if subFocus == .row {
            accent.withAlphaComponent(Metrics.rowFocusAlpha).setFill()
            path.fill()
            path.lineWidth = Metrics.rowFocusBorderWidth
            accent.setStroke()
            path.stroke()
        } else if isHovered {
            accent.withAlphaComponent(Metrics.rowHoverAlpha).setFill()
            path.fill()
        }

        super.draw(dirtyRect)
    }

    public static func accessibilityKindLabel(for kind: EntryKind, strings: Strings) -> String {
        switch kind {
        case .color: return strings[.a11yKindColor]
        case .svg: return strings[.a11yKindSvg]
        case .image: return strings[.a11yKindImage]
        case .imageSet: return strings[.a11yKindImageSet]
        case .url: return strings[.a11yKindUrl]
        case .files: return strings[.a11yKindFiles]
        case .pdf: return strings[.a11yKindPdf]
        case .richText: return strings[.a11yKindRichText]
        case .text: return strings[.a11yKindText]
        }
    }
}
