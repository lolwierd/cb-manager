import AppKit
import Carbon
import SwiftUI

@MainActor
final class ShortcutRecorderPanelController {
    private var panel: NSPanel?

    func present(current: HotKeyShortcut, completion: @escaping (HotKeyShortcut?) -> Void) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "Set Global Shortcut"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.center()

        let rootView = ShortcutRecorderView(
            current: current,
            onCancel: { [weak self] in
                completion(nil)
                self?.close()
            },
            onCapture: { [weak self] shortcut in
                completion(shortcut)
                self?.close()
            }
        )

        panel.contentView = NSHostingView(rootView: rootView)
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct ShortcutRecorderView: View {
    let current: HotKeyShortcut
    let onCancel: () -> Void
    let onCapture: (HotKeyShortcut) -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Record new shortcut")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Text("Current: \(current.title)")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Press your key combination now (must include ⌘, ⌥, or ⌃).")
                .font(.system(size: 13, weight: .regular, design: .rounded))

            ShortcutCaptureField { event in
                handle(event)
            }
            .frame(height: 54)

            Text(errorMessage ?? "Press Esc to cancel")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(errorMessage == nil ? .secondary : .red)

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel()
            return
        }

        if isModifierOnly(event.keyCode) {
            return
        }

        let modifiers = event.modifierFlags
            .intersection([.command, .option, .control, .shift])
            .carbonHotKeyModifiers

        let shortcut = HotKeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)

        guard shortcut.isValid else {
            errorMessage = "Use at least ⌘, ⌥, or ⌃ in the shortcut."
            NSSound.beep()
            return
        }

        onCapture(shortcut)
    }

    private func isModifierOnly(_ keyCode: UInt16) -> Bool {
        [
            UInt16(kVK_Command), UInt16(kVK_RightCommand),
            UInt16(kVK_Shift), UInt16(kVK_RightShift),
            UInt16(kVK_Option), UInt16(kVK_RightOption),
            UInt16(kVK_Control), UInt16(kVK_RightControl),
            UInt16(kVK_CapsLock), UInt16(kVK_Function)
        ].contains(keyCode)
    }
}

private struct ShortcutCaptureField: NSViewRepresentable {
    let onEvent: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onEvent = onEvent
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onEvent = onEvent
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyCaptureView: NSView {
    var onEvent: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = "Waiting for shortcut…"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let size = text.size(withAttributes: attrs)
        let point = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        text.draw(at: point, withAttributes: attrs)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        onEvent?(event)
    }
}
