import AppKit
import Combine
import Foundation
import SclipCore
import SclipPlatform
import SclipUI
import SclipViewModels

@MainActor
public final class AppContainer: RefreshPort {
    public let strings: Strings
    public let clock = SystemClock()
    public let ids = EntryIDGenerator()
    public let classifier = Classifier()

    public let settingsStore: UserDefaultsSettingsStore
    public private(set) var hotkeyRegistrar: CarbonHotkey!
    public private(set) var settingsViewModel: SettingsViewModel!

    public private(set) var promiseReader: FilePromiseReader!
    public private(set) var pasteboardReader: PasteboardReader!
    public private(set) var captureEngine: CaptureEngine!
    public private(set) var tempStore: FileTempStore!
    public private(set) var historyStore: HistoryStore!
    public private(set) var pasteboardWriter: PasteboardWriter!
    public let paster = CGEventPaster()

    public let searchViewModel = SearchViewModel()
    public let bannerViewModel = BannerViewModel()
    public private(set) var historyViewModel: HistoryViewModel!
    public private(set) var panelViewModel: PanelViewModel!

    public private(set) var toolbarView: ToolbarView!
    public private(set) var bannerStackView: BannerStackView!
    public private(set) var searchBarView: SearchBarView!
    public private(set) var historyTableView: HistoryTableView!
    public private(set) var settingsView: SettingsView!
    public private(set) var panelController: PanelController!
    public private(set) var keyRouter: PanelKeyRouter!
    public private(set) var statusItemController: StatusItemController!

    public private(set) var pasteboardMonitor: PasteboardMonitor!
    public private(set) var screenLockMonitor: ScreenLockMonitor!

    private var activityToken: NSObjectProtocol?
    private var accessibilityTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    public init() {
        self.strings = Self.loadStrings()
        self.settingsStore = UserDefaultsSettingsStore()

        self.activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Clipboard monitoring"
        )

        setupCoreAndViewModels()
        setupViewsAndPanel()
        setupBindingsAndMonitors()
    }

    public func refreshNow() {
        checkAccessibilityTrust()
        if let entry = captureEngine.tick() {
            historyViewModel.ingest(entry)
        }
    }

    public func shutdown() {
        pasteboardMonitor?.stop()
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        tempStore?.pruneAll()
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
    }

    // MARK: - Setup Phases

    private func setupCoreAndViewModels() {
        hotkeyRegistrar = CarbonHotkey { [weak self] in
            self?.panelViewModel?.toggle(.hotkey)
        }
        settingsViewModel = SettingsViewModel(store: settingsStore, hotkeys: hotkeyRegistrar)

        let tempRoot = FileManager.default.temporaryDirectory
        promiseReader = FilePromiseReader(root: tempRoot)
        let pr = promiseReader!
        pasteboardReader = PasteboardReader(
            pasteboard: .general,
            receivePromises: { pb, id in pr.receive(from: pb, into: id) },
            cancelPromises: { pr.cancelCurrentAttempt() }
        )

        captureEngine = CaptureEngine(
            source: pasteboardReader,
            classifier: classifier,
            ids: ids,
            clock: clock,
            sensitiveFilter: settingsViewModel.sensitiveFilter
        )

        tempStore = FileTempStore(
            root: tempRoot,
            isOnPasteboard: { [weak self] entry in
                entry.contentHash == self?.captureEngine?.lastSignature
            }
        )
        // B-8.4.3: Prune stale temp files on startup.
        tempStore.pruneAll()

        let ts = tempStore!
        historyStore = HistoryStore(
            maxItems: settingsViewModel.maxItems,
            onEvict: { entry in
                ts.delete(entry)
                MainActor.assumeIsolated {
                    ThumbnailCache.shared.remove(entryID: entry.id)
                }
            }
        )

        pasteboardWriter = PasteboardWriter(pasteboard: .general, temp: tempStore)

        let ce = captureEngine!
        historyViewModel = HistoryViewModel(
            store: historyStore,
            search: searchViewModel,
            strings: strings,
            clock: clock,
            resetBaseline: {
                pr.cancelCurrentAttempt()
                ce.resetBaseline()
                MainActor.assumeIsolated {
                    ThumbnailCache.shared.clear()
                }
            }
        )

        // Initial baseline tick (B-8.8.5) and clearOnStartup (B-8.8.11)
        _ = captureEngine.tick()
        if settingsViewModel.clearOnStartup {
            historyViewModel.clearAll()
        }
    }

    private func setupViewsAndPanel() {
        let placeholderHistoryContainer = NSView(frame: .zero)
        let placeholderSettingsContainer = NSView(frame: .zero)

        panelController = PanelController(
            content: placeholderHistoryContainer,
            settings: placeholderSettingsContainer,
            title: strings[.appTitle]
        )

        panelViewModel = PanelViewModel(
            window: panelController,
            paster: paster,
            sink: pasteboardWriter,
            refresh: self,
            clock: clock,
            pinned: settingsViewModel.alwaysOnTopDefault,
            autoHideOnBlur: settingsViewModel.autoHideOnBlur
        )
        panelViewModel.alwaysPastePlainText = settingsViewModel.alwaysPastePlainText
        panelViewModel.searchOpen = { [weak self] in self?.searchViewModel.isOpen ?? false }
        panelViewModel.closeSearch = { [weak self] in
            guard let self else { return }
            self.searchViewModel.close()
            self.historyTableView.focusFirstRow()
        }
        panelViewModel.onHidden = { [weak self] in
            guard let self else { return }
            self.toolbarView?.dismissActiveAlertIfNeeded()
            self.settingsView?.dismissActiveModalIfNeeded()
            if self.panelViewModel.dialogOpen {
                self.panelViewModel.setDialogOpen(false)
            }
            self.searchViewModel.clearQuery()
        }
        panelViewModel.onOwnWrite = { [weak self] receipt in self?.captureEngine.noteOwnWrite(receipt) }
        panelViewModel.onTouch = { [weak self] id in self?.historyViewModel.touch(id) }

        toolbarView = ToolbarView(
            panelViewModel: panelViewModel,
            historyViewModel: historyViewModel,
            searchViewModel: searchViewModel,
            strings: strings
        )
        bannerStackView = BannerStackView(bannerViewModel: bannerViewModel, strings: strings)
        searchBarView = SearchBarView(searchViewModel: searchViewModel, strings: strings)
        historyTableView = HistoryTableView(
            historyViewModel: historyViewModel,
            panelViewModel: panelViewModel,
            searchViewModel: searchViewModel,
            strings: strings,
            clock: clock
        )
        settingsView = SettingsView(
            settingsViewModel: settingsViewModel,
            panelViewModel: panelViewModel,
            strings: strings
        )

        assembleHistoryPage(into: placeholderHistoryContainer)
        assembleSettingsPage(into: placeholderSettingsContainer)

        panelController.bind(viewModel: panelViewModel)
        panelController.onFocusTarget = { [weak self] target in
            guard let self else { return }
            switch target {
            case .firstRow:
                self.historyTableView.focusFirstRow()
            case .searchField:
                self.searchBarView.focusAndSelectAll()
            case .settings:
                self.settingsView.focusInitialControl()
            }
        }

        keyRouter = PanelKeyRouter(panelViewModel: panelViewModel, searchViewModel: searchViewModel)
        keyRouter.onDismissActiveDialog = { [weak self] in
            self?.toolbarView.dismissActiveAlertIfNeeded()
            self?.settingsView.dismissActiveModalIfNeeded()
        }
        keyRouter.install(on: panelController.panel)

        statusItemController = StatusItemController(
            panelViewModel: panelViewModel,
            historyViewModel: historyViewModel,
            strings: strings
        )
    }

    private func assembleHistoryPage(into container: NSView) {
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        bannerStackView.translatesAutoresizingMaskIntoConstraints = false
        searchBarView.translatesAutoresizingMaskIntoConstraints = false
        historyTableView.translatesAutoresizingMaskIntoConstraints = false

        let topStack = NSStackView(views: [toolbarView, bannerStackView, searchBarView])
        topStack.orientation = .vertical
        topStack.alignment = .leading
        topStack.spacing = 4
        topStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(topStack)
        container.addSubview(historyTableView)

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: container.topAnchor),
            topStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            toolbarView.widthAnchor.constraint(equalTo: topStack.widthAnchor),
            bannerStackView.widthAnchor.constraint(equalTo: topStack.widthAnchor),
            searchBarView.widthAnchor.constraint(equalTo: topStack.widthAnchor),

            historyTableView.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 4),
            historyTableView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            historyTableView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            historyTableView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        searchBarView.onSearchFocused = { [weak self] in
            self?.historyTableView.setFocusedRow(nil)
        }
        searchBarView.onMoveToFirstRow = { [weak self] in
            self?.historyTableView.focusFirstRow()
        }
        searchBarView.onSubmitFirstMatch = { [weak self] in
            self?.historyTableView.focusFirstRow()
        }
        searchBarView.onEscape = { [weak self] in
            self?.panelViewModel.escape()
        }

        historyTableView.onMoveUpFromFirstRow = { [weak self] in
            guard let self else { return }
            if self.searchViewModel.isOpen {
                self.searchBarView.focusAndSelectAll()
            } else {
                self.toolbarView.focusFirstButton()
            }
        }

        bannerStackView.onOpenAccessibilitySettings = {
            AccessibilityPermission.openSettings()
        }
        bannerStackView.onOpenHotkeySettings = { [weak self] in
            self?.panelViewModel.openSettings()
        }
        bannerStackView.onDismissLockCleared = { [weak self] in
            self?.bannerViewModel.dismissLockCleared()
        }
    }

    private func assembleSettingsPage(into container: NSView) {
        settingsView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(settingsView)
        NSLayoutConstraint.activate([
            settingsView.topAnchor.constraint(equalTo: container.topAnchor),
            settingsView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            settingsView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            settingsView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func setupBindingsAndMonitors() {
        settingsViewModel.registerInitialHotkey()

        settingsViewModel.$registeredHotkey.sink { [weak self] combo in
            self?.bannerViewModel.setHotkeyRegistered(combo != nil)
        }.store(in: &cancellables)

        settingsViewModel.$themeMode.sink { [weak self] mode in
            AppearanceApplier.apply(mode, to: self?.panelController.panel)
        }.store(in: &cancellables)

        settingsViewModel.$maxItems.sink { [weak self] val in
            self?.historyStore.maxItems = val
        }.store(in: &cancellables)

        settingsViewModel.$sensitiveFilter.sink { [weak self] val in
            self?.captureEngine.sensitiveFilter = val
        }.store(in: &cancellables)

        settingsViewModel.$autoHideOnBlur.sink { [weak self] val in
            self?.panelViewModel.autoHideOnBlur = val
        }.store(in: &cancellables)

        settingsViewModel.$alwaysOnTopDefault.dropFirst().sink { [weak self] val in
            self?.panelViewModel.setPinned(val)
        }.store(in: &cancellables)

        settingsViewModel.$alwaysPastePlainText.sink { [weak self] val in
            self?.panelViewModel.alwaysPastePlainText = val
        }.store(in: &cancellables)

        let initialInterval = TimeInterval(settingsViewModel.pollingIntervalMs) / 1000.0
        pasteboardMonitor = PasteboardMonitor(interval: initialInterval) { [weak self] in
            guard let self else { return }
            if let entry = self.captureEngine.tick() {
                self.historyViewModel.ingest(entry)
            }
        }
        pasteboardMonitor.start()

        settingsViewModel.$pollingIntervalMs.dropFirst().sink { [weak self] ms in
            self?.pasteboardMonitor.interval = TimeInterval(ms) / 1000.0
        }.store(in: &cancellables)

        screenLockMonitor = ScreenLockMonitor { [weak self] in
            guard let self, self.settingsViewModel.clearOnScreenLock else { return }
            let hadEntries = !self.historyStore.entries.isEmpty
            self.historyViewModel.clearAll()
            self.bannerViewModel.lockCleared(hadEntries: hadEntries)
        }

        checkAccessibilityTrust()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkAccessibilityTrust()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        accessibilityTimer = timer
    }

    private func checkAccessibilityTrust() {
        bannerViewModel.setAccessibilityTrusted(AccessibilityPermission.isTrusted())
    }

    private static func loadStrings() -> Strings {
        if let url = Bundle.main.url(forResource: "strings.tr", withExtension: "json"),
           let loaded = try? Strings.load(from: url)
        {
            return loaded
        }
        let devURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("spec/strings.tr.json")
        if let loaded = try? Strings.load(from: devURL) {
            return loaded
        }
        fatalError("Failed to load strings.tr.json")
    }
}
