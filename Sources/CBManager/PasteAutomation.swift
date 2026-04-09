import AppKit
import ApplicationServices
import Foundation
import OSLog

enum PastePreflightFailure: String, Equatable, Sendable {
    case clipboardWriteFailed
    case missingTargetApp
    case targetAppIsCurrentApp
    case missingAccessibilityPermission
    case missingPostEventPermission
}

struct PastePermissionSnapshot: Equatable, Sendable {
    let accessibilityTrusted: Bool
    let postEventAccess: Bool

    var canSendSyntheticPaste: Bool {
        accessibilityTrusted && postEventAccess
    }
}

struct PastePreflight: Equatable, Sendable {
    let clipboardWriteSucceeded: Bool
    let hasTargetApp: Bool
    let targetAppIsCurrentApp: Bool
    let permissions: PastePermissionSnapshot

    var failure: PastePreflightFailure? {
        if !clipboardWriteSucceeded {
            return .clipboardWriteFailed
        }
        if !hasTargetApp {
            return .missingTargetApp
        }
        if targetAppIsCurrentApp {
            return .targetAppIsCurrentApp
        }
        if !permissions.accessibilityTrusted {
            return .missingAccessibilityPermission
        }
        if !permissions.postEventAccess {
            return .missingPostEventPermission
        }
        return nil
    }

    var canAttemptSyntheticPaste: Bool {
        failure == nil
    }
}

@MainActor
enum PasteAutomationPermissions {
    static func snapshot(promptIfNeeded: Bool = false) -> PastePermissionSnapshot {
        let accessibilityTrusted: Bool
        if promptIfNeeded {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        } else {
            accessibilityTrusted = AXIsProcessTrustedWithOptions(nil)
        }

        let postEventAccess = promptIfNeeded
            ? CGRequestPostEventAccess()
            : CGPreflightPostEventAccess()

        return PastePermissionSnapshot(
            accessibilityTrusted: accessibilityTrusted,
            postEventAccess: postEventAccess
        )
    }
}

enum PasteDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cbmanager.app",
        category: "paste"
    )
    private static let queue = DispatchQueue(label: "com.cbmanager.app.paste-log", qos: .utility)
    private static let maxLogSizeBytes = 256 * 1024

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let timestamp = ISO8601DateFormatter.string(
            from: .now,
            timeZone: .current,
            formatOptions: [.withInternetDateTime, .withFractionalSeconds]
        )
        let line = "\(timestamp) \(message)\n"
        queue.async {
            appendLine(line)
        }
    }

    static func describe(_ application: NSRunningApplication?) -> String {
        guard let application else { return "nil" }

        let name = application.localizedName ?? "Unknown"
        let bundleID = application.bundleIdentifier ?? "nil"
        return "\(name) [pid=\(application.processIdentifier) bundle=\(bundleID) hidden=\(application.isHidden) active=\(application.isActive) terminated=\(application.isTerminated)]"
    }

    private static var logURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CBManager", isDirectory: true)
        return appSupport.appendingPathComponent("paste.log", isDirectory: false)
    }

    private static func appendLine(_ line: String) {
        let fileManager = FileManager.default
        let url = logURL
        let directory = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        trimLogIfNeeded(at: url)

        let lineData = Data(line.utf8)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: lineData)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }

        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: lineData)
    }

    private static func trimLogIfNeeded(at url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > maxLogSizeBytes,
              let existing = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return
        }

        let retained = Data(existing.suffix(maxLogSizeBytes / 2))
        try? retained.write(to: url, options: .atomic)
    }
}
