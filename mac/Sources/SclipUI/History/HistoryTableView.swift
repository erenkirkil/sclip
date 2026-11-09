import AppKit
import Combine
import SclipCore
import SclipViewModels

@MainActor
public final class HistoryTableView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    public var onMoveUpFromFirstRow: (() -> Void)?
    public var onOpenURL: ((Entry) -> Void)?

    public let scrollView = NSScrollView()
    public let tableView = KeyHandlingTableView()
    public let emptyLabel = NSTextField(wrappingLabelWithString: "")

    private let historyViewModel: HistoryViewModel
    private let panelViewModel: PanelViewModel
    private let searchViewModel: SearchViewModel
    private let strings: Strings
    private let clock: Clock
    private let cache: ThumbnailCache

    private var rowsCancellable: AnyCancellable?
    nonisolated(unsafe) private var minuteTimer: Timer?
    private var displayedRows: [Entry] = []

    public private(set) var focusedRow: Int?
    public private(set) var rowSubFocus: RowSubFocus = .row
    private var gridFocusByEntryID: [EntryID: GridFocus] = [:]
    private var gridRememberedByEntryID: [EntryID: Int] = [:]

    public init(
        historyViewModel: HistoryViewModel,
        panelViewModel: PanelViewModel,
        searchViewModel: SearchViewModel,
        strings: Strings,
        clock: Clock,
        cache: ThumbnailCache = .shared
    ) {
        self.historyViewModel = historyViewModel
        self.panelViewModel = panelViewModel
        self.searchViewModel = searchViewModel
        self.strings = strings
        self.clock = clock
        self.cache = cache
        super.init(frame: .zero)

        setupViews()
        bind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        minuteTimer?.invalidate()
    }

    public func focusFirstRow() {
        guard !displayedRows.isEmpty else {
            window?.makeFirstResponder(tableView)
            focusedRow = nil
            return
        }
        window?.makeFirstResponder(tableView)
        setFocusedRow(0)
    }

    public func setFocusedRow(_ row: Int?) {
        guard let row, (0..<displayedRows.count).contains(row) else {
            focusedRow = nil
            tableView.deselectAll(nil)
            refreshRowFocusStates()
            return
        }
        focusedRow = row
        rowSubFocus = .row
        let entry = displayedRows[row]
        if entry.payload.kind == .imageSet, gridFocusByEntryID[entry.id] == nil {
            gridFocusByEntryID[entry.id] = .thumb(0)
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        refreshRowFocusStates()
    }

    // MARK: - NSTableViewDataSource & Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        displayedRows.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard (0..<displayedRows.count).contains(row) else { return nil }
        let entry = displayedRows[row]
        let isFocused = (focusedRow == row)

        if case let .imageSet(items) = entry.payload {
            let cell = ImageSetRowView(frame: .zero)
            let focus = isFocused ? (gridFocusByEntryID[entry.id] ?? .thumb(0)) : nil
            cell.configure(entry: entry, items: items, strings: strings, now: clock.now(), cache: cache, gridFocus: focus)
            cell.onPasteThumb = { [weak self] index in self?.panelViewModel.paste(entry, imageIndex: index) }
            cell.onPasteAll = { [weak self] in self?.panelViewModel.paste(entry, imageIndex: nil) }
            cell.onDelete = { [weak self] in self?.deleteEntry(entry) }
            return cell
        }

        let cell = HistoryRowView(frame: .zero)
        cell.configure(entry: entry, strings: strings, now: clock.now(), cache: cache, subFocus: isFocused ? rowSubFocus : .none)
        cell.onPaste = { [weak self] in self?.panelViewModel.paste(entry, imageIndex: nil) }
        cell.onOpenURL = { [weak self] in self?.openEntryURL(entry) }
        cell.onDelete = { [weak self] in self?.deleteEntry(entry) }
        return cell
    }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard (0..<displayedRows.count).contains(row) else { return 34 }
        if case let .imageSet(items) = displayedRows[row].payload {
            let width = max(tableView.bounds.width, Metrics.panelDefaultSize.width)
            return ImageSetRowView.estimatedHeight(itemCount: items.count, availableWidth: width)
        }
        return 34
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        UnemphasizedTableRowView()
    }

    // MARK: - Keyboard handling (§6.2)

    fileprivate func handleKeyDown(_ event: NSEvent) -> Bool {
        let rows = displayedRows
        guard !rows.isEmpty else { return false }
        let currentRow = focusedRow ?? 0
        guard (0..<rows.count).contains(currentRow) else { return false }
        let entry = rows[currentRow]
        if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty { return false }

        switch event.keyCode {
        case 51, 117:
            deleteEntry(entry)
            return true
        case 36, 76, 49:
            activateCurrentSelection(entry: entry)
            return true
        case 126:
            return moveVertical(.up, row: currentRow, entry: entry)
        case 125:
            return moveVertical(.down, row: currentRow, entry: entry)
        case 123:
            return moveHorizontal(.left, row: currentRow, entry: entry)
        case 124:
            return moveHorizontal(.right, row: currentRow, entry: entry)
        default:
            return false
        }
    }

    private func activateCurrentSelection(entry: Entry) {
        if case .imageSet = entry.payload {
            switch gridFocusByEntryID[entry.id] ?? .thumb(0) {
            case let .thumb(i): panelViewModel.paste(entry, imageIndex: i)
            case .pasteAll: panelViewModel.paste(entry, imageIndex: nil)
            case .delete: deleteEntry(entry)
            }
            return
        }
        switch rowSubFocus {
        case .row, .none: panelViewModel.paste(entry, imageIndex: nil)
        case .primaryAction: openEntryURL(entry)
        case .deleteAction: deleteEntry(entry)
        }
    }

    private func navigateImageSet(_ direction: Direction, row: Int, entry: Entry, count: Int) -> Bool {
        let width = max(tableView.bounds.width, Metrics.panelDefaultSize.width)
        let cols = ImageSetGridView.columnCount(forWidth: width - 64)
        let currentFocus = gridFocusByEntryID[entry.id] ?? .thumb(0)
        let move = GridNavigator.move(
            direction,
            from: currentFocus,
            count: count,
            columns: cols,
            hasPasteAll: true,
            remembered: gridRememberedByEntryID[entry.id],
            isFirstRow: row == 0,
            searchOpen: searchViewModel.isOpen
        )
        return applyGridMove(move, row: row, entry: entry, currentFocus: currentFocus)
    }

    private func moveVertical(_ direction: Direction, row: Int, entry: Entry) -> Bool {
        if case let .imageSet(items) = entry.payload {
            return navigateImageSet(direction, row: row, entry: entry, count: items.count)
        }
        if direction == .up {
            if row == 0 { onMoveUpFromFirstRow?() } else { setFocusedRow(row - 1) }
        } else if row + 1 < displayedRows.count {
            setFocusedRow(row + 1)
        }
        return true
    }

    private func moveHorizontal(_ direction: Direction, row: Int, entry: Entry) -> Bool {
        if case let .imageSet(items) = entry.payload {
            return navigateImageSet(direction, row: row, entry: entry, count: items.count)
        }
        let hasOpen = (entry.payload.kind == .url)
        if direction == .right {
            switch rowSubFocus {
            case .row, .none: rowSubFocus = hasOpen ? .primaryAction : .deleteAction
            case .primaryAction: rowSubFocus = .deleteAction
            case .deleteAction: break
            }
        } else {
            switch rowSubFocus {
            case .deleteAction: rowSubFocus = hasOpen ? .primaryAction : .row
            case .primaryAction, .row, .none: rowSubFocus = .row
            }
        }
        refreshRowFocusStates()
        return true
    }

    private func applyGridMove(_ move: GridMove, row: Int, entry: Entry, currentFocus: GridFocus) -> Bool {
        switch move {
        case let .focus(nextFocus):
            if case let .thumb(i) = currentFocus, nextFocus != .thumb(i) {
                if nextFocus == .pasteAll || nextFocus == .delete {
                    gridRememberedByEntryID[entry.id] = i
                }
            }
            gridFocusByEntryID[entry.id] = nextFocus
            refreshRowFocusStates()
        case .previousRow:
            if row == 0 { onMoveUpFromFirstRow?() } else { setFocusedRow(row - 1) }
        case .nextRow:
            if row + 1 < displayedRows.count { setFocusedRow(row + 1) }
        case .searchField:
            onMoveUpFromFirstRow?()
        case .none:
            break
        }
        return true
    }

    private func deleteEntry(_ entry: Entry) {
        let previousRow = focusedRow ?? 0
        let announcement = historyViewModel.delete(entry.id)
        if !announcement.isEmpty {
            NSAccessibility.post(
                element: self,
                notification: .announcementRequested,
                userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue]
            )
        }
        let newCount = displayedRows.count
        setFocusedRow(newCount > 0 ? min(previousRow, newCount - 1) : nil)
    }

    private func openEntryURL(_ entry: Entry) {
        guard case let .url(_, uri, _) = entry.payload, let url = URL(string: uri) else { return }
        panelViewModel.requestHide()
        NSWorkspace.shared.open(url)
        onOpenURL?(entry)
    }

    private func setupViews() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MainColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyHandler = { [weak self] event in self?.handleKeyDown(event) ?? false }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])

        let timer = Timer(timeInterval: 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVisibleTimestamps() }
        }
        timer.tolerance = 6.0
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }

    private func bind() {
        rowsCancellable = historyViewModel.$rows.sink { [weak self] rows in
            guard let self else { return }
            self.displayedRows = rows
            self.tableView.reloadData()
            self.emptyLabel.stringValue = self.historyViewModel.emptyStateText
            self.emptyLabel.isHidden = !rows.isEmpty
            self.scrollView.isHidden = rows.isEmpty
            let tableIsFocused = (self.window?.firstResponder === self.tableView)
            if rows.isEmpty || (!tableIsFocused && self.searchViewModel.isOpen) {
                self.focusedRow = nil
            } else if let current = self.focusedRow, current >= rows.count {
                self.focusedRow = rows.count - 1
            } else if self.focusedRow == nil {
                self.focusedRow = 0
            }
            self.refreshRowFocusStates()
        }
    }

    private func refreshRowFocusStates() {
        let range = tableView.rows(in: tableView.visibleRect)
        guard range.length > 0 else { return }
        for row in range.location..<(range.location + range.length) {
            guard (0..<displayedRows.count).contains(row),
                  let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
            else { continue }
            let isFocused = (focusedRow == row)
            if let historyRow = view as? HistoryRowView {
                historyRow.subFocus = isFocused ? rowSubFocus : .none
            } else if let imageSetRow = view as? ImageSetRowView {
                let entry = displayedRows[row]
                imageSetRow.updateFocus(isFocused ? (gridFocusByEntryID[entry.id] ?? .thumb(0)) : nil)
            }
        }
    }

    private func refreshVisibleTimestamps() {
        guard window?.isVisible == true else { return }
        let now = clock.now()
        let range = tableView.rows(in: tableView.visibleRect)
        guard range.length > 0 else { return }
        for row in range.location..<(range.location + range.length) {
            guard let view = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) else { continue }
            (view as? HistoryRowView)?.refreshTimeLabel(now: now, strings: strings)
            (view as? ImageSetRowView)?.refreshTimeLabel(now: now, strings: strings)
        }
    }
}

@MainActor
public final class KeyHandlingTableView: NSTableView {
    public var keyHandler: ((NSEvent) -> Bool)?

    override public func keyDown(with event: NSEvent) {
        if let keyHandler, keyHandler(event) { return }
        super.keyDown(with: event)
    }
}

@MainActor
private final class UnemphasizedTableRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}
