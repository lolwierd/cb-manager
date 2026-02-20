import AppKit
import Foundation

struct ClipboardEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case text = "Text"
        case link = "Link"
        case code = "Code"
        case path = "Path"
        case image = "Image"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .all: "square.stack.3d.up"
            case .text: "text.quote"
            case .link: "link"
            case .code: "chevron.left.forwardslash.chevron.right"
            case .path: "folder"
            case .image: "photo"
            }
        }
    }

    let id: String
    let content: String
    let date: Date
    let sourceApp: String?
    let kind: Kind
    let imagePath: String?
    var ocrText: String
    var isOCRPending: Bool
    var aiTitle: String = ""
    var isAITitlePending: Bool = false

    var titleLine: String {
        switch kind {
        case .image:
            let trimmedTitle = aiTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                return Self.compactLine(trimmedTitle, limit: 90)
            }
            if isAITitlePending {
                return imageSummary
            }
            return imageSummary
        default:
            return Self.compactLine(content, limit: 96)
        }
    }

    /// Compact fallback summary for images: dimensions + source.
    private var imageSummary: String {
        var parts: [String] = ["Image"]
        if let path = imagePath,
           let size = ThumbnailCache.imageDimensions(at: path) {
            parts.append("(\(Int(size.width))×\(Int(size.height)))")
        }
        if let app = sourceApp, !app.isEmpty {
            parts.append("· \(app)")
        }
        return parts.joined(separator: " ")
    }

    var searchHints: String {
        var hints: [String] = [kind.rawValue.lowercased()]

        switch kind {
        case .code:
            hints += ["snippet", "command", "query"]
            let upper = content.uppercased()
            let sqlMarkers = ["SELECT ", "FROM ", "WHERE ", "JOIN ", "INSERT ", "UPDATE ", "DELETE ", "GROUP BY", "ORDER BY"]
            if sqlMarkers.contains(where: { upper.contains($0) }) {
                hints += ["sql", "database", "query", "postgres", "mysql"]
            }
        case .image:
            hints += ["photo", "screenshot", "picture"]
        case .link:
            hints += ["url", "web", "website"]
        case .path:
            hints += ["file", "directory", "folder"]
        case .text:
            hints += ["note", "plain"]
        case .all:
            break
        }

        return hints.joined(separator: " ")
    }

    var searchableText: String {
        [content, ocrText, aiTitle, sourceApp ?? "", kind.rawValue, searchHints].joined(separator: " ").lowercased()
    }

    private static func compactLine(_ text: String, limit: Int) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard oneLine.count > limit else { return oneLine }
        return String(oneLine.prefix(limit)) + "…"
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var query = "" { didSet { scheduleQMDSearch() } }
    @Published var selectedFilter: ClipboardEntry.Kind = .all
    @Published private(set) var qmdSearchInProgress = false
    @Published private(set) var isQMDAvailable = false
    @Published private(set) var canUndoDelete = false
    @Published private(set) var overlayPresentedToken = UUID()
    @Published private(set) var lastRestoredEntryID: String?
    @Published private(set) var isOverlayVisible = false

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var qmdKeywordTask: Task<Void, Never>?
    private var qmdSemanticTask: Task<Void, Never>?

    private var qmdKeywordIDs: Set<String>? = nil
    private var qmdSemanticIDs: Set<String>? = nil
    private var qmdResultQuery = ""

    private struct DeletedSnapshot {
        let entry: ClipboardEntry
        let index: Int
        let deletedAt: Date
    }

    private var deletedStack: [DeletedSnapshot] = []
    private var pendingImageDeletions: [String: Date] = [:]
    private let undoWindow: TimeInterval = 20

    private let database = ClipboardDatabase()
    private let imageDirectory: URL
    private let qmdSearch: QMDSearchEngine
    private let imageTitleGenerator = ImageTitleGenerator()
    private var imageTitlesEnabled = true

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CBManager", isDirectory: true)
        let imageDirectory = base.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        self.imageDirectory = imageDirectory
        self.qmdSearch = QMDSearchEngine(baseDirectory: base)

        entries = database.loadEntries()

        let qmdSearch = self.qmdSearch
        Task { [weak self, qmdSearch] in
            let available = await qmdSearch.isAvailable()
            await MainActor.run {
                self?.isQMDAvailable = available
            }

            guard available else { return }
            let bootstrapEntries = await MainActor.run { self?.entries ?? [] }
            await qmdSearch.bootstrap(entries: bootstrapEntries)
        }

        startMonitoring()
    }

    var filteredEntries: [ClipboardEntry] {
        ClipboardSearch.rank(
            entries: entries,
            query: query,
            filter: selectedFilter,
            qmdResultQuery: qmdResultQuery,
            qmdKeywordIDs: qmdKeywordIDs,
            qmdSemanticIDs: qmdSemanticIDs
        )
    }

    func copyToClipboard(_ entry: ClipboardEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()

        if entry.kind == .image,
           let path = entry.imagePath,
           let image = NSImage(contentsOfFile: path) {
            pb.writeObjects([image])
            return
        }

        pb.setString(entry.content, forType: .string)
    }

    func overlayDidOpen() {
        isOverlayVisible = true
        overlayPresentedToken = UUID()
    }

    func overlayDidClose() {
        isOverlayVisible = false
    }

    func deleteEntry(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let removed = entries.remove(at: index)

        deletedStack.append(DeletedSnapshot(entry: removed, index: index, deletedAt: .now))
        trimDeletedStack()
        canUndoDelete = !deletedStack.isEmpty
        lastRestoredEntryID = nil

        database.delete(id: removed.id)

        if let imagePath = removed.imagePath {
            pendingImageDeletions[imagePath] = Date().addingTimeInterval(undoWindow)
        }

        if isQMDAvailable {
            Task { await qmdSearch.remove(id: removed.id) }
        }
        scheduleQMDSearch()
    }

    func undoDelete() {
        cleanupExpiredDeletedFiles()
        trimDeletedStack()
        guard let snapshot = deletedStack.popLast() else {
            NSSound.beep()
            canUndoDelete = false
            return
        }

        let insertIndex = min(snapshot.index, entries.count)
        entries.insert(snapshot.entry, at: insertIndex)

        database.insert(snapshot.entry)
        if isQMDAvailable {
            Task { await qmdSearch.upsert(snapshot.entry) }
        }

        if let path = snapshot.entry.imagePath {
            pendingImageDeletions.removeValue(forKey: path)
        }

        lastRestoredEntryID = snapshot.entry.id
        canUndoDelete = !deletedStack.isEmpty
        scheduleQMDSearch()
    }

    private func startMonitoring() {
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupExpiredDeletedFiles()
                self?.pollPasteboard()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let newEntry = captureClipboardEntry(from: pb) else { return }
        if isDuplicateOfLatest(newEntry) {
            if let path = newEntry.imagePath {
                try? FileManager.default.removeItem(atPath: path)
            }
            return
        }

        entries.insert(newEntry, at: 0)
        database.insert(newEntry)
        if isQMDAvailable {
            Task { await qmdSearch.upsert(newEntry) }
        }

        if newEntry.kind == .image {
            recognizeTextForImageEntry(newEntry)
            generateTitleForImageEntry(newEntry)
        }

        scheduleQMDSearch()
    }

    private func scheduleQMDSearch() {
        let normalizedQuery = ClipboardSearch.normalize(query)

        qmdKeywordTask?.cancel()
        qmdSemanticTask?.cancel()

        guard isQMDAvailable else {
            qmdResultQuery = normalizedQuery
            qmdKeywordIDs = nil
            qmdSemanticIDs = nil
            qmdSearchInProgress = false
            return
        }

        guard !normalizedQuery.isEmpty else {
            qmdResultQuery = ""
            qmdKeywordIDs = nil
            qmdSemanticIDs = nil
            qmdSearchInProgress = false
            return
        }

        qmdResultQuery = normalizedQuery
        qmdKeywordIDs = nil
        qmdSemanticIDs = nil

        // Keep short queries fuzzy-only for speed.
        guard ClipboardSearch.shouldRunKeywordQMD(normalizedQuery: normalizedQuery) else {
            qmdSearchInProgress = false
            return
        }

        qmdSearchInProgress = true

        qmdKeywordTask = Task { [weak self, qmdSearch] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let ids = await qmdSearch.keywordSearchIDs(query: normalizedQuery, limit: 220)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.qmdResultQuery == normalizedQuery else { return }
                self.qmdKeywordIDs = ids
                self.updateQMDSearchInProgress()
            }
        }

        // Semantic pass kicks in for longer queries.
        guard ClipboardSearch.shouldRunSemanticQMD(normalizedQuery: normalizedQuery) else {
            return
        }

        qmdSemanticTask = Task { [weak self, qmdSearch] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            let ids = await qmdSearch.semanticSearchIDs(query: normalizedQuery, limit: 120)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.qmdResultQuery == normalizedQuery else { return }
                self.qmdSemanticIDs = ids
                self.updateQMDSearchInProgress()
            }
        }
    }

    private func updateQMDSearchInProgress() {
        let keywordRunning = qmdKeywordTask != nil && !(qmdKeywordTask?.isCancelled ?? true) && qmdKeywordIDs == nil
        let semanticNeeded = ClipboardSearch.shouldRunSemanticQMD(normalizedQuery: qmdResultQuery)
        let semanticRunning = semanticNeeded && qmdSemanticTask != nil && !(qmdSemanticTask?.isCancelled ?? true) && qmdSemanticIDs == nil
        qmdSearchInProgress = keywordRunning || semanticRunning
    }

    private func trimDeletedStack() {
        let now = Date()
        deletedStack.removeAll { snapshot in
            let expired = now.timeIntervalSince(snapshot.deletedAt) > undoWindow
            if expired, let path = snapshot.entry.imagePath {
                pendingImageDeletions[path] = now
            }
            return expired
        }
    }

    private func cleanupExpiredDeletedFiles() {
        let now = Date()
        let expiredPaths = pendingImageDeletions
            .filter { $0.value <= now }
            .map(\.key)

        for path in expiredPaths {
            try? FileManager.default.removeItem(atPath: path)
            pendingImageDeletions.removeValue(forKey: path)
        }
    }

    private func isDuplicateOfLatest(_ newEntry: ClipboardEntry) -> Bool {
        guard let latest = entries.first else { return false }

        if latest.kind != .image && newEntry.kind != .image {
            return latest.kind == newEntry.kind && latest.content == newEntry.content
        }

        if latest.kind == .image,
           newEntry.kind == .image,
           let oldPath = latest.imagePath,
           let newPath = newEntry.imagePath {
            let fm = FileManager.default
            guard let oldSize = try? fm.attributesOfItem(atPath: oldPath)[.size] as? Int,
                  let newSize = try? fm.attributesOfItem(atPath: newPath)[.size] as? Int,
                  oldSize == newSize else {
                return false
            }
            guard let oldData = try? Data(contentsOf: URL(fileURLWithPath: oldPath)),
                  let newData = try? Data(contentsOf: URL(fileURLWithPath: newPath)) else {
                return false
            }
            return oldData == newData
        }

        return false
    }

    private func captureClipboardEntry(from pasteboard: NSPasteboard) -> ClipboardEntry? {
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClipboardEntry(
                id: UUID().uuidString,
                content: string,
                date: .now,
                sourceApp: sourceApp,
                kind: classify(string),
                imagePath: nil,
                ocrText: "",
                isOCRPending: false,
                aiTitle: "",
                isAITitlePending: false
            )
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let joined = urls.map(\.path).joined(separator: "\n")
            return ClipboardEntry(
                id: UUID().uuidString,
                content: joined,
                date: .now,
                sourceApp: sourceApp,
                kind: .path,
                imagePath: nil,
                ocrText: "",
                isOCRPending: false,
                aiTitle: "",
                isAITitlePending: false
            )
        }

        if let image = NSImage(pasteboard: pasteboard) {
            let entryID = UUID().uuidString
            guard let imagePath = persistImage(image, id: entryID) else { return nil }

            return ClipboardEntry(
                id: entryID,
                content: "",
                date: .now,
                sourceApp: sourceApp,
                kind: .image,
                imagePath: imagePath,
                ocrText: "",
                isOCRPending: true,
                aiTitle: "",
                isAITitlePending: true
            )
        }

        return nil
    }

    private func recognizeTextForImageEntry(_ entry: ClipboardEntry) {
        guard let path = entry.imagePath else { return }
        let entryID = entry.id

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let image = NSImage(contentsOfFile: path) else {
                await MainActor.run { self.markOCRCompleted(for: entryID, text: "") }
                return
            }

            let ocrText = await ImageTextRecognizer.recognizeText(from: image)
            await MainActor.run {
                self.markOCRCompleted(for: entryID, text: ocrText)
            }
        }
    }

    private func markOCRCompleted(for entryID: String, text: String) {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }

        entries[idx].ocrText = text
        entries[idx].isOCRPending = false

        database.updateOCR(id: entryID, ocrText: text, isPending: false)
        if isQMDAvailable {
            Task { await qmdSearch.upsert(entries[idx]) }
        }
        scheduleQMDSearch()
    }

    // MARK: - Age-based pruning

    /// Delete all entries older than `days` days. Returns the count of removed entries.
    @discardableResult
    func pruneEntries(olderThanDays days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let removed = database.deleteOlderThan(cutoff)

        // Remove from in-memory list.
        let removedIDs = Set(removed.map(\.id))
        entries.removeAll { removedIDs.contains($0.id) }

        // Clean up image files and QMD docs.
        for entry in removed {
            if let path = entry.imagePath {
                try? FileManager.default.removeItem(atPath: path)
                pendingImageDeletions.removeValue(forKey: path)
            }
            if isQMDAvailable {
                Task { await qmdSearch.remove(id: entry.id) }
            }
        }

        if !removed.isEmpty {
            scheduleQMDSearch()
        }

        return removed.count
    }

    // MARK: - AI image title generation

    func configureImageTitles(enabled: Bool, model: String) {
        imageTitlesEnabled = enabled
        Task { await imageTitleGenerator.setModel(model) }
    }

    private func generateTitleForImageEntry(_ entry: ClipboardEntry) {
        guard imageTitlesEnabled, let path = entry.imagePath else {
            markAITitleCompleted(for: entry.id, title: "")
            return
        }
        let entryID = entry.id

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let title = await self.imageTitleGenerator.generateTitle(forImageAt: path)
            await MainActor.run {
                self.markAITitleCompleted(for: entryID, title: title ?? "")
            }
        }
    }

    private func markAITitleCompleted(for entryID: String, title: String) {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }

        entries[idx].aiTitle = title
        entries[idx].isAITitlePending = false

        database.updateAITitle(id: entryID, aiTitle: title, isPending: false)
        if isQMDAvailable {
            Task { await qmdSearch.upsert(entries[idx]) }
        }
        scheduleQMDSearch()
    }

    private func persistImage(_ image: NSImage, id: String) -> String? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let destination = imageDirectory.appendingPathComponent("\(id).png")
        do {
            try png.write(to: destination)
            return destination.path
        } catch {
            return nil
        }
    }

    private func classify(_ text: String) -> ClipboardEntry.Kind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return .link
        }

        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            return .path
        }

        let codeHints = ["{", "}", "=>", "import ", "func ", "class ", "let ", "const ", "SELECT ", "#!/"]
        if codeHints.contains(where: { trimmed.contains($0) }) {
            return .code
        }

        return .text
    }
}
