import Foundation

actor ShellPathResolver {
    enum Mode: Hashable {
        case login
        case interactiveLogin

        var shellArguments: [String] {
            switch self {
            case .login:
                return ["-lc", "echo $PATH"]
            case .interactiveLogin:
                return ["-ilc", "echo $PATH"]
            }
        }
    }

    static let shared = ShellPathResolver()

    private var resolvedPaths: [Mode: String] = [:]

    func findExecutable(named name: String, mode: Mode) async -> String? {
        let path = await resolvedPath(mode: mode)
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func resolvedPath(mode: Mode) async -> String {
        if let cached = resolvedPaths[mode] {
            return cached
        }

        let resolved = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = mode.shellArguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if let path = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !path.isEmpty {
                        continuation.resume(returning: path)
                        return
                    }
                } catch {}

                continuation.resume(
                    returning: ProcessInfo.processInfo.environment["PATH"]
                        ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                )
            }
        }

        resolvedPaths[mode] = resolved
        return resolved
    }
}
