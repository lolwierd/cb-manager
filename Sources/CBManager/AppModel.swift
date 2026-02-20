import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var shortcut: HotKeyShortcut
    @Published var isRecordingShortcut = false
    @Published var shortcutError: String?

    let store = ClipboardStore()
    private let hotKey = GlobalHotKey()
    private let shortcutRecorder = ShortcutRecorderPanelController()
    private let statusBar = StatusBarController()
    private lazy var panelController = OverlayPanelController(store: store)

    private let shortcutDefaultsKey = "globalShortcutV2"
    private let settingsURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CBManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        settingsURL = appSupport.appendingPathComponent("settings.json")

        if let saved = Self.loadShortcutFromSettings(at: settingsURL) {
            shortcut = saved
        } else if let data = UserDefaults.standard.data(forKey: shortcutDefaultsKey),
                  let migrated = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) {
            shortcut = migrated
            Self.saveShortcutToSettings(migrated, at: settingsURL)
        } else {
            shortcut = .fallback
        }

        hotKey.onPressed = { [weak self] in
            self?.toggleOverlay()
        }

        if !hotKey.register(shortcut) {
            shortcut = .fallback
            _ = hotKey.register(.fallback)
        }

        statusBar.onOpen = { [weak self] in
            self?.toggleOverlay()
        }
        statusBar.onChangeShortcut = { [weak self] in
            self?.beginShortcutRecording()
        }
        statusBar.onQuit = {
            NSApplication.shared.terminate(nil)
        }

        refreshStatusBarMenu()
    }

    func beginShortcutRecording() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        shortcutError = nil
        refreshStatusBarMenu()

        let previous = shortcut
        shortcutRecorder.present(current: previous) { [weak self] captured in
            guard let self else { return }
            self.isRecordingShortcut = false

            guard let captured else {
                self.refreshStatusBarMenu()
                return
            }

            guard self.hotKey.register(captured) else {
                _ = self.hotKey.register(previous)
                self.shortcutError = "Shortcut unavailable. Try another combination."
                self.refreshStatusBarMenu()
                return
            }

            self.shortcut = captured
            self.shortcutError = nil
            if let data = try? JSONEncoder().encode(captured) {
                UserDefaults.standard.set(data, forKey: self.shortcutDefaultsKey)
            }
            Self.saveShortcutToSettings(captured, at: self.settingsURL)
            self.refreshStatusBarMenu()
        }
    }

    func toggleOverlay() {
        panelController.toggle()
        refreshStatusBarMenu()
    }

    func showOverlay() {
        panelController.show()
        refreshStatusBarMenu()
    }

    private func refreshStatusBarMenu() {
        statusBar.update(
            openTitle: "Toggle Clipboard (\(shortcut.title))",
            isRecording: isRecordingShortcut,
            error: shortcutError
        )
    }

    private static func loadShortcutFromSettings(at url: URL) -> HotKeyShortcut? {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return nil
        }
        return settings.shortcut
    }

    private static func saveShortcutToSettings(_ shortcut: HotKeyShortcut, at url: URL) {
        let settings = AppSettings(shortcut: shortcut)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private struct AppSettings: Codable {
    let shortcut: HotKeyShortcut
}
