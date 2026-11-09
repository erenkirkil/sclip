import AppKit

@MainActor
public final class ColorSwatchView: NSView {
    public var argb: UInt32 = 0xFFFF_FFFF {
        didSet {
            if oldValue != argb {
                needsDisplay = true
            }
        }
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let swatchSize = Metrics.colorSwatch
        let rect = NSRect(
            x: (bounds.width - swatchSize) / 2,
            y: (bounds.height - swatchSize) / 2,
            width: swatchSize,
            height: swatchSize
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: Metrics.thumbCornerRadius, yRadius: Metrics.thumbCornerRadius)

        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        if a < 1.0 {
            drawCheckerboard(in: rect)
        }

        NSColor(srgbRed: r, green: g, blue: b, alpha: a).setFill()
        rect.fill()
        NSGraphicsContext.restoreGraphicsState()

        let strokeRect = rect.insetBy(dx: 0.5, dy: 0.5)
        let strokePath = NSBezierPath(
            roundedRect: strokeRect,
            xRadius: Metrics.thumbCornerRadius,
            yRadius: Metrics.thumbCornerRadius
        )
        strokePath.lineWidth = 1.0
        NSColor.separatorColor.setStroke()
        strokePath.stroke()
    }

    private func drawCheckerboard(in rect: NSRect) {
        let cell: CGFloat = 5
        let light = NSColor(calibratedWhite: 0.92, alpha: 1.0)
        let dark = NSColor(calibratedWhite: 0.75, alpha: 1.0)

        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var col = 0
            var x = rect.minX
            while x < rect.maxX {
                ((row + col).isMultiple(of: 2) ? light : dark).setFill()
                NSRect(x: x, y: y, width: cell, height: cell).fill()
                x += cell
                col += 1
            }
            y += cell
            row += 1
        }
    }
}
