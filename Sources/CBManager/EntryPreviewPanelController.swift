import AppKit
import Carbon
import SwiftUI

@MainActor
final class EntryPreviewPanelController: NSObject, NSWindowDelegate {
    private var panel: FocusPanel?
    private var onClose: (() -> Void)?
    private var keyMonitor: Any?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle(entry: ClipboardEntry, onClose: (() -> Void)? = nil) {
        if isVisible {
            close()
        } else {
            present(entry: entry, onClose: onClose)
        }
    }

    func present(entry: ClipboardEntry, onClose: (() -> Void)? = nil) {
        self.onClose = onClose

        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: EntryPreviewView(entry: entry))

        if let screen = NSScreen.main {
            let size = NSSize(width: 1040, height: 700)
            let frame = NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2 + 40,
                width: size.width,
                height: size.height
            )
            panel.setFrame(frame, display: true)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        removeKeyMonitor()

        guard let panel, panel.isVisible else {
            onClose?()
            onClose = nil
            return
        }

        panel.orderOut(nil)
        let callback = onClose
        onClose = nil
        callback?()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let commandNoControlOrOption = mods.contains(.command) && !mods.contains(.control) && !mods.contains(.option)

            if event.keyCode == UInt16(kVK_ANSI_Y), commandNoControlOrOption {
                self.close()
                return nil
            }

            if event.keyCode == UInt16(kVK_Escape) {
                self.close()
                return nil
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func makePanel() -> FocusPanel {
        let panel = FocusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        panel.onEscape = { [weak self] in
            self?.close()
        }

        panel.onKeyDown = { [weak self] event in
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let commandNoControlOrOption = mods.contains(.command) && !mods.contains(.control) && !mods.contains(.option)
            if event.keyCode == UInt16(kVK_ANSI_Y), commandNoControlOrOption {
                self?.close()
                return true
            }
            return false
        }

        self.panel = panel
        return panel
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
        let callback = onClose
        onClose = nil
        callback?()
    }

}

private struct EntryPreviewView: View {
    let entry: ClipboardEntry

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(entry.kind.rawValue, systemImage: entry.kind.symbol)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().overlay(.white.opacity(0.10))

            Group {
                if entry.kind == .image,
                   let imagePath = entry.imagePath {
                    EntryPreviewImageView(path: imagePath)
                        .padding(18)
                } else {
                    ScrollView {
                        Text(entry.content)
                            .font(entry.kind == .code || entry.kind == .path
                                  ? .system(size: 15, weight: .regular, design: .monospaced)
                                  : .system(size: 15, weight: .regular, design: .rounded))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(22)
                    }
                }
            }

            Divider().overlay(.white.opacity(0.10))

            HStack {
                Text(entry.sourceApp ?? "Unknown Source")
                Spacer()
                Text("⌘Y / Esc to close")
            }
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                )
        )
        .padding(10)
    }
}

private struct EntryPreviewImageView: View {
    let path: String

    @State private var loadGeneration: UInt = 0
    @State private var displayedImage: NSImage?

    var body: some View {
        GeometryReader { geometry in
            let maxPixelSize = quantizedMaxPixelSize(for: geometry.size)
            let image = displayedImage ?? ThumbnailCache.shared.cachedThumbnail(
                for: path,
                maxPixelSize: maxPixelSize
            )

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.05))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear {
                scheduleLoad(for: geometry.size)
            }
            .onChange(of: path) { _, _ in
                scheduleLoad(for: geometry.size)
            }
            .onChange(of: quantizedMaxPixelSize(for: geometry.size)) { _, _ in
                scheduleLoad(for: geometry.size)
            }
        }
    }

    private func quantizedMaxPixelSize(for size: CGSize) -> CGFloat {
        let rawSize = max(size.width, size.height) * 2
        return max(512, ceil(rawSize / 128) * 128)
    }

    private func scheduleLoad(for size: CGSize) {
        let generation = loadGeneration &+ 1
        loadGeneration = generation
        let maxPixelSize = quantizedMaxPixelSize(for: size)
        displayedImage = ThumbnailCache.shared.cachedThumbnail(
            for: path,
            maxPixelSize: maxPixelSize
        )

        if displayedImage != nil {
            return
        }

        let pathSnapshot = path
        DispatchQueue.global(qos: .userInitiated).async {
            let image = ThumbnailCache.shared.thumbnail(
                for: pathSnapshot,
                maxPixelSize: maxPixelSize
            )
            DispatchQueue.main.async {
                guard loadGeneration == generation else { return }
                displayedImage = image
            }
        }
    }
}
