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
      case "currentState":
        // Combined probe: monotonic change counter + concealed-type check.
        // changeCount lets the Dart side skip ticks when the pasteboard
        // hasn't moved. Concealed type (org.nspasteboard.ConcealedType) is
        // the cross-app convention password managers set to opt out of
        // history managers — see http://nspasteboard.org/.
        let pb = NSPasteboard.general
        let change = pb.changeCount
        let types = pb.types ?? []
        let sensitive = types.contains { $0.rawValue == "org.nspasteboard.ConcealedType" }
        result(["change": change, "sensitive": sensitive])
      case "isAccessibilityTrusted":
        // Cmd+V posting via CGEvent requires Accessibility permission.
        // Without it, pasteToPrevious silently fails — let Dart side know
        // so it can surface a one-time banner pointing the user at System
        // Settings.
        result(AXIsProcessTrusted())
      case "openAccessibilitySettings":
        let url = URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
        result(nil)
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
