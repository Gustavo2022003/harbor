import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController!
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController()
        controller.start()
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "Harbor")
        let menu = NSMenu()
        menu.addItem(withTitle: "Abrir Harbor", action: #selector(openNook), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair do Harbor", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { controller.handle(url: $0) }
    }

    @objc private func openNook() { controller.open(tab: .nook, pinned: true) }
    @objc private func openSettings() { controller.open(tab: .settings, pinned: true) }
    @objc private func quit() { NSApp.terminate(nil) }
}
