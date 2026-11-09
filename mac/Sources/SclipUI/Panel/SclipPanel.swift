import AppKit

@MainActor
public final class SclipPanel: NSPanel {
    public var onKeyEvent: ((NSEvent) -> Bool)?
    public var onCloseCommand: (() -> Void)?

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .nonactivatingPanel,
                .titled,
                .closable,
                .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = .floating
        minSize = Metrics.panelMinSize
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false

        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            if key == "w" {
                onCloseCommand?()
                return true
            }
            if let textView = firstResponder as? NSTextView {
                switch key {
                case "a":
                    textView.selectAll(nil)
                    return true
                case "c":
                    textView.copy(nil)
                    return true
                case "v":
                    textView.paste(nil)
                    return true
                case "x":
                    textView.cut(nil)
                    return true
                case "z":
                    textView.undoManager?.undo()
                    return true
                default:
                    break
                }
            }
        }
        if let onKeyEvent, onKeyEvent(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override public func keyDown(with event: NSEvent) {
        if let onKeyEvent, onKeyEvent(event) {
            return
        }
        super.keyDown(with: event)
    }

    override public func cancelOperation(_ sender: Any?) {
        if let event = NSApp.currentEvent, let onKeyEvent, onKeyEvent(event) {
            return
        }
    }
}
