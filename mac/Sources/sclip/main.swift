import AppKit

// Yer tutucu iskelet: Task 30'da gerçek AppDelegate/menü bağlanana dek tek bir durum öğesi.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
if let button = statusItem.button {
    let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "sclip")
    image?.isTemplate = true
    button.image = image
}

let menu = NSMenu()
menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
statusItem.menu = menu

app.run()
