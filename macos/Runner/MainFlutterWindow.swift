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
        // Combined probe: monotonic change counter + concealed-type check
        // + file-promise short-circuit. changeCount lets the Dart side
        // skip ticks when the pasteboard hasn't moved. Concealed type
        // (org.nspasteboard.ConcealedType) is the cross-app convention
        // password managers set to opt out of history managers — see
        // http://nspasteboard.org/. hasFilePromise flags any payload
        // carrying NSFilePromise identifiers so the Dart side can skip
        // super_clipboard's read — touching a promise resolves it and
        // silently empties the source app's clipboard, breaking the
        // user's own Cmd+V (Finder, Android Studio, Xcode all do this).
        // We check "has promise" rather than "is file-only" because
        // Finder routinely adds public.utf8-plain-text (the filename)
        // alongside the promise; skipping requires spotting the promise,
        // not proving nothing else is there.
        let pb = NSPasteboard.general
        let change = pb.changeCount
        let types = pb.types ?? []
        let sensitive = types.contains { $0.rawValue == "org.nspasteboard.ConcealedType" }
        let promiseTypes: Set<String> = [
          "com.apple.pasteboard.promised-file-url",
          "com.apple.pasteboard.promised-file-name",
          "com.apple.pasteboard.promised-file-content-type",
          "com.apple.pasteboard.PromisedFileURL",
          "com.apple.pasteboard.PromisedFileName",
          "com.apple.pasteboard.PromisedFileContentType",
        ]
        let hasFilePromise = types.contains { promiseTypes.contains($0.rawValue) }
        result([
          "change": change,
          "sensitive": sensitive,
          "hasFilePromise": hasFilePromise,
        ])
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
