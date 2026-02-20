import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        model = AppModel()
    }

    /// Minimal main menu so standard key equivalents (⌘W, ⌘Q) work.
    /// Menu bar apps don't show the menu bar, but AppKit still dispatches
    /// shortcuts through it when a window is key.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // App menu (required root item)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitItem = appMenu.addItem(withTitle: "Quit CBManager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu (⌘W lives here)
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let closeItem = fileMenu.addItem(withTitle: "Close Window", action: #selector(closeWindowFromMenu(_:)), keyEquivalent: "w")
        closeItem.target = self
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func closeWindowFromMenu(_ sender: Any?) {
        if model?.handleCloseWindowCommand() == true {
            return
        }
        NSApp.keyWindow?.performClose(sender)
    }
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
