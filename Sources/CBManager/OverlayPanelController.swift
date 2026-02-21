import AppKit
import Carbon
import SwiftUI

@MainActor
final class OverlayPanelController: NSObject, NSWindowDelegate {
    private let store: ClipboardStore
    private lazy var panel: FocusPanel = makePanel()
    private let alignmentGuides = AlignmentGuidesController()
    private let previewController = EntryPreviewPanelController()

    var onOpenSettings: (() -> Void)?

    private var previousFrontmostApp: NSRunningApplication?
    private var isProgrammaticMove = false
    private var mouseUpMonitor: Any?

    private let panelSize = NSSize(width: 980, height: 620)
    private let snapThreshold: CGFloat = 12

    init(store: ClipboardStore) {
        self.store = store
        super.init()
        _ = panel // prewarm window so first open is instant
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show(captureFrontmost: Bool = true) {
        if captureFrontmost,
           let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousFrontmostApp = frontmost
        }

        installMouseUpMonitor()

        if let screen = NSScreen.main {
            panel.setFrame(panelFrame(for: screen), display: false)
        }

        panel.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        store.overlayDidOpen()
    }

    func hide(restoreFocus: Bool = true) {
        alignmentGuides.hideAll()
        removeMouseUpMonitor()
        guard panel.isVisible else { return }

        panel.orderOut(nil)
        panel.alphaValue = 1
        store.overlayDidClose()

        if restoreFocus,
           let target = previousFrontmostApp,
           target.processIdentifier != NSRunningApplication.current.processIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                target.unhide()
                let activated = target.activate(options: [.activateAllWindows])
                if !activated {
                    NSApp.hide(nil)
                }
            }
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard panel.isVisible, !isProgrammaticMove else { return }

        // Show guides only while actively dragging.
        guard NSEvent.pressedMouseButtons != 0 else {
            alignmentGuides.hideAll()
            return
        }

        guard let screen = panel.screen ?? NSScreen.main else { return }

        let reference = panelFrame(for: screen)
        let current = panel.frame
        var snappedOrigin = current.origin

        let snapX = abs(current.midX - reference.midX) <= snapThreshold
        let snapY = abs(current.midY - reference.midY) <= snapThreshold

        if snapX {
            snappedOrigin.x = reference.midX - current.width / 2
        }

        if snapY {
            snappedOrigin.y = reference.midY - current.height / 2
        }

        alignmentGuides.show(
            verticalX: reference.midX,
            horizontalY: reference.midY,
            on: screen,
            showVertical: snapX,
            showHorizontal: snapY
        )

        if abs(snappedOrigin.x - current.origin.x) > 0.5 || abs(snappedOrigin.y - current.origin.y) > 0.5 {
            isProgrammaticMove = true
            panel.setFrameOrigin(snappedOrigin)
            isProgrammaticMove = false
        }
    }

    @discardableResult
    func closeTopPanel() -> Bool {
        if previewController.isVisible {
            previewController.close()
            return true
        }

        if panel.isVisible {
            hide()
            return true
        }

        return false
    }

    private func installMouseUpMonitor() {
        removeMouseUpMonitor()
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            self?.alignmentGuides.hideAll()
            return event
        }
    }

    private func removeMouseUpMonitor() {
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
            self.mouseUpMonitor = nil
        }
    }

    private func paste(_ entry: ClipboardEntry) {
        store.bumpToTop(entry)
        store.copyToClipboard(entry)
        hide(restoreFocus: false)

        let target = previousFrontmostApp
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            target?.activate(options: [])
            try? await Task.sleep(for: .milliseconds(120))
            sendCommandV()
        }
    }

    private func openPreview(_ entry: ClipboardEntry) {
        if previewController.isVisible {
            previewController.close()
            return
        }

        hide(restoreFocus: false)
        previewController.toggle(entry: entry) { [weak self] in
            self?.show(captureFrontmost: false)
        }
    }

    private func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func panelFrame(for screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - panelSize.width / 2,
            y: screen.frame.midY - panelSize.height / 2 + 80,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func makePanel() -> FocusPanel {
        let panel = FocusPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.onEscape = { [weak self] in self?.hide() }
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let view = SearchOverlayView(
            store: store,
            onClose: { [weak self] in self?.hide() },
            onConfirm: { [weak self] entry in self?.paste(entry) },
            onDelete: { [weak self] entry in self?.store.deleteEntry(entry) },
            onUndoDelete: { [weak self] in self?.store.undoDelete() },
            onOpenPreview: { [weak self] entry in self?.openPreview(entry) },
            onOpenSettings: { [weak self] in
                self?.hide(restoreFocus: false)
                self?.onOpenSettings?()
            }
        )

        panel.contentView = NSHostingView(rootView: view)
        return panel
    }
}
