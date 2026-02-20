import AppKit

@MainActor
final class StatusBarController: NSObject {
    var onOpen: (() -> Void)?
    var onChangeShortcut: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private lazy var openItem = NSMenuItem(title: "Open Clipboard", action: #selector(openFromMenu), keyEquivalent: "")
    private lazy var changeShortcutItem = NSMenuItem(title: "Change Global Shortcut…", action: #selector(changeShortcutFromMenu), keyEquivalent: "")
    private lazy var settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: ",")
    private lazy var quitItem = NSMenuItem(title: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q")
    private var errorItem: NSMenuItem?

    override init() {
        super.init()
        setupStatusButton()
        setupMenu()
    }

    func update(openTitle: String, isRecording: Bool, error: String?) {
        openItem.title = openTitle
        changeShortcutItem.title = isRecording ? "Recording shortcut…" : "Change Global Shortcut…"
        changeShortcutItem.isEnabled = !isRecording

        if let error, !error.isEmpty {
            if errorItem == nil {
                let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.attributedTitle = NSAttributedString(
                    string: error,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
                errorItem = item
            } else {
                errorItem?.title = error
                errorItem?.attributedTitle = NSAttributedString(
                    string: error,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            }

            if let errorItem, !menu.items.contains(errorItem) {
                menu.insertItem(errorItem, at: 3)
            }
        } else if let errorItem, menu.items.contains(errorItem) {
            menu.removeItem(errorItem)
        }
    }

    private func setupStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "CBManager")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(statusButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupMenu() {
        openItem.target = self
        changeShortcutItem.target = self
        settingsItem.target = self
        quitItem.target = self

        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(changeShortcutItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true

        if isRightClick {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onOpen?()
        }
    }

    @objc private func openFromMenu() {
        onOpen?()
    }

    @objc private func changeShortcutFromMenu() {
        onChangeShortcut?()
    }

    @objc private func settingsFromMenu() {
        onSettings?()
    }

    @objc private func quitFromMenu() {
        onQuit?()
    }
}
