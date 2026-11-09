import AppKit
import SclipCore

@MainActor
public final class ImageSetRowView: NSTableCellView {
    public var onPasteThumb: ((Int) -> Void)?
    public var onPasteAll: (() -> Void)?
    public var onDelete: (() -> Void)?

    public let gridView = ImageSetGridView(frame: .zero)
    public let footerLabel = NSTextField(labelWithString: "")
    public let actionsView = RowActionsView(frame: .zero)

    private var entry: Entry?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        gridView.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        actionsView.translatesAutoresizingMaskIntoConstraints = false

        footerLabel.font = .systemFont(ofSize: Metrics.timeFont)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.lineBreakMode = .byTruncatingTail
        footerLabel.maximumNumberOfLines = 1

        addSubview(gridView)
        addSubview(footerLabel)
        addSubview(actionsView)

        NSLayoutConstraint.activate([
            gridView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            gridView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            gridView.trailingAnchor.constraint(equalTo: actionsView.leadingAnchor, constant: -6),

            footerLabel.topAnchor.constraint(equalTo: gridView.bottomAnchor, constant: 4),
            footerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            footerLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionsView.leadingAnchor, constant: -6),
            footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            actionsView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            actionsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        gridView.onSelectIndex = { [weak self] index in
            self?.onPasteThumb?(index)
        }
        actionsView.onPrimaryAction = { [weak self] in
            self?.onPasteAll?()
        }
        actionsView.onDeleteAction = { [weak self] in
            self?.onDelete?()
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public static func estimatedHeight(itemCount: Int, availableWidth: CGFloat) -> CGFloat {
        let gridWidth = max(Metrics.thumb, availableWidth - 76)
        let gridHeight = ImageSetGridView.height(forCount: itemCount, width: gridWidth)
        return gridHeight + 28
    }

    public func configure(
        entry: Entry,
        items: [ImageItem],
        strings: Strings,
        now: Date,
        cache: ThumbnailCache,
        gridFocus: GridFocus?
    ) {
        self.entry = entry
        let focusedIndex: Int?
        if case let .thumb(i)? = gridFocus {
            focusedIndex = i
        } else {
            focusedIndex = nil
        }

        gridView.configure(
            entryID: entry.id,
            items: items,
            strings: strings,
            cache: cache,
            focusedIndex: focusedIndex
        )

        actionsView.configure(
            primarySymbol: "doc.on.doc",
            primaryTooltip: strings[.rowPasteAll],
            deleteTooltip: strings[.rowDelete]
        )
        updateFocus(gridFocus)
        refreshTimeLabel(now: now, strings: strings)
        setAccessibilityLabel(strings[.a11yKindImageSet])
    }

    public func updateFocus(_ gridFocus: GridFocus?) {
        switch gridFocus {
        case let .thumb(i)?:
            gridView.updateFocusedIndex(i)
            actionsView.setSubFocus(.none)
        case .pasteAll?:
            gridView.updateFocusedIndex(nil)
            actionsView.setSubFocus(.primaryAction)
        case .delete?:
            gridView.updateFocusedIndex(nil)
            actionsView.setSubFocus(.deleteAction)
        case nil:
            gridView.updateFocusedIndex(nil)
            actionsView.setSubFocus(.none)
        }
    }

    public func refreshTimeLabel(now: Date, strings: Strings) {
        guard let entry else { return }
        let preview = entry.preview(strings)
        let time = RelativeTime.label(from: entry.createdAt, now: now, strings: strings)
        footerLabel.stringValue = strings.format(.imageSetFooter, ["preview": preview, "time": time])
    }
}
