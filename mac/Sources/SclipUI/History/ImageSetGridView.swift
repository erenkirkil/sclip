import AppKit
import SclipCore

@MainActor
public final class ImageSetGridView: NSView {
    public var onSelectIndex: ((Int) -> Void)?

    private var thumbViews: [ImageSetThumbView] = []
    private var focusedIndex: Int?

    override public var isFlipped: Bool { true }

    public static func columnCount(forWidth width: CGFloat) -> Int {
        let cell = Metrics.thumb + Metrics.imageSetGap
        guard width > Metrics.thumb else { return 1 }
        return max(1, Int(floor((width + Metrics.imageSetGap) / cell)))
    }

    public static func height(forCount count: Int, width: CGFloat) -> CGFloat {
        guard count > 0 else { return Metrics.thumb }
        let cols = columnCount(forWidth: width)
        let rows = (count + cols - 1) / cols
        return CGFloat(rows) * Metrics.thumb + CGFloat(max(0, rows - 1)) * Metrics.imageSetGap
    }

    public func configure(
        entryID: EntryID,
        items: [ImageItem],
        strings: Strings,
        cache: ThumbnailCache,
        focusedIndex: Int?
    ) {
        self.focusedIndex = focusedIndex
        thumbViews.forEach { $0.removeFromSuperview() }
        thumbViews.removeAll(keepingCapacity: true)

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let total = items.count

        for (index, item) in items.enumerated() {
            let view = ImageSetThumbView(frame: NSRect(x: 0, y: 0, width: Metrics.thumb, height: Metrics.thumb))
            let a11y = strings.format(.a11yImageSetThumb, ["n": String(index + 1), "total": String(total)])
            view.setAccessibilityLabel(a11y)
            view.toolTip = a11y
            view.isKeyboardFocused = (focusedIndex == index)
            view.onClick = { [weak self] in
                self?.onSelectIndex?(index)
            }
            addSubview(view)
            thumbViews.append(view)

            cache.loadThumbnail(entryID: entryID, index: index, data: item.data, scale: scale) { [weak view] img in
                view?.image = img
            }
        }
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    public func updateFocusedIndex(_ index: Int?) {
        focusedIndex = index
        for (i, view) in thumbViews.enumerated() {
            view.isKeyboardFocused = (index == i)
        }
    }

    override public func layout() {
        super.layout()
        let cols = Self.columnCount(forWidth: bounds.width)
        let step = Metrics.thumb + Metrics.imageSetGap
        for (index, view) in thumbViews.enumerated() {
            let col = index % cols
            let row = index / cols
            view.frame = NSRect(
                x: CGFloat(col) * step,
                y: CGFloat(row) * step,
                width: Metrics.thumb,
                height: Metrics.thumb
            )
        }
    }

    override public var intrinsicContentSize: NSSize {
        let width = bounds.width > 0 ? bounds.width : (Metrics.panelDefaultSize.width - 76)
        let h = Self.height(forCount: thumbViews.count, width: width)
        return NSSize(width: NSView.noIntrinsicMetric, height: h)
    }
}

@MainActor
private final class ImageSetThumbView: NSView {
    var onClick: (() -> Void)?
    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var isKeyboardFocused = false {
        didSet {
            if oldValue != isKeyboardFocused { needsDisplay = true }
        }
    }
    private var isHovered = false {
        didSet {
            if oldValue != isHovered { needsDisplay = true }
        }
    }
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            onClick?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: Metrics.thumbCornerRadius,
            yRadius: Metrics.thumbCornerRadius
        )
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.quaternaryLabelColor.setFill()
        bounds.fill()
        if let image {
            image.draw(in: bounds)
        }
        NSGraphicsContext.restoreGraphicsState()

        let accent = NSColor.controlAccentColor
        if isKeyboardFocused {
            let strokeRect = bounds.insetBy(dx: 0.75, dy: 0.75)
            let strokePath = NSBezierPath(
                roundedRect: strokeRect,
                xRadius: Metrics.thumbCornerRadius,
                yRadius: Metrics.thumbCornerRadius
            )
            accent.withAlphaComponent(Metrics.rowFocusAlpha).setFill()
            strokePath.fill()
            strokePath.lineWidth = Metrics.rowFocusBorderWidth
            accent.setStroke()
            strokePath.stroke()
        } else if isHovered {
            accent.withAlphaComponent(Metrics.rowHoverAlpha).setFill()
            path.fill()
        }
    }
}
