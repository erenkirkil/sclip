import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Keep a strong reference so App Nap stays disabled for the process lifetime.
  // Accessory-mode apps that are hidden get throttled by macOS, which pauses
  // the Dart clipboard polling Timer and causes us to miss copies made while
  // the window is hidden.
  private var activityToken: NSObjectProtocol?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    activityToken = ProcessInfo.processInfo.beginActivity(
      options: .userInitiatedAllowingIdleSystemSleep,
      reason: "sclip clipboard polling"
    )
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    // window_manager's focus() flips policy to .regular, which adds the app
    // to the Dock and Cmd+Tab. Keep it pinned to .accessory.
    if NSApp.activationPolicy() != .accessory {
      NSApp.setActivationPolicy(.accessory)
    }
    super.applicationDidBecomeActive(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
