import AppKit
import Combine
import SclipCore
import SclipViewModels

@MainActor
public final class StatusItemController: NSObject {
    public let statusItem: NSStatusItem
    public let menu = NSMenu()
    public let toggleItem = NSMenuItem()
    public let pinItem = NSMenuItem()
    public let clearAllItem = NSMenuItem()
    public let settingsItem = NSMenuItem()
    public let quitItem = NSMenuItem()

    private let panelViewModel: PanelViewModel
    private let historyViewModel: HistoryViewModel
    private let strings: Strings
    private var pinnedCancellable: AnyCancellable?

    public init(
        panelViewModel: PanelViewModel,
        historyViewModel: HistoryViewModel,
        strings: Strings
    ) {
        self.panelViewModel = panelViewModel
        self.historyViewModel = historyViewModel
        self.strings = strings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        setupStatusItem()
        setupMenu()
        bind()
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        let title = strings[.appTitle]
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.image = Self.makeTemplateIcon()
    }

    private func setupMenu() {
        // B-6.7.1: Toggle · separator · Pin (checkbox) · separator · Clear All · separator · Settings · separator · Quit
        toggleItem.title = strings[.trayToggle]
        toggleItem.target = self
        toggleItem.action = #selector(handleToggle)

        pinItem.title = strings[.trayPin]
        pinItem.target = self
        pinItem.action = #selector(handleTogglePin)

        clearAllItem.title = strings[.trayClearAll]
        clearAllItem.target = self
        clearAllItem.action = #selector(handleClearAll)

        settingsItem.title = strings[.traySettings]
        settingsItem.target = self
        settingsItem.action = #selector(handleSettings)

        quitItem.title = strings[.trayQuit]
        quitItem.target = self
        quitItem.action = #selector(handleQuit)

        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(pinItem)
        menu.addItem(.separator())
        menu.addItem(clearAllItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func bind() {
        pinnedCancellable = panelViewModel.$pinned.sink { [weak self] pinned in
            self?.pinItem.state = pinned ? .on : .off
        }
    }

    @objc private func handleToggle() {
        panelViewModel.toggle(.tray)
    }

    @objc private func handleTogglePin() {
        panelViewModel.setPinned(!panelViewModel.pinned)
    }

    @objc private func handleClearAll() {
        // B-6.7.2: Clear all from tray deletes without confirmation.
        historyViewModel.clearAll()
    }

    @objc private func handleSettings() {
        // B-6.7.3: Shows panel and opens settings page.
        panelViewModel.openSettings()
        if panelViewModel.visibility != .shown {
            panelViewModel.toggle(.tray)
        }
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    private static func makeTemplateIcon() -> NSImage? {
        let svg = """
        <svg width="22" height="14" viewBox="0 0 44 28" xmlns="http://www.w3.org/2000/svg">
        <path d="M20.72 16C20.72 13.7333 21.1733 11.76 22.08 10.08C22.9867 8.37333 24.24 7.05333 25.84 6.12C27.4667 5.18667 29.32 4.72 31.4 4.72C34.0933 4.72 36.3067 5.37333 38.04 6.68C39.8 7.98667 40.96 9.8 41.52 12.12H37.6C37.2267 10.7867 36.4933 9.73333 35.4 8.96C34.3333 8.18667 33 7.8 31.4 7.8C29.32 7.8 27.64 8.52 26.36 9.96C25.08 11.3733 24.44 13.3867 24.44 16C24.44 18.64 25.08 20.68 26.36 22.12C27.64 23.56 29.32 24.28 31.4 24.28C33 24.28 34.3333 23.9067 35.4 23.16C36.4667 22.4133 37.2 21.3467 37.6 19.96H41.52C40.9333 22.2 39.76 24 38 25.36C36.24 26.6933 34.04 27.36 31.4 27.36C29.32 27.36 27.4667 26.8933 25.84 25.96C24.24 25.0267 22.9867 23.7067 22.08 22C21.1733 20.2933 20.72 18.2933 20.72 16Z" fill="black"/>
        <path d="M10.84 27.36C9.16 27.36 7.65333 27.08 6.32 26.52C4.98667 25.9333 3.93333 25.1333 3.16 24.12C2.38667 23.08 1.96 21.8933 1.88 20.56H5.64C5.74667 21.6533 6.25333 22.5467 7.16 23.24C8.09333 23.9333 9.30667 24.28 10.8 24.28C12.1867 24.28 13.28 23.9733 14.08 23.36C14.88 22.7467 15.28 21.9733 15.28 21.04C15.28 20.08 14.8533 19.3733 14 18.92C13.1467 18.44 11.8267 17.9733 10.04 17.52C8.41333 17.0933 7.08 16.6667 6.04 16.24C5.02667 15.7867 4.14667 15.1333 3.4 14.28C2.68 13.4 2.32 12.2533 2.32 10.84C2.32 9.72 2.65333 8.69333 3.32 7.76C3.98667 6.82667 4.93333 6.09333 6.16 5.56C7.38667 5 8.78667 4.72 10.36 4.72C12.7867 4.72 14.7467 5.33333 16.24 6.56C17.7333 7.78667 18.5333 9.46667 18.64 11.6H15C14.92 10.4533 14.4533 9.53333 13.6 8.84C12.7733 8.14667 11.6533 7.8 10.24 7.8C8.93333 7.8 7.89333 8.08 7.12 8.64C6.34667 9.2 5.96 9.93333 5.96 10.84C5.96 11.56 6.18667 12.16 6.64 12.64C7.12 13.0933 7.70667 13.4667 8.4 13.76C9.12 14.0267 10.1067 14.3333 11.36 14.68C12.9333 15.1067 14.2133 15.5333 15.2 15.96C16.1867 16.36 17.0267 16.9733 17.72 17.8C18.44 18.6267 18.8133 19.7067 18.84 21.04C18.84 22.24 18.5067 23.32 17.84 24.28C17.1733 25.24 16.2267 26 15 26.56C13.8 27.0933 12.4133 27.36 10.84 27.36Z" fill="black"/>
        </svg>
        """
        if let image = NSImage(data: Data(svg.utf8)), image.isValid {
            image.size = NSSize(width: 22, height: 14)
            image.isTemplate = true
            return image
        }
        let fallback = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "sclip")
        fallback?.isTemplate = true
        return fallback
    }
}
