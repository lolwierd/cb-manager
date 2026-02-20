import Foundation

actor QMDSearchEngine {
    private let docsDirectory: URL
    private let collectionName = "cbmanager"
    private var collectionEnsured = false
    private var updateTask: Task<Void, Never>?
    private var embedTask: Task<Void, Never>?

    init(baseDirectory: URL) {
        docsDirectory = baseDirectory.appendingPathComponent("qmd-docs", isDirectory: true)
        try? FileManager.default.createDirectory(at: docsDirectory, withIntermediateDirectories: true)
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

    private func runQMD(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["qmd"] + arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    if process.terminationStatus != 0 {
                        // Best-effort fallback: if command wrote valid JSON to stdout, caller may still parse it.
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
    }
}

private struct QMDSearchRow: Decodable {
    let file: String?
}
