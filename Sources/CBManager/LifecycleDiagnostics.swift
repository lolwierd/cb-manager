import AppKit
import Darwin
import Foundation
import OSLog

/// Records why the app went away.
///
/// CBManager runs for days at a time as an accessory app, and when it
/// disappears there is usually nothing to look at: a clean exit leaves no
/// trace at all, and an OS kill (jetsam under memory pressure, or a plain
/// `kill -9`) leaves no crash dialog either. Both look identical from the
/// outside. This records enough to tell them apart after the fact.
///
/// Two files under `~/Library/Application Support/CBManager/`:
///
/// - `lifecycle-state.json` — the current session, rewritten every heartbeat.
///   If a session ends cleanly, `exitReason` is set before the process goes
///   away. If the process is killed, the file is left with `exitReason` nil
///   and a `lastHeartbeatAt` a few seconds before death, along with the
///   resource counters as of that moment.
/// - `lifecycle.log` — one line per launch, plus a verdict line about the
///   previous session. Size-capped like `paste.log`.
///
/// The verdict on the previous session is also emitted to the unified log at
/// `notice` level, so `log show --predicate 'subsystem == "com.cbmanager.app"'`
/// finds it without opening any files.
/// Snapshot of one run of the app.
///
/// Declared at file scope rather than nested in `LifecycleDiagnostics` so it
/// stays outside the main actor: heartbeats are written from a background
/// queue.
struct LifecycleSessionState: Codable, Sendable {
    var sessionID: String
    var pid: Int32
    var version: String
    var startedAt: Double
    var lastHeartbeatAt: Double
    var uptimeSeconds: Double
    /// `phys_footprint` in MB — the number macOS memory pressure acts on.
    var footprintMB: Double
    var peakFootprintMB: Double
    var threadCount: Int
    var openFileDescriptors: Int
    var entryCount: Int
    /// Nil while the session is running, and while it is being killed.
    /// Non-nil only if the app got a chance to shut down in an orderly way.
    var exitReason: String?
}

@MainActor
enum LifecycleDiagnostics {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cbmanager.app",
        category: "lifecycle"
    )
    private nonisolated static let queue = DispatchQueue(label: "com.cbmanager.app.lifecycle-log", qos: .utility)
    private nonisolated static let heartbeatInterval: TimeInterval = 30
    private nonisolated static let maxLogSizeBytes = 128 * 1024
    /// Emit a unified-log notice each time the footprint crosses another
    /// multiple of this, so growth is visible in `log show` without the file.
    private nonisolated static let footprintNoticeStepMB: Double = 100

    private static var state: LifecycleSessionState?
    private static var heartbeatTimer: Timer?
    private static var entryCountProvider: (@MainActor () -> Int)?
    private static var lastNoticedFootprintStep: Double = 0
    private static var started = false

    // MARK: - Lifecycle

    /// Begin recording. Call once, after the app model exists.
    ///
    /// `entryCount` is read on each heartbeat so the memory number can be read
    /// against how much history is actually being held.
    static func start(entryCount: @MainActor @escaping () -> Int) {
        guard !started else { return }
        started = true
        entryCountProvider = entryCount

        let previous = loadPreviousState()
        let now = Date().timeIntervalSince1970
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

        var session = LifecycleSessionState(
            sessionID: UUID().uuidString,
            pid: ProcessInfo.processInfo.processIdentifier,
            version: version,
            startedAt: now,
            lastHeartbeatAt: now,
            uptimeSeconds: 0,
            footprintMB: memoryFootprintMB(),
            peakFootprintMB: memoryFootprintMB(),
            threadCount: threadCount(),
            openFileDescriptors: -1,
            entryCount: entryCount(),
            exitReason: nil
        )
        state = session

        // Report on the run that came before this one before overwriting it.
        if let previous {
            let verdict = Self.verdict(for: previous)
            logger.notice("\(verdict, privacy: .public)")
            append(line: verdict)
        } else {
            append(line: "no previous session state on disk (first run, or state file removed)")
        }

        let launchLine = "session start pid=\(session.pid) version=\(version) entries=\(session.entryCount) footprintMB=\(format(session.footprintMB)) threads=\(session.threadCount)"
        logger.notice("\(launchLine, privacy: .public)")
        append(line: launchLine)

        persist(session)

        observeSystemShutdown()
        startHeartbeat()
    }

    /// Record an orderly shutdown. Anything that leaves `exitReason` unset is,
    /// by definition, not an orderly shutdown.
    static func recordCleanExit(reason: String) {
        guard var session = state else { return }
        let now = Date().timeIntervalSince1970
        session.lastHeartbeatAt = now
        session.uptimeSeconds = now - session.startedAt
        session.footprintMB = memoryFootprintMB()
        session.peakFootprintMB = max(session.peakFootprintMB, session.footprintMB)
        session.threadCount = threadCount()
        session.entryCount = entryCountProvider?() ?? session.entryCount
        session.exitReason = reason
        state = session

        let line = "clean exit reason=\(reason) uptime=\(formatUptime(session.uptimeSeconds)) footprintMB=\(format(session.footprintMB)) peakMB=\(format(session.peakFootprintMB)) entries=\(session.entryCount)"
        logger.notice("\(line, privacy: .public)")

        // Both writes are synchronous: the process may be seconds from gone.
        persistSynchronously(session)
        queue.sync { appendLine("\(timestamp(now)) \(line)\n") }

        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private static func observeSystemShutdown() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                recordCleanExit(reason: "system-power-off")
            }
        }
    }

    // MARK: - Heartbeat

    private static func startHeartbeat() {
        let timer = Timer(timeInterval: heartbeatInterval, repeats: true) { _ in
            MainActor.assumeIsolated { heartbeat() }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private static func heartbeat() {
        guard var session = state, session.exitReason == nil else { return }

        let now = Date().timeIntervalSince1970
        session.lastHeartbeatAt = now
        session.uptimeSeconds = now - session.startedAt
        session.footprintMB = memoryFootprintMB()
        session.peakFootprintMB = max(session.peakFootprintMB, session.footprintMB)
        session.threadCount = threadCount()
        session.entryCount = entryCountProvider?() ?? session.entryCount
        state = session

        // Only shout when the footprint crosses a new step, so the unified log
        // does not fill up with a line every 30 seconds.
        let step = (session.footprintMB / footprintNoticeStepMB).rounded(.down) * footprintNoticeStepMB
        if step > lastNoticedFootprintStep {
            lastNoticedFootprintStep = step
            let line = "footprint crossed \(format(step))MB uptime=\(formatUptime(session.uptimeSeconds)) entries=\(session.entryCount) threads=\(session.threadCount)"
            logger.notice("\(line, privacy: .public)")
            append(line: line)
        }

        persist(session)
    }

    // MARK: - Verdict

    /// Internal (not private) so the kill-vs-quit decision is unit testable.
    /// `now` is injected for the same reason.
    static func verdict(for previous: LifecycleSessionState, now: Double = Date().timeIntervalSince1970) -> String {
        let common = "previous session pid=\(previous.pid) version=\(previous.version) uptime=\(formatUptime(previous.uptimeSeconds)) footprintMB=\(format(previous.footprintMB)) peakMB=\(format(previous.peakFootprintMB)) threads=\(previous.threadCount) fds=\(previous.openFileDescriptors) entries=\(previous.entryCount) lastHeartbeat=\(timestamp(previous.lastHeartbeatAt))"

        if let reason = previous.exitReason {
            return "previous session ended cleanly reason=\(reason) \(common)"
        }

        // No exit reason means applicationWillTerminate never ran: the process
        // was killed (jetsam, SIGKILL, a crash that skipped AppKit teardown) or
        // the machine lost power.
        let gap = now - previous.lastHeartbeatAt
        return "previous session DIED WITHOUT CLEAN EXIT (killed, not quit) deadFor=\(formatUptime(gap)) \(common)"
    }

    // MARK: - Metrics

    /// Resident memory as macOS accounts for it. `phys_footprint` is the value
    /// the memory pressure / jetsam machinery compares against limits, so it is
    /// the right number to watch for an OS kill.
    private static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / (1024 * 1024)
    }

    /// Live thread count. A steadily climbing number here means threads are
    /// being parked and never reclaimed — the usual suspect is a blocking wait
    /// on a subprocess from a concurrent queue.
    private static func threadCount() -> Int {
        var threads: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS,
              let threads else {
            return -1
        }
        defer {
            let address = vm_address_t(UInt(bitPattern: UnsafeRawPointer(threads)))
            let size = vm_size_t(Int(count) * MemoryLayout<thread_t>.size)
            vm_deallocate(mach_task_self_, address, size)
        }
        return Int(count)
    }

    /// Open file descriptors, by probing the descriptor table. Cheap enough to
    /// run once per heartbeat, and it is the direct test for pipes leaked by
    /// subprocess invocations.
    private nonisolated static func openFileDescriptorCount() -> Int {
        let limit = min(Int(getdtablesize()), 4096)
        var open = 0
        for descriptor in 0..<limit where fcntl(Int32(descriptor), F_GETFD) != -1 {
            open += 1
        }
        return open
    }

    // MARK: - Persistence

    private nonisolated static let stateFileName = "lifecycle-state.json"
    private nonisolated static let logFileName = "lifecycle.log"

    private nonisolated static func fileURL(named name: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CBManager", isDirectory: true)
        return appSupport.appendingPathComponent(name, isDirectory: false)
    }

    private static func loadPreviousState() -> LifecycleSessionState? {
        guard let data = try? Data(contentsOf: fileURL(named: stateFileName)) else { return nil }
        return try? JSONDecoder().decode(LifecycleSessionState.self, from: data)
    }

    /// Write the state file off the main thread. The fd scan happens here too,
    /// so the main actor never pays for it.
    private static func persist(_ session: LifecycleSessionState) {
        queue.async {
            var snapshot = session
            snapshot.openFileDescriptors = openFileDescriptorCount()
            write(snapshot)
        }
    }

    private static func persistSynchronously(_ session: LifecycleSessionState) {
        queue.sync {
            var snapshot = session
            snapshot.openFileDescriptors = openFileDescriptorCount()
            write(snapshot)
        }
    }

    private nonisolated static func write(_ session: LifecycleSessionState) {
        let url = fileURL(named: stateFileName)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func append(line: String) {
        let stamped = "\(timestamp(Date().timeIntervalSince1970)) \(line)\n"
        queue.async { appendLine(stamped) }
    }

    private nonisolated static func appendLine(_ line: String) {
        let fileManager = FileManager.default
        let url = fileURL(named: logFileName)
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        trimLogIfNeeded(at: url)

        let data = Data(line.utf8)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: data)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private nonisolated static func trimLogIfNeeded(at url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > maxLogSizeBytes,
              let existing = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return
        }
        let retained = Data(existing.suffix(maxLogSizeBytes / 2))
        try? retained.write(to: url, options: .atomic)
    }

    // MARK: - Formatting

    private nonisolated static func timestamp(_ interval: Double) -> String {
        ISO8601DateFormatter.string(
            from: Date(timeIntervalSince1970: interval),
            timeZone: .current,
            formatOptions: [.withInternetDateTime]
        )
    }

    private nonisolated static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    nonisolated static func formatUptime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "unknown" }
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d\(hours)h\(minutes)m" }
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }
}
