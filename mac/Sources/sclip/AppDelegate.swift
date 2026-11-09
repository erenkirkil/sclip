import AppKit
import Foundation
import SclipPlatform
import SclipViewModels

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let bundleID: String
    private var container: AppContainer?
    private var didClaimSingleInstance = false

    public override init() {
        self.bundleID = Bundle.main.bundleIdentifier ?? "com.erenkirkil.sclip"
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let claimed = SingleInstance.claim(bundleID: bundleID) { [weak self] in
            self?.container?.panelViewModel.toggle(.secondInstance)
        }
        guard claimed else {
            NSApp.terminate(nil)
            return
        }
        didClaimSingleInstance = true
        container = AppContainer()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        container?.shutdown()
        if didClaimSingleInstance {
            SingleInstance.release(bundleID: bundleID)
        }
    }
}
