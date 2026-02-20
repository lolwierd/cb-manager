import AppKit

@MainActor
final class AlignmentGuidesController {
    private var verticalGuide: NSWindow?
    private var horizontalGuide: NSWindow?

    private let guideColor = NSColor.systemBlue.withAlphaComponent(0.55)
    private let glowColor = NSColor.systemBlue.withAlphaComponent(0.18)
    private let thickness: CGFloat = 1

    func show(verticalX: CGFloat, horizontalY: CGFloat, on screen: NSScreen, showVertical: Bool, showHorizontal: Bool) {
        if showVertical {
            let frame = NSRect(
                x: verticalX - thickness / 2,
                y: screen.frame.minY,
                width: thickness,
                height: screen.frame.height
            )
            let window = ensureVerticalGuide()
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
        } else {
            verticalGuide?.orderOut(nil)
        }

        if showHorizontal {
            let frame = NSRect(
                x: screen.frame.minX,
                y: horizontalY - thickness / 2,
                width: screen.frame.width,
                height: thickness
            )
            let window = ensureHorizontalGuide()
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
        } else {
            horizontalGuide?.orderOut(nil)
        }
    }

    func hideAll() {
        verticalGuide?.orderOut(nil)
        horizontalGuide?.orderOut(nil)
    }

    private func ensureVerticalGuide() -> NSWindow {
        if let verticalGuide {
            return verticalGuide
        }

        let window = makeGuideWindow()
        verticalGuide = window
        return window
    }

    private func ensureHorizontalGuide() -> NSWindow {
        if let horizontalGuide {
            return horizontalGuide
        }

        let window = makeGuideWindow()
        horizontalGuide = window
        return window
    }

    private func makeGuideWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        let guideView = NSView(frame: .zero)
        guideView.wantsLayer = true
        guideView.layer?.backgroundColor = guideColor.cgColor
        guideView.layer?.shadowColor = glowColor.cgColor
        guideView.layer?.shadowOpacity = 1
        guideView.layer?.shadowRadius = 3
        guideView.layer?.shadowOffset = .zero

        window.contentView = guideView
        return window
    }
}
