import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let clipboardChannel = FlutterMethodChannel(
      name: "sclip/clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    clipboardChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "currentIsSensitive":
        // Password managers (1Password, Bitwarden, Keychain) mark their
        // payload with org.nspasteboard.ConcealedType so clipboard managers
        // know to skip it. See http://nspasteboard.org/.
        let types = NSPasteboard.general.types ?? []
        let sensitive = types.contains { t in
          let s = t.rawValue
          return s == "org.nspasteboard.ConcealedType"
        }
        result(sensitive)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let channel = FlutterMethodChannel(
      name: "sclip/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "hideAndDeactivate":
        // NSApp.hide(nil) hides all our windows and hands focus back to the
        // next running app, so the user's previous context (e.g. editor) stays
        // active after dismissing sclip.
        NSApp.hide(nil)
        result(nil)
      case "pasteToPrevious":
        // Hide sclip so the previously active app regains focus, then post
        // Cmd+V into it. Requires Accessibility permission (System Settings →
        // Privacy & Security → Accessibility).
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
          let src = CGEventSource(stateID: .combinedSessionState)
          let vKey: CGKeyCode = 0x09
          let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
          let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
          down?.flags = .maskCommand
          up?.flags = .maskCommand
          down?.post(tap: .cghidEventTap)
          up?.post(tap: .cghidEventTap)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
