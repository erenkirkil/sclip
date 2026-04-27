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
        // + file-presence flag. changeCount lets the Dart side skip ticks
        // when the pasteboard hasn't moved. Concealed type
        // (org.nspasteboard.ConcealedType) is the cross-app convention
        // password managers set to opt out of history managers — see
        // http://nspasteboard.org/. hasFiles covers both NSURL items
        // (Finder direct copy) and NSFilePromise items (Xcode, some
        // Finder bundle copies); the Dart side dispatches `readFiles`
        // instead of super_clipboard's read because resolving a promise
        // through super_clipboard's normal path empties the source
        // app's clipboard and breaks the user's own Cmd+V.
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
        let hasFileUrl = types.contains { $0.rawValue == "public.file-url" }
        let hasFiles = hasFilePromise || hasFileUrl
        result([
          "change": change,
          "sensitive": sensitive,
          "hasFiles": hasFiles,
        ])
      case "readFiles":
        // Resolves a "files-on-clipboard" payload into a flat list of paths
        // the Dart side can wrap as a `ClipboardEntry.files` entry. Two
        // sources, two strategies:
        //
        //   1. Direct NSURL — the common Finder-Cmd+C path. Reading these
        //      via `readObjects(forClasses: [NSURL.self])` is non-
        //      destructive: the source clipboard stays intact, no I/O,
        //      no temp files. We try this first.
        //
        //   2. NSFilePromiseReceiver — the Xcode / asset-catalog / some-
        //      Finder-bundle path. Apple's contract here is destructive:
        //      `receivePromisedFiles` copies bytes into our destination
        //      dir and the source's clipboard is effectively spent
        //      afterwards (the user's own Cmd+V into the originating app
        //      stops working). We compensate by republishing the
        //      resolved file URLs back to the pasteboard so the user
        //      gets a usable clipboard back. The Dart side's
        //      `_lastSignature` dedup catches the resulting changeCount
        //      bump so we don't re-ingest our own write.
        //
        // Args: { "entryId": String } — used as the destination dir
        // component under <NSTemporaryDirectory>/sclip/<entryId>/ so
        // the per-entry cleanup hook on Dart eviction can prune in one
        // shot.
        let pb = NSPasteboard.general
        let args = call.arguments as? [String: Any]
        let entryId = (args?["entryId"] as? String) ?? UUID().uuidString
        let types = pb.types ?? []
        let hasFileUrl = types.contains { $0.rawValue == "public.file-url" }

        if hasFileUrl,
           let urls = pb.readObjects(
             forClasses: [NSURL.self],
             options: [.urlReadingFileURLsOnly: true]
           ) as? [URL],
           !urls.isEmpty {
          result(urls.map { $0.path })
          return
        }

        guard let promises = pb.readObjects(
                forClasses: [NSFilePromiseReceiver.self],
                options: nil) as? [NSFilePromiseReceiver],
              !promises.isEmpty else {
          result([])
          return
        }

        let destDir = (NSTemporaryDirectory() as NSString)
          .appendingPathComponent("sclip")
        let entryDir = (destDir as NSString).appendingPathComponent(entryId)
        let entryURL = URL(fileURLWithPath: entryDir, isDirectory: true)
        do {
          try FileManager.default.createDirectory(
            at: entryURL,
            withIntermediateDirectories: true,
            attributes: nil)
        } catch {
          NSLog("sclip: createDirectory failed for promise dest: \(error)")
          result([])
          return
        }

        // Apple's docs recommend a serial OperationQueue for promise
        // resolution — concurrent receives on the same queue can race on
        // identical destination filenames and produce surprises.
        let opQueue = OperationQueue()
        opQueue.maxConcurrentOperationCount = 1
        let group = DispatchGroup()
        let lock = NSLock()
        var resolved: [URL] = []

        for promise in promises {
          group.enter()
          promise.receivePromisedFiles(
            atDestination: entryURL,
            options: [:],
            operationQueue: opQueue
          ) { fileURL, error in
            if let error = error {
              NSLog("sclip: promise resolution failed: \(error)")
            } else {
              lock.lock()
              resolved.append(fileURL)
              lock.unlock()
            }
            group.leave()
          }
        }

        group.notify(queue: .main) {
          if !resolved.isEmpty {
            // Source pasteboard is now spent — its promise is consumed.
            // Republish resolved URLs as plain file references so the
            // user's clipboard is still useful afterwards.
            pb.clearContents()
            pb.writeObjects(resolved.map { $0 as NSURL })
          }
          result(resolved.map { $0.path })
        }
      case "writeFiles":
        // Authoritative path for publishing files back to the pasteboard.
        // We build NSPasteboardItem instances explicitly instead of
        // letting `pb.writeObjects([NSURL])` auto-derive types — that
        // route attaches `public.url` (and a few other URL-flavored
        // siblings) alongside the file URL, and Telegram on macOS
        // currently routes such payloads through a different (and
        // broken-for-non-image-files) drop handler. Mirroring
        // super_clipboard's minimal per-item `public.file-url` layout
        // keeps Telegram / Slack / Mail attachments working. We then
        // attach the legacy `NSFilenamesPboardType` list to item 0 so
        // Finder's "Edit > Paste Item" still lights up the way it does
        // for a Finder→Finder copy. Empty input is a no-op so a
        // misdispatched call can't wipe the user's clipboard.
        let pb = NSPasteboard.general
        let args = call.arguments as? [String: Any]
        let paths = (args?["paths"] as? [String]) ?? []
        let cleanedPaths = paths.filter { !$0.isEmpty }
        if cleanedPaths.isEmpty {
          result(nil)
          return
        }
        let urls = cleanedPaths.map { URL(fileURLWithPath: $0) }
        let fileURLType = NSPasteboard.PasteboardType("public.file-url")
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        pb.clearContents()
        var items: [NSPasteboardItem] = []
        for (index, url) in urls.enumerated() {
          let item = NSPasteboardItem()
          item.setString(url.absoluteString, forType: fileURLType)
          if index == 0 {
            // NSFilenamesPboardType is a pasteboard-level combined list
            // (read by Finder via pb.propertyList(forType:)); writing it
            // on item 0 satisfies that read without polluting per-item
            // data for apps that iterate items individually.
            item.setPropertyList(cleanedPaths, forType: filenamesType)
          }
          items.append(item)
        }
        pb.writeObjects(items)
        result(nil)
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
      case "screenLayout":
        // Returns cursor + every visible display in a single, consistent
        // top-left flipped coordinate space anchored to the primary
        // display's frame height. We roll our own because screen_retriever
        // 0.2.0 flips cursor Y against `min(frame.maxY)` but flips display
        // Y against `primary.frame.height` — the two don't agree on
        // multi-monitor layouts where the secondary has a different height
        // or sits next to the primary, so cursor containment fails.
        let screens = NSScreen.screens
        guard let primary = screens.first else {
          result(["cursor": ["dx": 0.0, "dy": 0.0], "displays": []])
          return
        }
        let primaryHeight = primary.frame.height
        let mouse = NSEvent.mouseLocation
        let displays: [NSDictionary] = screens.map { s in
          let vf = s.visibleFrame
          let f = s.frame
          // `visible` excludes the menu bar / dock — use for window
          // clamping so sclip never slides under them. `full` includes
          // the menu bar — used for cursor containment because tray
          // icons live ON the menu bar, and otherwise a tray click
          // lands cursor.y "above" every visible rect and we
          // misattribute the display.
          let visibleTopLeftY = primaryHeight - vf.origin.y - vf.height
          let fullTopLeftY = primaryHeight - f.origin.y - f.height
          let screenID = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
          return [
            "id": "\(screenID)",
            "x": vf.origin.x,
            "y": visibleTopLeftY,
            "width": vf.width,
            "height": vf.height,
            "fullX": f.origin.x,
            "fullY": fullTopLeftY,
            "fullWidth": f.width,
            "fullHeight": f.height,
            "scaleFactor": s.backingScaleFactor,
          ] as NSDictionary
        }
        result([
          "cursor": [
            "dx": mouse.x,
            "dy": primaryHeight - mouse.y,
          ],
          "displays": displays,
        ])
      case "pasteToPrevious":
        // Capture the frontmost app pid *before* we hide sclip. After the
        // 120 ms settle we verify the same app is still frontmost — if the
        // user switched windows during the race window we skip injection
        // rather than pasting into the wrong target.
        let targetPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
          let currentPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
          guard let expected = targetPid, let actual = currentPid, expected == actual else {
            // Foreground changed during the race window — abort paste.
            NSLog("[sclip] pasteToPrevious aborted: foreground pid changed (%@ → %@)",
                  String(describing: targetPid), String(describing: currentPid))
            return
          }
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
