import AppKit
import Carbon
import SwiftUI

struct SearchOverlayView: View {
    nonisolated private static let inlinePreviewCharacterLimit = 4_000
    nonisolated private static let metadataScanCharacterLimit = 6_000
    nonisolated private static let initialVisibleEntries = 100
    nonisolated private static let visibleEntriesPageSize = 200
    nonisolated private static let visibleEntriesPrefetchThreshold = 24

    @ObservedObject var store: ClipboardStore
    let onClose: () -> Void
    let onConfirm: (ClipboardEntry) -> Void
    let onDelete: (ClipboardEntry) -> Void
    let onUndoDelete: () -> Void
    let onOpenPreview: (ClipboardEntry) -> Void
    var onOpenSettings: (() -> Void)?


    @State private var selectedID: ClipboardEntry.ID?
    @State private var keyMonitor: Any?
    @State private var groupedEntries: [EntryGroup] = []
    @State private var flattenedEntryIDs: [ClipboardEntry.ID] = []
    @State private var rebuildVisibleEntriesTask: Task<Void, Never>?
    @State private var selectedEntryDetailsTask: Task<Void, Never>?
    @State private var selectedEntryDetails: SelectedEntryDetails?
    @State private var selectedEntryDetailsGeneration: UInt = 0
    @State private var visibleEntryLimit = SearchOverlayView.initialVisibleEntries
    @State private var totalFilteredEntryCount = 0
    @State private var isGrowingVisibleEntryWindow = false
    @State private var pendingScrollSelectionID: ClipboardEntry.ID?
    @FocusState private var isSearchFocused: Bool

    private var selectedEntry: ClipboardEntry? {
        let entries = store.filteredEntries
        guard let selectedID else { return entries.first }
        return entries.first { $0.id == selectedID } ?? entries.first
    }

    private var filterTitle: String {
        store.selectedFilter == .all ? "All" : store.selectedFilter.rawValue
    }

    var body: some View {
        let panelShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        VStack(spacing: 0) {
            searchHeader
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

            Divider().overlay(.white.opacity(0.12))

            HStack(spacing: 0) {
                historyList
                    .frame(width: 370)

                Divider().overlay(.white.opacity(0.08))

                previewPane
            }
        }
        .background(
            panelShape
                .fill(.regularMaterial)
                .overlay(panelShape.fill(Color.black.opacity(0.10)))
        )
        .clipShape(panelShape)
        .overlay(
            panelShape
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        )
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            resetVisibleEntryWindow()
            scheduleVisibleEntriesRebuild(
                selectLatestAfterRebuild: true,
                scrollSelectionIntoViewAfterRebuild: true
            )
            focusSearchField()
            updateKeyMonitorForOverlayVisibility()
        }
        .onDisappear {
            rebuildVisibleEntriesTask?.cancel()
            selectedEntryDetailsTask?.cancel()
            removeKeyMonitor()
        }
        .onChange(of: store.filteredEntriesVersion) { _, _ in
            guard store.isOverlayVisible else { return }
            resetVisibleEntryWindow()
            scheduleVisibleEntriesRebuild(
                refreshSelectionAfterRebuild: true,
                scrollSelectionIntoViewAfterRebuild: true
            )
        }
        .onChange(of: store.overlayPresentedToken) { _, _ in
            resetVisibleEntryWindow()
            scheduleVisibleEntriesRebuild(
                selectLatestAfterRebuild: true,
                scrollSelectionIntoViewAfterRebuild: true
            )
            focusSearchField()
        }
        .onChange(of: store.isOverlayVisible) { _, _ in
            updateKeyMonitorForOverlayVisibility()
        }
        .onChange(of: store.lastRestoredEntryID) { _, restoredID in
            guard let restoredID else { return }
            selectedID = restoredID
            pendingScrollSelectionID = restoredID
            focusSearchField()
        }
        .onChange(of: selectedID) { _, _ in
            scheduleSelectedEntryDetailsUpdate()
        }
        .onMoveCommand(perform: handleMoveCommand)
        .onExitCommand(perform: onClose)
    }

    private var searchHeader: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)

            TextField("Search clipboard history", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .focused($isSearchFocused)
                .padding(.leading, 8)
                .onSubmit {
                    if let selectedEntry { onConfirm(selectedEntry) }
                }

            if store.isQMDAvailable {
                ZStack {
                    ProgressView()
                        .controlSize(.small)
                        .opacity(store.qmdSearchInProgress ? 1 : 0)
                }
                .frame(width: 16, height: 16)
                .padding(.trailing, 8)

                Text("QMD")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.09))
                    )

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 10)
            }

            Menu {
                ForEach(ClipboardEntry.Kind.allCases) { kind in
                    Button {
                        store.selectedFilter = kind
                    } label: {
                        HStack {
                            Label(kind.rawValue, systemImage: kind.symbol)
                            if store.selectedFilter == kind {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(filterTitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .padding(.vertical, 4)
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(groupedEntries) { group in
                    Section {
                        ForEach(group.items) { entry in
                            row(for: entry)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 14)
                    }
                }
            }
            .listStyle(.plain)
            .contentMargins(.vertical, 10, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onAppear {
                if let selectedID {
                    proxy.scrollTo(selectedID, anchor: .top)
                }
            }
            .onChange(of: pendingScrollSelectionID) { _, requestedID in
                guard let requestedID else { return }
                pendingScrollSelectionID = nil
                proxy.scrollTo(requestedID, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func row(for entry: EntryListItem) -> some View {
        EntryRow(entry: entry, isSelected: selectedID == entry.id)
            .equatable()
            .id(entry.id)
            .onAppear {
                loadMoreVisibleEntriesIfNeeded(after: entry.id)
            }
            .onTapGesture {
                selectedID = entry.id
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    guard let confirmedEntry = selectedEntry(matching: entry.id) else { return }
                    onConfirm(confirmedEntry)
                }
            )
    }

    private var previewPane: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
            if let selectedEntry {
                let selectedDetails = details(for: selectedEntry)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if selectedEntry.kind == .image {
                            imagePreview(
                                for: selectedEntry,
                                availableSize: geometry.size,
                                details: selectedDetails
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                if let selectedDetails {
                                    Text(selectedDetails.previewText)
                                        .font(font(for: selectedEntry.kind))
                                        .frame(maxWidth: .infinity, alignment: .topLeading)

                                    if selectedDetails.isPreviewTruncated {
                                        Text("Showing an excerpt here for speed. Use ⌘Y for the full preview.")
                                            .font(.system(size: 11, weight: .regular, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text("Loading preview…")
                                    }
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }

                        Divider().overlay(.white.opacity(0.08))

                        metadataSection(for: selectedEntry, details: selectedDetails)
                            .padding(.top, 6)
                    }
                    .padding(20)
                    .padding(.bottom, 4)
                }

                Divider().overlay(.white.opacity(0.08))

                HStack {
                    Spacer()
                    Text("↩ Paste   •   ⌘Y Preview   •   ⌘D Delete   •   ⌘Z Undo")
                }
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            } else {
                ContentUnavailableView("No clips yet", systemImage: "clipboard", description: Text("Copy something and it will appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func imagePreview(
        for entry: ClipboardEntry,
        availableSize: CGSize,
        details: SelectedEntryDetails?
    ) -> some View {
        if let imagePath = entry.imagePath {
            let imageSize = details?.imageDimensions
            let previewHeight = adaptiveImagePreviewHeight(for: availableSize, imageSize: imageSize)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.05))

                SelectedImagePreviewView(
                    path: imagePath,
                    maxPixelSize: quantizedPreviewPixelSize(for: availableSize)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )

            if entry.isOCRPending {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Indexing text in image…")
                                        .font(.system(size: 11, weight: .regular, design: .rounded))
                                        .foregroundStyle(.secondary)
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.05))
                .frame(height: adaptiveImagePreviewHeight(for: availableSize, imageSize: nil))
                .overlay {
                    Text("Image unavailable")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func adaptiveImagePreviewHeight(for availableSize: CGSize, imageSize: CGSize?) -> CGFloat {
        let minHeight: CGFloat = 300
        let maxHeight: CGFloat = 460

        let byContainer = availableSize.height * 0.60
        let byWidth = availableSize.width * 0.55
        var target = min(byContainer, byWidth)

        if let imageSize, imageSize.height > imageSize.width {
            target *= 1.12
        }

        return min(max(target, minHeight), maxHeight)
    }

    private func quantizedPreviewPixelSize(for availableSize: CGSize) -> CGFloat {
        let rawSize = max(availableSize.width, availableSize.height) * 2
        return max(256, ceil(rawSize / 64) * 64)
    }

    private func resetVisibleEntryWindow() {
        visibleEntryLimit = Self.initialVisibleEntries
        isGrowingVisibleEntryWindow = false
    }

    private func loadMoreVisibleEntriesIfNeeded(after entryID: ClipboardEntry.ID) {
        guard store.isOverlayVisible,
              !isGrowingVisibleEntryWindow,
              totalFilteredEntryCount > flattenedEntryIDs.count,
              let index = flattenedEntryIDs.firstIndex(of: entryID),
              index >= flattenedEntryIDs.count - Self.visibleEntriesPrefetchThreshold else {
            return
        }

        let newLimit = min(
            max(visibleEntryLimit, flattenedEntryIDs.count) + Self.visibleEntriesPageSize,
            totalFilteredEntryCount
        )
        guard newLimit > visibleEntryLimit else { return }

        isGrowingVisibleEntryWindow = true
        visibleEntryLimit = newLimit
        scheduleVisibleEntriesRebuild(
            refreshSelectionAfterRebuild: false,
            selectLatestAfterRebuild: false,
            refreshSelectedEntryDetailsAfterRebuild: false
        )
    }

    private func scheduleVisibleEntriesRebuild(
        refreshSelectionAfterRebuild: Bool = false,
        selectLatestAfterRebuild: Bool = false,
        scrollSelectionIntoViewAfterRebuild: Bool = false,
        refreshSelectedEntryDetailsAfterRebuild: Bool = true
    ) {
        rebuildVisibleEntriesTask?.cancel()

        let totalEntries = store.filteredEntries.count
        let entriesSnapshot = Array(store.filteredEntries.prefix(visibleEntryLimit))
        rebuildVisibleEntriesTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }

            let (groups, flattenedIDs) = Self.makeEntryGroups(from: entriesSnapshot)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isGrowingVisibleEntryWindow = false
                totalFilteredEntryCount = totalEntries
                groupedEntries = groups
                flattenedEntryIDs = flattenedIDs
                if selectLatestAfterRebuild {
                    selectLatestEntry()
                } else if refreshSelectionAfterRebuild {
                    refreshSelection()
                }
                if scrollSelectionIntoViewAfterRebuild {
                    pendingScrollSelectionID = selectedID
                }
                if refreshSelectedEntryDetailsAfterRebuild {
                    scheduleSelectedEntryDetailsUpdate()
                }
            }
        }
    }

    nonisolated private static func makeEntryGroups(from entries: [ClipboardEntry]) -> ([EntryGroup], [ClipboardEntry.ID]) {
        let calendar = Calendar.current
        var today: [EntryListItem] = []
        var yesterday: [EntryListItem] = []
        var earlier: [EntryListItem] = []
        var flattenedIDs: [ClipboardEntry.ID] = []

        today.reserveCapacity(entries.count)
        yesterday.reserveCapacity(min(entries.count, 64))
        earlier.reserveCapacity(entries.count)
        flattenedIDs.reserveCapacity(entries.count)

        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 64), Task.isCancelled {
                return ([], [])
            }

            let listItem = EntryListItem(entry: entry)
            flattenedIDs.append(listItem.id)
            if calendar.isDateInToday(entry.date) {
                today.append(listItem)
            } else if calendar.isDateInYesterday(entry.date) {
                yesterday.append(listItem)
            } else {
                earlier.append(listItem)
            }
        }

        var groups: [EntryGroup] = []
        groups.reserveCapacity(3)
        if !today.isEmpty {
            groups.append(EntryGroup(title: "Today", items: today))
        }
        if !yesterday.isEmpty {
            groups.append(EntryGroup(title: "Yesterday", items: yesterday))
        }
        if !earlier.isEmpty {
            groups.append(EntryGroup(title: "Earlier", items: earlier))
        }
        return (groups, flattenedIDs)
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func selectLatestEntry() {
        selectedID = flattenedEntryIDs.first
    }

    private func refreshSelection() {
        if let selectedID,
           flattenedEntryIDs.contains(selectedID) {
            return
        }
        selectedID = flattenedEntryIDs.first
    }

    private func selectedEntry(matching id: ClipboardEntry.ID) -> ClipboardEntry? {
        store.filteredEntries.first { $0.id == id }
    }

    private func details(for entry: ClipboardEntry) -> SelectedEntryDetails? {
        guard let selectedEntryDetails,
              selectedEntryDetails.entryID == entry.id else {
            return nil
        }
        return selectedEntryDetails
    }

    private func scheduleSelectedEntryDetailsUpdate() {
        guard let entry = selectedEntry else {
            selectedEntryDetailsTask?.cancel()
            selectedEntryDetails = nil
            return
        }

        selectedEntryDetailsTask?.cancel()
        let generation = selectedEntryDetailsGeneration &+ 1
        selectedEntryDetailsGeneration = generation
        let entrySnapshot = entry

        selectedEntryDetailsTask = Task.detached(priority: .utility) {
            let details = Self.buildSelectedEntryDetails(for: entrySnapshot)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard selectedEntryDetailsGeneration == generation,
                      selectedID == entrySnapshot.id else { return }
                selectedEntryDetails = details
            }
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            moveSelection(by: -1)
        case .down:
            moveSelection(by: 1)
        default:
            break
        }
    }

    private func updateKeyMonitorForOverlayVisibility() {
        if store.isOverlayVisible {
            installKeyMonitor()
        } else {
            removeKeyMonitor()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard store.isOverlayVisible else { return false }
        let commandOnly = event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command]

        switch Int(event.keyCode) {
        case Int(kVK_UpArrow):
            moveSelection(by: -1)
            return true
        case Int(kVK_DownArrow):
            moveSelection(by: 1)
            return true
        case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
            guard let selectedEntry else { return false }
            onConfirm(selectedEntry)
            return true
        case Int(kVK_ANSI_Y):
            guard commandOnly, let selectedEntry else { return false }
            onOpenPreview(selectedEntry)
            return true
        case Int(kVK_ANSI_D):
            guard commandOnly, let selectedEntry else { return false }
            onDelete(selectedEntry)
            return true
        case Int(kVK_ANSI_Z):
            guard commandOnly else { return false }
            // Prefer app-level restore when we actually have a deleted entry.
            guard store.canUndoDelete else { return false }
            onUndoDelete()
            return true
        case Int(kVK_ANSI_Comma):
            guard commandOnly else { return false }
            onOpenSettings?()
            return true
        case Int(kVK_Escape):
            onClose()
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !flattenedEntryIDs.isEmpty else { return }

        guard let selectedID,
              let idx = flattenedEntryIDs.firstIndex(of: selectedID) else {
            self.selectedID = flattenedEntryIDs.first
            pendingScrollSelectionID = self.selectedID
            return
        }

        let newIndex = min(max(idx + delta, 0), flattenedEntryIDs.count - 1)
        self.selectedID = flattenedEntryIDs[newIndex]
        pendingScrollSelectionID = self.selectedID
    }

    @ViewBuilder
    private func metadataSection(for entry: ClipboardEntry, details: SelectedEntryDetails?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Information")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            if let details {
                ForEach(Array(details.metadataRows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 8) {
                        Text(row.title)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(row.value)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .padding(.vertical, 6)

                    if index < details.metadataRows.count - 1 {
                        Divider().overlay(.white.opacity(0.06))
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading information…")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .padding(.vertical, 6)
            }
        }
    }

    private func font(for kind: ClipboardEntry.Kind) -> Font {
        switch kind {
        case .code, .path:
            return .system(size: 14, weight: .regular, design: .monospaced)
        default:
            return .system(size: 14, weight: .regular, design: .rounded)
        }
    }

    nonisolated private static func buildSelectedEntryDetails(for entry: ClipboardEntry) -> SelectedEntryDetails {
        if entry.kind == .image {
            let imageSize = entry.imagePath.flatMap(ThumbnailCache.imageDimensions)
            var rows: [MetadataRow] = []

            let trimmedTitle = entry.aiTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                rows.append(MetadataRow(title: "Title", value: trimmedTitle))
            } else if entry.isAITitlePending {
                rows.append(MetadataRow(title: "Title", value: "Generating…"))
            }

            rows.append(contentsOf: [
                MetadataRow(title: "Type", value: entry.kind.rawValue),
                MetadataRow(title: "Source", value: entry.sourceApp ?? "Unknown"),
                MetadataRow(
                    title: "Dimensions",
                    value: imageSize.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "Unknown"
                ),
                MetadataRow(
                    title: "Copied",
                    value: entry.date.formatted(date: .abbreviated, time: .shortened)
                )
            ])

            if entry.isOCRPending {
                rows.append(MetadataRow(title: "OCR", value: "Extracting text…"))
            }

            return SelectedEntryDetails(
                entryID: entry.id,
                previewText: "",
                isPreviewTruncated: false,
                imageDimensions: imageSize,
                metadataRows: rows
            )
        }

        let preview = truncatedPrefix(of: entry.content, limit: inlinePreviewCharacterLimit)
        let stats = inlineMetadataStats(for: entry.content)
        return SelectedEntryDetails(
            entryID: entry.id,
            previewText: preview.text,
            isPreviewTruncated: preview.truncated,
            imageDimensions: nil,
            metadataRows: [
                MetadataRow(title: "Type", value: entry.kind.rawValue),
                MetadataRow(title: "Source", value: entry.sourceApp ?? "Unknown"),
                MetadataRow(title: "Characters", value: stats.characterLabel),
                MetadataRow(title: "Words", value: stats.wordLabel),
                MetadataRow(
                    title: "Copied",
                    value: entry.date.formatted(date: .abbreviated, time: .shortened)
                )
            ]
        )
    }

    nonisolated private static func inlineMetadataStats(for content: String) -> (characterLabel: String, wordLabel: String) {
        let preview = truncatedPrefix(of: content, limit: metadataScanCharacterLimit)
        let characterCount = preview.text.count
        let wordCount = preview.text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count

        let suffix = preview.truncated ? "+" : ""
        return ("\(characterCount)\(suffix)", "\(wordCount)\(suffix)")
    }

    nonisolated private static func truncatedPrefix(of text: String, limit: Int) -> (text: String, truncated: Bool) {
        let end = text.index(text.startIndex, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        return (String(text[..<end]), end != text.endIndex)
    }
}

private struct EntryRow: View, Equatable {
    let entry: EntryListItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            thumbnailOrIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.titleLine)
                    .lineLimit(1)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)

                    if entry.kind == .image, entry.isOCRPending {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(height: 58)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? .white.opacity(0.16) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? .white.opacity(0.22) : .clear, lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnailOrIcon: some View {
        if entry.kind == .image,
           let imagePath = entry.imagePath {
            EntryRowThumbnailView(path: imagePath)
        } else {
            Image(systemName: entry.kind.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.leading, 7)
        }
    }
}

private struct EntryGroup: Identifiable, Sendable {
    var id: String { title }
    let title: String
    let items: [EntryListItem]
}

private struct EntryListItem: Identifiable, Hashable, Sendable {
    let id: ClipboardEntry.ID
    let kind: ClipboardEntry.Kind
    let titleLine: String
    let date: Date
    let imagePath: String?
    let isOCRPending: Bool

    init(entry: ClipboardEntry) {
        id = entry.id
        kind = entry.kind
        titleLine = entry.titleLine
        date = entry.date
        imagePath = entry.imagePath
        isOCRPending = entry.isOCRPending
    }
}

private struct SelectedEntryDetails {
    let entryID: String
    let previewText: String
    let isPreviewTruncated: Bool
    let imageDimensions: CGSize?
    let metadataRows: [MetadataRow]
}

private struct MetadataRow {
    let title: String
    let value: String
}

private struct EntryRowThumbnailView: View {
    let path: String

    @State private var loadGeneration: UInt = 0
    @State private var displayedThumbnail: NSImage?

    var body: some View {
        let thumbnail = displayedThumbnail ?? ThumbnailCache.shared.cachedThumbnail(for: path)

        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.06))

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
        .onAppear(perform: scheduleLoad)
        .onChange(of: path) { _, _ in
            scheduleLoad()
        }
    }

    private func scheduleLoad() {
        let generation = loadGeneration &+ 1
        loadGeneration = generation
        displayedThumbnail = ThumbnailCache.shared.cachedThumbnail(for: path)

        if displayedThumbnail != nil {
            return
        }

        let pathSnapshot = path
        DispatchQueue.global(qos: .userInitiated).async {
            let thumbnail = ThumbnailCache.shared.thumbnail(for: pathSnapshot)
            DispatchQueue.main.async {
                guard loadGeneration == generation else { return }
                displayedThumbnail = thumbnail
            }
        }
    }
}

private struct SelectedImagePreviewView: View {
    let path: String
    let maxPixelSize: CGFloat

    @State private var loadGeneration: UInt = 0
    @State private var displayedImage: NSImage?

    var body: some View {
        let image = displayedImage ?? ThumbnailCache.shared.cachedThumbnail(
            for: path,
            maxPixelSize: quantizedMaxPixelSize
        )

        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .onAppear(perform: scheduleLoad)
        .onChange(of: path) { _, _ in
            scheduleLoad()
        }
        .onChange(of: quantizedMaxPixelSize) { _, _ in
            scheduleLoad()
        }
    }

    private var quantizedMaxPixelSize: CGFloat {
        max(256, ceil(maxPixelSize / 64) * 64)
    }

    private func scheduleLoad() {
        let generation = loadGeneration &+ 1
        loadGeneration = generation
        displayedImage = ThumbnailCache.shared.cachedThumbnail(
            for: path,
            maxPixelSize: quantizedMaxPixelSize
        )

        if displayedImage != nil {
            return
        }

        let pathSnapshot = path
        let requestedSize = quantizedMaxPixelSize
        DispatchQueue.global(qos: .userInitiated).async {
            let image = ThumbnailCache.shared.thumbnail(
                for: pathSnapshot,
                maxPixelSize: requestedSize
            )
            DispatchQueue.main.async {
                guard loadGeneration == generation else { return }
                displayedImage = image
            }
        }
    }
}
