import AppKit
import Combine
import SclipCore
import SclipPlatform
import SclipViewModels

@MainActor
public final class PanelController: NSObject, PanelWindowPort, NSWindowDelegate {
    public let panel: SclipPanel
    public let containerView: PanelContentView
    public var onFocusTarget: ((FocusTarget) -> Void)?

    private weak var viewModel: PanelViewModel?
    private var pageCancellable: AnyCancellable?
    private var hasShownOnce = false

    public init(content: NSView, settings: NSView, title: String = "sclip") {
        let initialRect = NSRect(origin: .zero, size: Metrics.panelDefaultSize)
        self.panel = SclipPanel(contentRect: initialRect)
        self.containerView = PanelContentView(content: content, settings: settings)
        super.init()

        panel.title = title
        panel.delegate = self
        panel.contentView = containerView
        panel.onCloseCommand = { [weak self] in
            self?.viewModel?.requestHide()
        }
    }

    public convenience init(
        viewModel: PanelViewModel,
        content: NSView,
        settings: NSView,
        title: String = "sclip"
    ) {
        self.init(content: content, settings: settings, title: title)
        bind(viewModel: viewModel)
    }

    public func bind(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        pageCancellable = viewModel.$page.sink { [weak self] page in
            guard let self else { return }
            self.containerView.showPage(page)
            if self.panel.isVisible {
                if page == .settings {
                    self.focus(.settings)
                } else {
                    let target: FocusTarget = viewModel.searchOpen() ? .searchField : .firstRow
                    self.focus(target)
                }
            }
        }
    }

    public var isKey: Bool {
        panel.isKeyWindow
    }

    public func show() {
        let (cursor, screens) = ScreenLocator.current()
        let size = panel.frame.size

        if !hasShownOnce {
            hasShownOnce = true
            panel.setContentSize(Metrics.panelDefaultSize)
            let origin = Self.centeredOrigin(cursor: cursor, screens: screens, size: panel.frame.size)
            panel.setFrameOrigin(origin)
        } else {
            let origin = PanelPlacement.origin(cursor: cursor, screens: screens, size: size)
            panel.setFrameOrigin(origin)
        }

        panel.orderFrontRegardless()
        panel.makeKey()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    public func focus(_ target: FocusTarget) {
        onFocusTarget?(target)
    }

    // MARK: - NSWindowDelegate

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        viewModel?.requestHide()
        return false
    }

    public func windowDidResignKey(_ notification: Notification) {
        viewModel?.blur()
    }

    // MARK: - Helpers

    private static func centeredOrigin(cursor: CGPoint, screens: [ScreenArea], size: CGSize) -> CGPoint {
        let targetScreen = screens.first { screen in
            let f = screen.frame
            return cursor.x >= f.origin.x
                && cursor.x < f.origin.x + f.size.width
                && cursor.y >= f.origin.y
                && cursor.y <= f.origin.y + f.size.height
        } ?? screens.first

        guard let area = targetScreen?.visible else {
            return CGPoint(x: cursor.x - size.width / 2, y: cursor.y - size.height / 2)
        }

        let x = area.origin.x + (area.size.width - size.width) / 2
        let y = area.origin.y + (area.size.height - size.height) / 2
        return CGPoint(x: x, y: y)
    }
}
