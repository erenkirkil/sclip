import AppKit
import Combine
import SclipCore
import SclipViewModels

@MainActor
public final class ToolbarView: NSView {
    public let titleLabel = NSTextField(labelWithString: "")
    public let searchButton = FirstMouseButton(frame: .zero)
    public let clearAllButton = FirstMouseButton(frame: .zero)
    public let settingsButton = FirstMouseButton(frame: .zero)

    private let panelViewModel: PanelViewModel
    private let historyViewModel: HistoryViewModel
    private let searchViewModel: SearchViewModel
    private let strings: Strings
    private var totalCountCancellable: AnyCancellable?

    public init(
        panelViewModel: PanelViewModel,
        historyViewModel: HistoryViewModel,
        searchViewModel: SearchViewModel,
        strings: Strings
    ) {
        self.panelViewModel = panelViewModel
        self.historyViewModel = historyViewModel
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

    public func focusFirstButton() {
        window?.makeFirstResponder(searchButton)
    }

    public func dismissActiveAlertIfNeeded() {
        (window?.contentView as? PanelContentView)?.dismissModal()
    }

    private func setupViews() {
        titleLabel.stringValue = strings[.appTitle]
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureToolbarButton(
            searchButton,
            symbol: "magnifyingglass",
            tooltip: strings[.toolbarSearch],
            action: #selector(handleSearch)
        )
        configureToolbarButton(
            clearAllButton,
            symbol: "trash",
            tooltip: strings[.toolbarClearAll],
            action: #selector(handleClearAll)
        )
        configureToolbarButton(
            settingsButton,
            symbol: "gearshape",
            tooltip: strings[.toolbarSettings],
            action: #selector(handleSettings)
        )

        let buttonStack = NSStackView(views: [searchButton, clearAllButton, settingsButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 4
        buttonStack.alignment = .centerY
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(buttonStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
        ])
    }

    private func configureToolbarButton(
        _ button: NSButton,
        symbol: String,
        tooltip: String,
        action: Selector
    ) {
        let config = NSImage.SymbolConfiguration(pointSize: Metrics.toolbarIcon, weight: .regular)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        button.contentTintColor = .labelColor
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Metrics.toolbarButton),
            button.heightAnchor.constraint(equalToConstant: Metrics.toolbarButton),
        ])
    }

    private func bind() {
        totalCountCancellable = historyViewModel.$totalCount.sink { [weak self] count in
            self?.clearAllButton.isEnabled = (count > 0)
        }
    }

    @objc private func handleSearch() {
        searchViewModel.open()
    }

    @objc private func handleClearAll() {
        guard historyViewModel.totalCount > 0 else { return }
        let dialog = historyViewModel.clearConfirmation()
        guard let host = window?.contentView as? PanelContentView else {
            historyViewModel.clearAll()
            return
        }

        panelViewModel.setDialogOpen(true)
        let card = ModalDialogView(
            title: dialog.title,
            body: dialog.body,
            confirmTitle: dialog.confirm,
            cancelTitle: dialog.cancel,
            onConfirm: { [weak self, weak host] in
                guard let self else { return }
                host?.dismissModal(runCancel: false)
                self.panelViewModel.setDialogOpen(false)
                self.historyViewModel.clearAll()
            },
            onCancel: { [weak self, weak host] in
                guard let self else { return }
                host?.dismissModal(runCancel: false)
                self.panelViewModel.setDialogOpen(false)
            }
        )
        host.presentModal(card, initialFirstResponder: card) { [weak self] in
            self?.panelViewModel.setDialogOpen(false)
        }
    }

    @objc private func handleSettings() {
        panelViewModel.openSettings()
    }
}
