import AppKit
import SwiftUI

@MainActor
final class SettingsPanelController {
    private var window: NSWindow?
    private var settingsModel: SettingsModel?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show(settingsURL: URL, onChanged: @escaping (SettingsModel.SettingsSnapshot) -> Void) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let model = SettingsModel(settingsURL: settingsURL, onChanged: onChanged)
        self.settingsModel = model

        let view = SettingsView(settingsModel: model)
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CBManager Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.contentView = hostingView
        window.center()
        window.level = .floating
        window.isReleasedWhenClosed = false

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
        settingsModel = nil
    }
}
