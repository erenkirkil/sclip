import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
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
