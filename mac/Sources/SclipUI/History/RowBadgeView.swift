import AppKit
import SclipCore

@MainActor
public final class RowBadgeView: NSView {
    private let swatchView = ColorSwatchView(frame: .zero)
    private let imageView = NSImageView(frame: .zero)
    private var currentEntryID: EntryID?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Metrics.thumbCornerRadius
        layer?.masksToBounds = true

        swatchView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown

        addSubview(swatchView)
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Metrics.thumb),
            heightAnchor.constraint(equalToConstant: Metrics.thumb),

            swatchView.leadingAnchor.constraint(equalTo: leadingAnchor),
            swatchView.trailingAnchor.constraint(equalTo: trailingAnchor),
            swatchView.topAnchor.constraint(equalTo: topAnchor),
            swatchView.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.thumb),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: Metrics.thumb),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(with entry: Entry, cache: ThumbnailCache) {
        currentEntryID = entry.id
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0

        switch entry.payload {
        case let .color(_, _, argb):
            layer?.backgroundColor = nil
            swatchView.isHidden = false
            imageView.isHidden = true
            swatchView.argb = argb

        case let .image(item):
            swatchView.isHidden = true
            imageView.isHidden = false
            showSymbol("photo")
            let expectedID = entry.id
            cache.loadThumbnail(entryID: entry.id, index: 0, data: item.data, scale: scale) { [weak self] img in
                guard let self, self.currentEntryID == expectedID, let img else { return }
                self.layer?.backgroundColor = nil
                self.imageView.contentTintColor = nil
                self.imageView.image = img
            }

        case let .svg(xml):
            swatchView.isHidden = true
            imageView.isHidden = false
            let expectedID = entry.id
            cache.loadSvgThumbnail(entryID: entry.id, xml: xml, scale: scale) { [weak self] img in
                guard let self, self.currentEntryID == expectedID else { return }
                if let img {
                    self.layer?.backgroundColor = nil
                    self.imageView.contentTintColor = nil
                    self.imageView.image = img
                } else {
                    self.showSymbol("exclamationmark.triangle")
                }
            }

        case .url:
            swatchView.isHidden = true
            imageView.isHidden = false
            showSymbol("link")

        case .files:
            swatchView.isHidden = true
            imageView.isHidden = false
            showSymbol("folder")

        case .pdf:
            swatchView.isHidden = true
            imageView.isHidden = false
            showSymbol("doc.richtext")

        case .richText:
            swatchView.isHidden = true
            imageView.isHidden = false
            showSymbol("textformat")

        case .text:
            swatchView.isHidden = true
            imageView.isHidden = false
            showSymbol("doc.plaintext")

        case .imageSet:
            swatchView.isHidden = true
            imageView.isHidden = false
            showSymbol("photo.on.rectangle.angled")
        }
    }

    private func showSymbol(_ name: String) {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        let config = NSImage.SymbolConfiguration(pointSize: Metrics.badgeIcon, weight: .regular)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        imageView.image = img
        imageView.contentTintColor = .secondaryLabelColor
    }
}
