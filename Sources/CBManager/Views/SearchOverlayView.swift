import AppKit
import Carbon
import SwiftUI

struct SearchOverlayView: View {
    @ObservedObject var store: ClipboardStore
    let onClose: () -> Void
    let onConfirm: (ClipboardEntry) -> Void
    let onDelete: (ClipboardEntry) -> Void
    let onUndoDelete: () -> Void
    let onOpenPreview: (ClipboardEntry) -> Void

    @State private var selectedID: ClipboardEntry.ID?
    @State private var keyMonitor: Any?
    @FocusState private var isSearchFocused: Bool

    private var flattenedEntries: [ClipboardEntry] {
        groupedEntries.flatMap(\.items)
    }

    private var selectedEntry: ClipboardEntry? {
        guard let selectedID else { return flattenedEntries.first }
        return flattenedEntries.first { $0.id == selectedID }
    }

    private var groupedEntries: [EntryGroup] {
        let calendar = Calendar.current

        let groups = Dictionary(grouping: store.filteredEntries) { entry -> String in
            if calendar.isDateInToday(entry.date) { return "Today" }
            if calendar.isDateInYesterday(entry.date) { return "Yesterday" }
            return "Earlier"
        }

        return ["Today", "Yesterday", "Earlier"].compactMap { key in
            guard let items = groups[key], !items.isEmpty else { return nil }
            return EntryGroup(title: key, items: items)
        }
    }

    private var filterTitle: String {
        store.selectedFilter == .all ? "All" : store.selectedFilter.rawValue
    }

    var body: some View {
        let panelShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        VStack(spacing: 0) {
            searchHeader
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            Divider().overlay(.white.opacity(0.12))

            HStack(spacing: 0) {
                historyList
                    .frame(width: 370)

                Divider().overlay(.white.opacity(0.08))

                previewPane
            }
        }
        .background(panelShape.fill(.ultraThinMaterial))
        .clipShape(panelShape)
        .overlay(
            panelShape
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            applyOpenDefaults()
            updateKeyMonitorForOverlayVisibility()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: store.filteredEntries.map(\.id)) { _, _ in
            refreshSelection()
        }
        .onChange(of: store.overlayPresentedToken) { _, _ in
            applyOpenDefaults()
        }
        .onChange(of: store.isOverlayVisible) { _, _ in
            updateKeyMonitorForOverlayVisibility()
        }
        .onChange(of: store.lastRestoredEntryID) { _, restoredID in
            guard let restoredID else { return }
            selectedID = restoredID
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onMoveCommand(perform: handleMoveCommand)
        .onExitCommand(perform: onClose)
    }

    private var searchHeader: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)

            TextField("Search clipboard history", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular, design: .rounded))
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
                HStack(spacing: 6) {
                    Text(filterTitle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 90)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groupedEntries) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 14)

                            ForEach(group.items) { entry in
                                EntryRow(entry: entry, isSelected: selectedID == entry.id)
                                    .id(entry.id)
                                    .onTapGesture {
                                        selectedID = entry.id
                                    }
                                    .onTapGesture(count: 2) {
                                        onConfirm(entry)
                                    }
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
            }
            .onAppear {
                if let selectedID {
                    proxy.scrollTo(selectedID, anchor: .top)
                }
            }
            .onChange(of: selectedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var previewPane: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
            if let selectedEntry {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(selectedEntry.kind.rawValue, systemImage: selectedEntry.kind.symbol)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.12))
                            )

                        if selectedEntry.kind == .image, selectedEntry.isOCRPending {
                            Label("Extracting text…", systemImage: "sparkles")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(selectedEntry.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if selectedEntry.kind == .image {
                        imagePreview(for: selectedEntry, availableSize: geometry.size)
                    } else {
                        ScrollView {
                            Text(selectedEntry.content)
                                .font(font(for: selectedEntry.kind))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(.bottom, 20)
                        }
                    }

                    Divider().overlay(.white.opacity(0.08))

                    metadataSection(for: selectedEntry)
                        .padding(.top, 6)

                    Divider().overlay(.white.opacity(0.08))

                    HStack {
                        Spacer()
                        Text("↩ Paste   •   ⌘Y Preview   •   ⌘D Delete   •   ⌘Z Undo")
                    }
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            } else {
                ContentUnavailableView("No clips yet", systemImage: "clipboard", description: Text("Copy something and it will appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func imagePreview(for entry: ClipboardEntry, availableSize: CGSize) -> some View {
        if let imagePath = entry.imagePath,
           let image = NSImage(contentsOfFile: imagePath) {
            let previewHeight = adaptiveImagePreviewHeight(for: availableSize, imageSize: image.size)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.05))

                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
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
        let minHeight: CGFloat = 240
        let maxHeight: CGFloat = 300

        let byContainer = availableSize.height * 0.40
        let byWidth = availableSize.width * 0.34
        var target = min(byContainer, byWidth)

        if let imageSize, imageSize.height > imageSize.width {
            target *= 1.08
        }

        return min(max(target, minHeight), maxHeight)
    }

    private func applyOpenDefaults() {
        selectLatestEntry()
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func selectLatestEntry() {
        selectedID = flattenedEntries.first?.id
    }

    private func refreshSelection() {
        let currentIDs = Set(flattenedEntries.map(\.id))
        if let selectedID, currentIDs.contains(selectedID) {
            return
        }
        selectedID = flattenedEntries.first?.id
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
        case Int(kVK_Escape):
            onClose()
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        let ids = groupedEntries.flatMap(\.items).map(\.id)
        guard !ids.isEmpty else { return }

        guard let selectedID, let idx = ids.firstIndex(of: selectedID) else {
            self.selectedID = ids.first
            return
        }

        let newIndex = min(max(idx + delta, 0), ids.count - 1)
        self.selectedID = ids[newIndex]
    }

    @ViewBuilder
    private func metadataSection(for entry: ClipboardEntry) -> some View {
        let contentForStats = entry.kind == .image ? entry.ocrText : entry.content
        let rows = metadataRows(for: entry, contentForStats: contentForStats)

        VStack(alignment: .leading, spacing: 0) {
            Text("Information")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 8) {
                    Text(row.title)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.value)
                        .multilineTextAlignment(.trailing)
                }
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .padding(.vertical, 6)

                if index < rows.count - 1 {
                    Divider().overlay(.white.opacity(0.06))
                }
            }
        }
    }

    private func metadataRows(for entry: ClipboardEntry, contentForStats: String) -> [(title: String, value: String)] {
        let chars = contentForStats.count
        let words = contentForStats
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count

        if entry.kind == .image,
           let imagePath = entry.imagePath,
           let image = NSImage(contentsOfFile: imagePath) {
            let size = image.size
            return [
                ("Source", entry.sourceApp ?? "Unknown"),
                ("Content type", entry.kind.rawValue),
                ("Dimensions", "\(Int(size.width)) × \(Int(size.height))"),
                ("Copied", entry.date.formatted(date: .abbreviated, time: .shortened))
            ]
        }

        return [
            ("Source", entry.sourceApp ?? "Unknown"),
            ("Content type", entry.kind.rawValue),
            ("Characters", "\(chars)"),
            ("Words", "\(words)"),
            ("Copied", entry.date.formatted(date: .abbreviated, time: .shortened))
        ]
    }

    private func font(for kind: ClipboardEntry.Kind) -> Font {
        switch kind {
        case .code, .path:
            return .system(size: 14, weight: .regular, design: .monospaced)
        default:
            return .system(size: 14, weight: .regular, design: .rounded)
        }
    }
}

private struct EntryRow: View {
    let entry: ClipboardEntry
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
           let imagePath = entry.imagePath,
           let image = NSImage(contentsOfFile: imagePath) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.06))

                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
        } else {
            Image(systemName: entry.kind.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.leading, 7)
        }
    }
}

private struct EntryGroup: Identifiable {
    var id: String { title }
    let title: String
    let items: [ClipboardEntry]
}
