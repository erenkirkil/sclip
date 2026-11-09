import AppKit
import Combine
import SclipCore
import SclipViewModels

@MainActor
public final class SearchBarView: NSView, NSSearchFieldDelegate {
    public var onSearchFocused: (() -> Void)?
    public var onMoveToFirstRow: (() -> Void)?
    public var onSubmitFirstMatch: (() -> Void)?
    public var onEscape: (() -> Void)?

    public let searchField = NSSearchField(frame: .zero)
    public let closeButton = FirstMouseButton(frame: .zero)

    private let searchViewModel: SearchViewModel
    private let strings: Strings
    private var cancellables: Set<AnyCancellable> = []

    public init(searchViewModel: SearchViewModel, strings: Strings) {
        self.searchViewModel = searchViewModel
        self.strings = strings
        super.init(frame: .zero)

        setupViews()
        bind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func focusAndSelectAll() {
        guard !isHidden else { return }
        onSearchFocused?()
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    // MARK: - NSSearchFieldDelegate

    public func controlTextDidBeginEditing(_ obj: Notification) {
        onSearchFocused?()
    }

    public func controlTextDidChange(_ obj: Notification) {
        onSearchFocused?()
        let value = searchField.stringValue
        if searchViewModel.query != value {
            searchViewModel.query = value
        }
    }

    public func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            onMoveToFirstRow?()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onSubmitFirstMatch?()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onEscape?()
            return true
        }
        // B-6.2.16: Backspace / Forward Delete in search field only edits text, never deletes a row.
        return false
    }

    // MARK: - Private

    private func setupViews() {
        searchField.placeholderString = strings[.searchPlaceholder]
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        searchField.font = .systemFont(ofSize: Metrics.previewFont)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.setAccessibilityLabel(strings[.searchPlaceholder])

        let closeTitle = strings[.searchClose]
        let config = NSImage.SymbolConfiguration(pointSize: Metrics.rowButtonIcon, weight: .regular)
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: closeTitle)?
            .withSymbolConfiguration(config)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = closeTitle
        closeButton.setAccessibilityLabel(closeTitle)
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchField)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),

            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: Metrics.rowButton),
            closeButton.heightAnchor.constraint(equalToConstant: Metrics.rowButton),
        ])
    }

    private func bind() {
        searchViewModel.$isOpen.sink { [weak self] open in
            guard let self else { return }
            self.isHidden = !open
            if open {
                DispatchQueue.main.async { [weak self] in
                    self?.focusAndSelectAll()
                }
            } else if self.window?.isVisible == true {
                DispatchQueue.main.async { [weak self] in
                    self?.onMoveToFirstRow?()
                }
            }
        }.store(in: &cancellables)

        searchViewModel.$query.sink { [weak self] query in
            guard let self else { return }
            if self.searchField.stringValue != query {
                self.searchField.stringValue = query
            }
        }.store(in: &cancellables)

        searchViewModel.focusRequest.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.focusAndSelectAll()
            }
        }.store(in: &cancellables)
    }

    @objc private func handleClose() {
        searchViewModel.close()
    }
}
