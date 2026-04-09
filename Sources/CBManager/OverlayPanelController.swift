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
    private var focusRestoreWorkItem: DispatchWorkItem?

    private let panelSize = NSSize(width: 980, height: 620)
    private let snapThreshold: CGFloat = 12
    private let pasteActivationTimeout: Duration = .seconds(1)
    private let pasteActivationPollInterval: Duration = .milliseconds(40)
    private let pastePostActivationDelay: Duration = .milliseconds(80)

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

    func show(captureFrontmost: Bool = true, resetSearch: Bool = true) {
        focusRestoreWorkItem?.cancel()
        focusRestoreWorkItem = nil

        if captureFrontmost,
           let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousFrontmostApp = frontmost
            PasteDiagnostics.log("Captured previous frontmost app: \(PasteDiagnostics.describe(frontmost))")
        }

        installMouseUpMonitor()

        if let screen = NSScreen.main {
            panel.setFrame(panelFrame(for: screen), display: false)
        }

        panel.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        store.overlayDidOpen(resetSearch: resetSearch)
    }

    func hide(restoreFocus: Bool = true) {
        alignmentGuides.hideAll()
        removeMouseUpMonitor()
        guard panel.isVisible else { return }

        focusRestoreWorkItem?.cancel()
        focusRestoreWorkItem = nil

        panel.orderOut(nil)
        panel.alphaValue = 1
        store.overlayDidClose()

        if restoreFocus,
           let target = previousFrontmostApp,
           target.processIdentifier != NSRunningApplication.current.processIdentifier {
            let workItem = DispatchWorkItem {
                target.unhide()
                let activated = target.activate(options: [.activateAllWindows])
                PasteDiagnostics.log(
                    "Restoring focus to previous app activated=\(activated) target=\(PasteDiagnostics.describe(target))"
                )
                if !activated {
                    NSApp.hide(nil)
                }
            }
            focusRestoreWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: workItem)
        }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == panel,
              !window.isVisible,
              store.isOverlayVisible else { return }
        alignmentGuides.hideAll()
        removeMouseUpMonitor()
        focusRestoreWorkItem?.cancel()
        focusRestoreWorkItem = nil
        store.overlayDidClose()
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
        let clipboardWriteSucceeded = store.copyToClipboard(entry)
        if clipboardWriteSucceeded {
            store.bumpToTop(entry)
        }

        let target = previousFrontmostApp
        let permissions = PasteAutomationPermissions.snapshot()
        let preflight = PastePreflight(
            clipboardWriteSucceeded: clipboardWriteSucceeded,
            hasTargetApp: target != nil,
            targetAppIsCurrentApp: target?.processIdentifier == NSRunningApplication.current.processIdentifier,
            permissions: permissions
        )

        PasteDiagnostics.log(
            "Paste requested entryID=\(entry.id) kind=\(entry.kind.rawValue) target=\(PasteDiagnostics.describe(target)) clipboardWriteSucceeded=\(clipboardWriteSucceeded) accessibilityTrusted=\(permissions.accessibilityTrusted) postEventAccess=\(permissions.postEventAccess) preflight=\(preflight.failure?.rawValue ?? "ready")"
        )

        if let failure = preflight.failure {
            if failure == .missingAccessibilityPermission || failure == .missingPostEventPermission {
                let promptedPermissions = PasteAutomationPermissions.snapshot(promptIfNeeded: true)
                PasteDiagnostics.log(
                    "Prompted paste permissions failure=\(failure.rawValue) accessibilityTrusted=\(promptedPermissions.accessibilityTrusted) postEventAccess=\(promptedPermissions.postEventAccess)"
                )
            }
            NSSound.beep()
            return
        }

        guard let target else {
            NSSound.beep()
            return
        }

        hide(restoreFocus: false)

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.activatePasteTarget(target) else {
                PasteDiagnostics.log("Failed to activate paste target before synthetic paste: \(PasteDiagnostics.describe(target))")
                NSSound.beep()
                return
            }
            try? await Task.sleep(for: self.pastePostActivationDelay)
            self.sendCommandV(to: target.processIdentifier)
        }
    }

    private func activatePasteTarget(_ target: NSRunningApplication) async -> Bool {
        let activationOptions: NSApplication.ActivationOptions = [.activateAllWindows]
        let deadline = ContinuousClock.now + pasteActivationTimeout
        var attempt = 0

        NSApp.hide(nil)
        PasteDiagnostics.log("Beginning paste target activation for \(PasteDiagnostics.describe(target))")

        while ContinuousClock.now < deadline {
            attempt += 1
            if target.isTerminated {
                PasteDiagnostics.log("Paste target terminated during activation: \(PasteDiagnostics.describe(target))")
                return false
            }

            target.unhide()
            let activated = target.activate(options: activationOptions)

            if let frontmost = NSWorkspace.shared.frontmostApplication,
               frontmost.processIdentifier == target.processIdentifier {
                PasteDiagnostics.log(
                    "Paste target became frontmost after \(attempt) attempt(s); activated=\(activated) frontmost=\(PasteDiagnostics.describe(frontmost))"
                )
                return true
            }

            if attempt == 1 || attempt % 5 == 0 {
                PasteDiagnostics.log(
                    "Paste target not frontmost yet attempt=\(attempt) activated=\(activated) frontmost=\(PasteDiagnostics.describe(NSWorkspace.shared.frontmostApplication))"
                )
            }

            try? await Task.sleep(for: pasteActivationPollInterval)
        }

        PasteDiagnostics.log(
            "Timed out activating paste target after \(attempt) attempt(s) target=\(PasteDiagnostics.describe(target)) frontmost=\(PasteDiagnostics.describe(NSWorkspace.shared.frontmostApplication))"
        )
        return false
    }

    private func openPreview(_ entry: ClipboardEntry) {
        if previewController.isVisible {
            previewController.close()
            return
        }

        hide(restoreFocus: false)
        previewController.toggle(entry: entry) { [weak self] in
            self?.show(captureFrontmost: false, resetSearch: false)
        }
    }

    private func sendCommandV(to processIdentifier: pid_t) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            PasteDiagnostics.log("Failed to create CGEventSource for synthetic paste")
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand

        guard let keyDown, let keyUp else {
            PasteDiagnostics.log("Failed to create Command-V events for pid=\(processIdentifier)")
            return
        }

        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        PasteDiagnostics.log("Posted synthetic Command-V directly to pid=\(processIdentifier)")
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
