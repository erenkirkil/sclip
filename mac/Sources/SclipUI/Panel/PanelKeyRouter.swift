import AppKit
import SclipViewModels

@MainActor
public final class PanelKeyRouter {
    public var onDismissActiveDialog: (() -> Void)?

    private let panelViewModel: PanelViewModel
    private let searchViewModel: SearchViewModel

    public init(panelViewModel: PanelViewModel, searchViewModel: SearchViewModel) {
        self.panelViewModel = panelViewModel
        self.searchViewModel = searchViewModel
    }

    public func install(on panel: SclipPanel) {
        panel.onKeyEvent = { [weak self] event in
            self?.handle(event) ?? false
        }
    }

    public func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        // Esc (keyCode 53): single press closes one layer (dialog -> settings -> search -> panel)
        if event.keyCode == 53 {
            if panelViewModel.dialogOpen {
                onDismissActiveDialog?()
            }
            panelViewModel.escape()
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let chars = event.charactersIgnoringModifiers?.lowercased() {
            if chars == "f", panelViewModel.page == .history, !panelViewModel.dialogOpen {
                searchViewModel.open()
                return true
            }
            if chars == ",", panelViewModel.page == .history, !panelViewModel.dialogOpen {
                panelViewModel.openSettings()
                return true
            }
        }

        return false
    }
}
