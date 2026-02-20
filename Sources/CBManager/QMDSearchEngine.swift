import Foundation

actor QMDSearchEngine {
    private let docsDirectory: URL
    private let collectionName = "cbmanager"
    private var collectionEnsured = false
    private var updateTask: Task<Void, Never>?
    private var embedTask: Task<Void, Never>?
    private var pathResolved = false

    init(baseDirectory: URL) {
        docsDirectory = baseDirectory.appendingPathComponent("qmd-docs", isDirectory: true)
        try? FileManager.default.createDirectory(at: docsDirectory, withIntermediateDirectories: true)
        resolvedQMDPath = nil
    }

    /// Resolve the qmd binary path on first use (off the main thread).
    private func resolvePathIfNeeded() {
        guard !pathResolved else { return }
        pathResolved = true
        let shellPATH = Self.resolveShellPATH()
        resolvedQMDPath = Self.findQMD(in: shellPATH)
    }

    func isAvailable() async -> Bool {
        resolvePathIfNeeded()
        guard let output = await runQMD(["--version"]) else { return false }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func bootstrap(entries: [ClipboardEntry]) async {
        await ensureCollection()
        for entry in entries {
            writeDocument(for: entry)
        }
        _ = await runQMD(["update"])
        scheduleEmbed(delay: .seconds(2))
    }

    func upsert(_ entry: ClipboardEntry) async {
        await ensureCollection()
        writeDocument(for: entry)
        scheduleUpdate()
        scheduleEmbed(delay: .seconds(10))
    }

    func remove(id: String) async {
        await ensureCollection()
        let file = docsDirectory.appendingPathComponent("\(id).md")
        try? FileManager.default.removeItem(at: file)
        scheduleUpdate()
    }

    func keywordSearchIDs(query: String, limit: Int) async -> Set<String> {
        await searchIDs(
            command: ["search", query, "-c", collectionName, "--json", "-n", "\(limit)"]
        )
    }

    func semanticSearchIDs(query: String, limit: Int) async -> Set<String> {
        await searchIDs(
            command: ["vsearch", query, "-c", collectionName, "--json", "-n", "\(limit)"]
        )
    }

    private func searchIDs(command: [String]) async -> Set<String> {
        guard let output = await runQMD(command) else { return [] }
        return Self.parseIDs(from: output)
    }

    static func parseIDs(from output: String) -> Set<String> {
        guard let data = output.data(using: .utf8),
              let rows = try? JSONDecoder().decode([QMDSearchRow].self, from: data) else {
            return []
        }

        let ids = rows.compactMap { row -> String? in
            guard let file = row.file else { return nil }
            let last = file.split(separator: "/").last.map(String.init) ?? file
            return last.replacingOccurrences(of: ".md", with: "")
        }

        return Set(ids)
    }

    private func ensureCollection() async {
        guard !collectionEnsured else { return }
        _ = await runQMD(["collection", "add", docsDirectory.path, "--name", collectionName])
        collectionEnsured = true
    }

    private func scheduleUpdate() {
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled, let self else { return }
            _ = await self.runQMD(["update"])
        }
    }

    private func scheduleEmbed(delay: Duration) {
        embedTask?.cancel()
        embedTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            _ = await self.runQMD(["embed"])
        }
    }

    private func writeDocument(for entry: ClipboardEntry) {
        let content = """
        # Clipboard Entry \(entry.id)

        - kind: \(entry.kind.rawValue)
        - source: \(entry.sourceApp ?? "Unknown")
        - created_at: \(entry.date.timeIntervalSince1970)

        ## Content
        \(entry.content)

        ## OCR
        \(entry.ocrText)

        ## Search Hints
        \(entry.searchHints)
        """

        let file = docsDirectory.appendingPathComponent("\(entry.id).md")
        try? content.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Resolve the user's full login-shell PATH (GUI apps inherit a minimal PATH).
    /// Computed fresh each time QMDSearchEngine is created (i.e. each app launch).
    private var resolvedQMDPath: String?

    private static func resolveShellPATH() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-ilc", "echo $PATH"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let resolved = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !resolved.isEmpty {
                return resolved
            }
        } catch {}
        return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    }

    private static func findQMD(in shellPATH: String) -> String? {
        for dir in shellPATH.split(separator: ":").map(String.init) {
            let candidate = "\(dir)/qmd"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func runQMD(_ arguments: [String]) async -> String? {
        // Use withTaskCancellationHandler so we kill the process when the Task is cancelled.
        let processHolder = ProcessHolder()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async { [resolvedQMDPath] in
                    let process = Process()
                    processHolder.process = process

                    if let resolved = resolvedQMDPath {
                        process.executableURL = URL(fileURLWithPath: resolved)
                        process.arguments = arguments
                    } else {
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                        process.arguments = ["qmd"] + arguments
                    }

                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe

                    do {
                        try process.run()
                        process.waitUntilExit()

                        guard process.terminationStatus != 15, // SIGTERM from cancellation
                              process.terminationReason != .uncaughtSignal else {
                            continuation.resume(returning: nil)
                            return
                        }

                        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                        if process.terminationStatus != 0 {
                            if outputData.isEmpty {
                                _ = String(data: errorData, encoding: .utf8)
                                continuation.resume(returning: nil)
                                return
                            }
                        }

                        continuation.resume(returning: String(data: outputData, encoding: .utf8))
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        } onCancel: {
            processHolder.terminate()
        }
    }
}

/// Thread-safe holder so the cancellation handler can terminate a running Process.
private final class ProcessHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?
    private var _cancelled = false

    var process: Process? {
        get { lock.withLock { _process } }
        set {
            lock.withLock {
                _process = newValue
                // If already cancelled before the process was assigned, kill immediately.
                if _cancelled, let p = newValue, p.isRunning {
                    p.terminate()
                }
            }
        }
    }

    func terminate() {
        lock.withLock {
            _cancelled = true
            if let p = _process, p.isRunning {
                p.terminate()
            }
        }
    }
}

private struct QMDSearchRow: Decodable {
    let file: String?
}
