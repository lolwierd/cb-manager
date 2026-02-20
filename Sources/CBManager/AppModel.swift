import AppKit
import Foundation

@MainActor
final class AppModel {
    private(set) var shortcut: HotKeyShortcut
    private var isRecordingShortcut = false
    private var shortcutError: String?

    let store = ClipboardStore()
    private let hotKey = GlobalHotKey()
    private let shortcutRecorder = ShortcutRecorderPanelController()
    private let statusBar = StatusBarController()
    private var panelController: OverlayPanelController?
    private let settingsPanel = SettingsPanelController()

    private let shortcutDefaultsKey = "globalShortcutV2"
    let settingsURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CBManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        settingsURL = appSupport.appendingPathComponent("settings.json")

        let loadedSettings = Self.loadSettings(at: settingsURL)

        if let saved = loadedSettings?.shortcut {
            shortcut = saved
        } else if let data = UserDefaults.standard.data(forKey: shortcutDefaultsKey),
                  let migrated = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) {
            shortcut = migrated
            Self.saveShortcutToSettings(migrated, at: settingsURL)
        } else {
            shortcut = .fallback
        }

        // Configure AI image title generation from settings.
        if let settings = loadedSettings {
            store.configureImageTitles(
                enabled: settings.resolvedImageTitlesEnabled,
                model: settings.resolvedImageTitleModel
            )

            // Run auto-prune on launch if enabled.
            if settings.resolvedAutoPruneEnabled {
                store.pruneEntries(olderThanDays: settings.resolvedAutoPruneDays)
            }
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
        statusBar.onSettings = { [weak self] in
            self?.openSettings()
        }
        statusBar.onQuit = {
            NSApplication.shared.terminate(nil)
        }

        refreshStatusBarMenu()

        // Prewarm the overlay panel shortly after launch so first open is instant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.ensurePanelController()
        }
    }

    @discardableResult
    private func ensurePanelController() -> OverlayPanelController {
        if let panelController { return panelController }
        let controller = OverlayPanelController(store: store)
        controller.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        panelController = controller
        return controller
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
        ensurePanelController().toggle()
        refreshStatusBarMenu()
    }

    func showOverlay() {
        ensurePanelController().show()
        refreshStatusBarMenu()
    }

    func openSettings() {
        settingsPanel.show(settingsURL: settingsURL) { [weak self] snapshot in
            self?.store.configureImageTitles(enabled: snapshot.imageTitlesEnabled, model: snapshot.imageTitleModel)
        }
    }

    @discardableResult
    func handleCloseWindowCommand() -> Bool {
        if settingsPanel.isVisible {
            settingsPanel.close()
            return true
        }

        if panelController?.closeTopPanel() == true {
            return true
        }

        return false
    }

    private func refreshStatusBarMenu() {
        statusBar.update(
            openTitle: "Toggle Clipboard (\(shortcut.title))",
            isRecording: isRecordingShortcut,
            error: shortcutError
        )
    }

    static func loadSettings(at url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return nil
        }
        return settings
    }

    private static func loadShortcutFromSettings(at url: URL) -> HotKeyShortcut? {
        return loadSettings(at: url)?.shortcut
    }

    static func saveSettings(_ settings: AppSettings, at url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func saveShortcutToSettings(_ shortcut: HotKeyShortcut, at url: URL) {
        var settings = loadSettings(at: url) ?? AppSettings(shortcut: nil)
        settings = AppSettings(
            shortcut: shortcut,
            imageTitleModel: settings.imageTitleModel,
            imageTitlesEnabled: settings.imageTitlesEnabled,
            autoPruneEnabled: settings.autoPruneEnabled,
            autoPruneDays: settings.autoPruneDays
        )
        saveSettings(settings, at: url)
    }
}

struct AppSettings: Codable {
    let shortcut: HotKeyShortcut?
    var imageTitleModel: String?
    var imageTitlesEnabled: Bool?
    var autoPruneEnabled: Bool?
    var autoPruneDays: Int?

    /// The model used for AI image title generation.
    var resolvedImageTitleModel: String {
        let custom = imageTitleModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? ImageTitleGenerator.defaultModel : custom
    }

    /// Whether AI image titles are enabled (defaults to true).
    var resolvedImageTitlesEnabled: Bool {
        imageTitlesEnabled ?? true
    }

    /// Whether auto-pruning old entries is enabled (defaults to false).
    var resolvedAutoPruneEnabled: Bool {
        autoPruneEnabled ?? false
    }

    /// Number of days after which entries are auto-pruned (defaults to 90).
    var resolvedAutoPruneDays: Int {
        let days = autoPruneDays ?? 90
        return max(days, 1)
    }
}
