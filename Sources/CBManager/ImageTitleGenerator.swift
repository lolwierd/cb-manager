import Foundation

/// Generates short AI-powered descriptions for images using the `pi` CLI.
actor ImageTitleGenerator {
    private var resolvedPiPath: String?
    private var pathResolved = false

    /// The pi model to use for title generation.
    static let defaultModel = "openai-codex/gpt-5.1-codex-mini"

    private var model: String = ImageTitleGenerator.defaultModel
    private let generationTimeout: Duration = .seconds(12)

    init() {}

    /// Update the model used for title generation.
    func setModel(_ newModel: String) {
        let trimmed = newModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            model = trimmed
        }
    }

    /// Check whether the `pi` CLI binary is reachable.
    func isAvailable() -> Bool {
        resolvePathIfNeeded()
        return resolvedPiPath != nil
    }

    /// Generate a one-sentence description for the image at the given path.
    /// Returns `nil` on any failure (missing binary, timeout, bad output, etc.).
    func generateTitle(forImageAt imagePath: String) async -> String? {
        resolvePathIfNeeded()
        guard let piPath = resolvedPiPath else { return nil }

        let prompt = """
        You are generating a title for a clipboard entry in a macOS clipboard manager app. \
        The title appears as a single line in a list of recent clipboard items, helping the user \
        quickly identify what they copied. Write one short, descriptive sentence (under 80 characters \
        if possible) that captures what this image shows. Be specific and concrete — mention key \
        subjects, UI elements, text, or context visible in the image. Output ONLY the title, \
        nothing else. No quotes, no prefix, no explanation.
        """

        let currentModel = model
        let timeout = generationTimeout

        return await withTaskGroup(of: String?.self, returning: String?.self) { group in
            group.addTask {
                await self.runPICommand(
                    piPath: piPath,
                    model: currentModel,
                    imagePath: imagePath,
                    prompt: prompt
                )
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            let firstResult = await group.next() ?? nil
            group.cancelAll()
            return firstResult
        }
    }

    private func runPICommand(
        piPath: String,
        model: String,
        imagePath: String,
        prompt: String
    ) async -> String? {
        let processHolder = ProcessHolder()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let process = Process()
                    processHolder.process = process

                    process.executableURL = URL(fileURLWithPath: piPath)
                    process.arguments = [
                        "-p",
                        "--model", model,
                        "--no-tools",
                        "--no-extensions",
                        "--no-skills",
                        "--no-session",
                        "--thinking", "off",
                        "@\(imagePath)",
                        prompt,
                    ]

                    let outputPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = FileHandle.nullDevice

                    do {
                        try process.run()

                        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()

                        guard process.terminationStatus == 0,
                              process.terminationReason != .uncaughtSignal else {
                            continuation.resume(returning: nil)
                            return
                        }

                        guard let raw = String(data: outputData, encoding: .utf8) else {
                            continuation.resume(returning: nil)
                            return
                        }

                        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: title.isEmpty ? nil : title)
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        } onCancel: {
            processHolder.terminate()
        }
    }

    // MARK: - Path resolution (same strategy as QMDSearchEngine)

    private func resolvePathIfNeeded() {
        guard !pathResolved else { return }
        pathResolved = true
        let shellPATH = Self.resolveShellPATH()
        resolvedPiPath = Self.findBinary(named: "pi", in: shellPATH)
    }

    private static func resolveShellPATH() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", "echo $PATH"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            if let resolved = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !resolved.isEmpty {
                return resolved
            }
        } catch {}
        return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    }

    private static func findBinary(named name: String, in shellPATH: String) -> String? {
        for dir in shellPATH.split(separator: ":").map(String.init) {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
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
