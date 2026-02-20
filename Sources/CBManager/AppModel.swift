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

    init() {
        if let data = UserDefaults.standard.data(forKey: shortcutDefaultsKey),
           let saved = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) {
            shortcut = saved
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
            self?.showOverlay()
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
            self.refreshStatusBarMenu()
        }
    }

    func toggleOverlay() {
        panelController.toggle()
    }

    func showOverlay() {
        panelController.show()
    }

    private func refreshStatusBarMenu() {
        statusBar.update(
            openTitle: "Open Clipboard (\(shortcut.title))",
            isRecording: isRecordingShortcut,
            error: shortcutError
        )
    }
}
