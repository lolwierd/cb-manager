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

    /// Precomputed lowercased search text and one-line title. Updated via
    /// `refreshSearchableText()` when OCR or AI title state changes.
    private(set) var searchableText: String = ""
    private(set) var titleLine: String = ""

    // Custom init mirrors the memberwise init but precomputes derived text.
    init(
        id: String,
        content: String,
        date: Date,
        sourceApp: String?,
        kind: Kind,
        imagePath: String?,
        ocrText: String,
        isOCRPending: Bool,
        aiTitle: String = "",
        isAITitlePending: Bool = false
    ) {
        self.id = id
        self.content = content
        self.date = date
        self.sourceApp = sourceApp
        self.kind = kind
        self.imagePath = imagePath
        self.ocrText = ocrText
        self.isOCRPending = isOCRPending
        self.aiTitle = aiTitle
        self.isAITitlePending = isAITitlePending
        refreshSearchableText()
    }

    /// Call after mutating OCR or AI title state to keep derived text current.
    mutating func refreshSearchableText() {
        searchableText = Self.buildSearchableText(
            content: content, ocrText: ocrText, aiTitle: aiTitle,
            sourceApp: sourceApp, kind: kind
        )
        titleLine = Self.buildTitleLine(
            content: content,
            sourceApp: sourceApp,
            kind: kind,
            aiTitle: aiTitle,
            isAITitlePending: isAITitlePending
        )
    }

    /// Compact fallback summary for image rows without touching the file system.
    private static func imageSummary(sourceApp: String?) -> String {
        var parts: [String] = ["Image"]
        if let app = sourceApp, !app.isEmpty {
            parts.append("· \(app)")
        }
        return parts.joined(separator: " ")
    }

    var searchHints: String {
        Self.computeSearchHints(kind: kind, content: content)
    }

    /// Maximum characters of content to include in the search index.
    /// Searching deep into a multi-MB clipboard entry is pointless for
    /// fuzzy matching and extremely expensive.
    private static let searchContentLimit = 500
    /// Maximum characters to scan when generating a one-line list title.
    /// The overlay only needs a compact summary, not the full payload.
    private static let titleLineScanLimit = 512

    private static func computeSearchHints(kind: Kind, content: String) -> String {
        var hints: [String] = [kind.rawValue.lowercased()]

        switch kind {
        case .code:
            hints += ["snippet", "command", "query"]
            let upper = String(content.prefix(2000)).uppercased()
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

    private static func buildSearchableText(
        content: String, ocrText: String, aiTitle: String,
        sourceApp: String?, kind: Kind
    ) -> String {
        // Truncate content to avoid lowercasing / matching multi-MB strings.
        let truncatedContent = content.count > searchContentLimit
            ? String(content.prefix(searchContentLimit))
            : content
        let hints = computeSearchHints(kind: kind, content: content)
        return [truncatedContent, ocrText, aiTitle, sourceApp ?? "", kind.rawValue, hints]
            .joined(separator: " ")
            .lowercased()
    }

    private static func buildTitleLine(
        content: String,
        sourceApp: String?,
        kind: Kind,
        aiTitle: String,
        isAITitlePending: Bool
    ) -> String {
        switch kind {
        case .image:
            let trimmedTitle = aiTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                return compactLine(trimmedTitle, limit: 90)
            }
            if isAITitlePending {
                return imageSummary(sourceApp: sourceApp)
            }
            return imageSummary(sourceApp: sourceApp)
        default:
            return compactLine(content, limit: 96)
        }
    }

    private static func compactLine(_ text: String, limit: Int) -> String {
        let scanEnd = text.index(text.startIndex, offsetBy: titleLineScanLimit, limitedBy: text.endIndex) ?? text.endIndex
        let truncatedAtSource = scanEnd != text.endIndex
        let excerpt = String(text[..<scanEnd])

        let oneLine = excerpt
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard oneLine.count > limit else {
            return truncatedAtSource ? oneLine + "…" : oneLine
        }
        return String(oneLine.prefix(limit)) + "…"
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    private static let duplicateImageSampleByteCount = 16 * 1024
    private static let searchQueryDebounce: Duration = .milliseconds(120)

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var query = "" {
        didSet {
            if ClipboardSearch.normalize(query).isEmpty {
                recomputeFilteredEntries()
            } else {
                scheduleFilterRecompute()
            }
        }
    }
    @Published var selectedFilter: ClipboardEntry.Kind = .all {
        didSet { recomputeFilteredEntries() }
    }
    @Published private(set) var filteredEntries: [ClipboardEntry] = []
    @Published private(set) var filteredEntriesVersion: UInt = 0
    // QMD runtime integration is intentionally disabled for responsiveness.
    @Published private(set) var qmdSearchInProgress = false
    @Published private(set) var isQMDAvailable = false
    @Published private(set) var canUndoDelete = false
    @Published private(set) var overlayPresentedToken = UUID()
    @Published private(set) var lastRestoredEntryID: String?
    @Published private(set) var isOverlayVisible = false

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastDeletionCleanupCheck = Date.distantPast
    private var imageDuplicateSignatures: [String: ImageDuplicateSignature] = [:]
    private var filterRecomputeTask: Task<Void, Never>?
    private var filterRankingTask: Task<Void, Never>?
    private var filterRankingGeneration: UInt = 0

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
    private let imageTitleGenerator = ImageTitleGenerator()
    private var imageTitlesEnabled = true

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CBManager", isDirectory: true)
        let imageDirectory = base.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        self.imageDirectory = imageDirectory

        entries = database.loadEntries()
        recomputeFilteredEntries()

        startMonitoring()
    }

    /// Debounced recompute — used by the query `didSet` so fast typing
    /// doesn't block the main thread on every keystroke.
    private func scheduleFilterRecompute() {
        filterRecomputeTask?.cancel()
        filterRecomputeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.searchQueryDebounce)
            guard !Task.isCancelled else { return }
            self?.recomputeFilteredEntries()
        }
    }

    /// Immediate recompute — used by filter changes, delete, undo, etc.
    /// Also cancels any pending debounced recompute.
    private func recomputeFilteredEntries() {
        filterRecomputeTask?.cancel()
        filterRankingTask?.cancel()

        let rankingGeneration = filterRankingGeneration &+ 1
        filterRankingGeneration = rankingGeneration

        let entriesSnapshot = entries
        let querySnapshot = query
        let filterSnapshot = selectedFilter

        filterRankingTask = Task.detached(priority: .utility) { [weak self] in
            let ranked = ClipboardSearch.rank(
                entries: entriesSnapshot,
                query: querySnapshot,
                filter: filterSnapshot,
                qmdResultQuery: "",
                qmdKeywordIDs: nil,
                qmdSemanticIDs: nil
            )
            guard !Task.isCancelled else { return }

            Task { @MainActor [weak self] in
                guard let self, self.filterRankingGeneration == rankingGeneration else { return }
                self.filteredEntries = ranked
                self.filteredEntriesVersion &+= 1
            }
        }
    }

    func copyToClipboard(_ entry: ClipboardEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()

        if entry.kind == .image,
           let path = entry.imagePath,
           let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) {
            pb.setData(data, forType: .png)
        } else {
            pb.setString(entry.content, forType: .string)
        }

        // Suppress the next pasteboard poll so we don't re-capture
        // the item we just placed on the clipboard.
        lastChangeCount = pb.changeCount
    }

    /// Move an existing entry to the top of the list (most recent).
    func bumpToTop(_ entry: ClipboardEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        if idx == 0 { return } // already at top

        let existing = entries.remove(at: idx)
        let updated = ClipboardEntry(
            id: existing.id,
            content: existing.content,
            date: .now,
            sourceApp: existing.sourceApp,
            kind: existing.kind,
            imagePath: existing.imagePath,
            ocrText: existing.ocrText,
            isOCRPending: existing.isOCRPending,
            aiTitle: existing.aiTitle,
            isAITitlePending: existing.isAITitlePending
        )
        entries.insert(updated, at: 0)
        database.insert(updated) // INSERT OR REPLACE updates the date
        recomputeFilteredEntries()
    }

    func overlayDidOpen(resetSearch: Bool = true) {
        isOverlayVisible = true
        // Clear stale search state so the overlay opens instantly.
        // Skip reset when re-showing after preview dismiss.
        if resetSearch {
            if !query.isEmpty {
                query = ""
            }
            if selectedFilter != .all {
                selectedFilter = .all
            }
        }
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

        recomputeFilteredEntries()
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
        if let path = snapshot.entry.imagePath {
            pendingImageDeletions.removeValue(forKey: path)
        }

        lastRestoredEntryID = snapshot.entry.id
        canUndoDelete = !deletedStack.isEmpty
        recomputeFilteredEntries()
    }

    private func startMonitoring() {
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMonitoringTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func handleMonitoringTick() {
        if !isOverlayVisible,
           !pendingImageDeletions.isEmpty,
           Date().timeIntervalSince(lastDeletionCleanupCheck) >= 2 {
            cleanupExpiredDeletedFiles()
            lastDeletionCleanupCheck = .now
        }

        guard !isOverlayVisible else { return }
        pollPasteboard()
    }

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let newEntry = captureClipboardEntry(from: pb) else { return }
        if let existingIdx = indexOfDuplicate(newEntry) {
            // Already have this content — move to top instead of inserting.
            if let path = newEntry.imagePath {
                try? FileManager.default.removeItem(atPath: path)
            }
            if existingIdx != 0 {
                let existing = entries.remove(at: existingIdx)
                let bumped = ClipboardEntry(
                    id: existing.id,
                    content: existing.content,
                    date: .now,
                    sourceApp: existing.sourceApp,
                    kind: existing.kind,
                    imagePath: existing.imagePath,
                    ocrText: existing.ocrText,
                    isOCRPending: existing.isOCRPending,
                    aiTitle: existing.aiTitle,
                    isAITitlePending: existing.isAITitlePending
                )
                entries.insert(bumped, at: 0)
                database.insert(bumped)
                recomputeFilteredEntries()
            }
            return
        }

        entries.insert(newEntry, at: 0)
        database.insert(newEntry)
        if newEntry.kind == .image {
            recognizeTextForImageEntry(newEntry)
            generateTitleForImageEntry(newEntry)
        }

        recomputeFilteredEntries()
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

        expiredPaths.forEach { pendingImageDeletions.removeValue(forKey: $0) }
        for path in expiredPaths {
            imageDuplicateSignatures.removeValue(forKey: path)
        }

        guard !expiredPaths.isEmpty else { return }
        DispatchQueue.global(qos: .background).async {
            for path in expiredPaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    /// Return the index of the first existing entry whose content matches
    /// the new entry, or `nil` if no match is found. For text-based entries
    /// we compare kind + content; for images we compare file size + bytes.
    private func indexOfDuplicate(_ newEntry: ClipboardEntry) -> Int? {
        for (idx, existing) in entries.enumerated() {
            if existing.kind != .image && newEntry.kind != .image {
                if existing.kind == newEntry.kind && existing.content == newEntry.content {
                    return idx
                }
            } else if existing.kind == .image,
                      newEntry.kind == .image,
                      let oldPath = existing.imagePath,
                      let newPath = newEntry.imagePath {
                guard let oldSignature = imageDuplicateSignature(at: oldPath),
                      let newSignature = imageDuplicateSignature(at: newPath),
                      oldSignature == newSignature else {
                    continue
                }
                return idx
            }
        }
        return nil
    }

    private func imageDuplicateSignature(at path: String) -> ImageDuplicateSignature? {
        if let cached = imageDuplicateSignatures[path] {
            return cached
        }

        guard let signature = Self.readImageDuplicateSignature(at: path) else {
            return nil
        }
        imageDuplicateSignatures[path] = signature
        return signature
    }

    private static func readImageDuplicateSignature(at path: String) -> ImageDuplicateSignature? {
        let fileURL = URL(fileURLWithPath: path)
        guard let fileSizeNumber = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber else {
            return nil
        }
        let fileSize = fileSizeNumber.intValue
        let sampleSize = min(fileSize, duplicateImageSampleByteCount)

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        guard let headSample = try? handle.read(upToCount: sampleSize) ?? Data() else {
            return nil
        }

        let tailSample: Data
        if fileSize <= sampleSize {
            tailSample = headSample
        } else {
            let tailOffset = UInt64(max(fileSize - sampleSize, 0))
            try? handle.seek(toOffset: tailOffset)
            tailSample = (try? handle.readToEnd()) ?? Data()
        }

        return ImageDuplicateSignature(
            fileSize: fileSize,
            headSample: headSample,
            tailSample: tailSample
        )
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
        entries[idx].refreshSearchableText()

        database.updateOCR(id: entryID, ocrText: text, isPending: false)
        scheduleFilterRecompute()
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

        // Clean up persisted image files for removed entries.
        for entry in removed {
            if let path = entry.imagePath {
                try? FileManager.default.removeItem(atPath: path)
                pendingImageDeletions.removeValue(forKey: path)
            }
        }

        if !removed.isEmpty {
            recomputeFilteredEntries()
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
        entries[idx].refreshSearchableText()

        database.updateAITitle(id: entryID, aiTitle: title, isPending: false)
        scheduleFilterRecompute()
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

private struct ImageDuplicateSignature: Equatable {
    let fileSize: Int
    let headSample: Data
    let tailSample: Data
}
