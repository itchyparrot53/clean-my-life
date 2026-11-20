import AppKit
import SwiftUI
import MacCleanKit

/// Screenshots tool: every screenshot and screen recording, grouped by age,
/// as a thumbnail grid. Remove sends them to the Trash (with Undo); "Move to
/// Pictures" files them into ~/Pictures/Screenshots by month instead.
struct ScreenshotsView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [ScanResult] = []
    @State private var groups: [ScreenshotsScanner.Group] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanComplete = false
    @State private var completion: CleanSummary?
    @State private var cleaning: CleaningEngine.Progress?
    @State private var cleanTask: Task<Void, Never>?

    var body: some View {
        ModuleContainerView(
            title: SidebarItem.screenshots.title,
            subtitle: "",
            theme: .files,
            emptyMessage: "No screenshots found",
            results: results,
            selectedItems: $selectedItems,
            isScanning: isScanning,
            scanProgress: scanProgress,
            scanPhase: "Asking Spotlight for your screenshots…",
            scanComplete: scanComplete,
            completion: completion,
            cleaning: cleaning,
            onScan: scan,
            onClean: clean,
            onCancelClean: { cleanTask?.cancel() },
            onReset: reset,
            resultsContent: {
                AnyView(ScreenshotsReview(groups: groups, selectedItems: $selectedItems, onArchive: archive))
            },
            actionLabel: L10n.tr("移除", "Remove", "Удалить"),
            resultsFullWidth: true)
    }

    private func scan() {
        isScanning = true
        scanComplete = false
        scanProgress = 0.4
        results = []
        selectedItems = []
        Task {
            let found = await Task.detached(priority: .userInitiated) { ScreenshotsScanner().scan() }.value
            apply(found)
            scanProgress = 1
            isScanning = false
            scanComplete = true
        }
    }

    private func apply(_ found: (result: ScanResult?, groups: [ScreenshotsScanner.Group])) {
        results = found.result.map { [$0] }?.filteringUncleanable() ?? []
        let allowed = Set(results.flatMap { $0.items.map(\.url) })
        groups = found.groups.map { group in
            .init(id: group.id, title: group.title, symbol: group.symbol, items: group.items.filter { allowed.contains($0.url) })
        }.filter { !$0.items.isEmpty }
        selectedItems.formIntersection(allowed)
    }

    private func clean() {
        let count = selectedItems.count
        cleaning = CleaningEngine.Progress(totalItems: count, processedItems: 0, removedSoFar: 0, freedBytesSoFar: 0)
        cleanTask = Task {
            let result = await CleanActions.executeUserClean(
                results: results, selectedItems: selectedItems, engine: appState.cleaningEngine,
                onProgress: { progress in Task { @MainActor in cleaning = progress } })
            cleaning = nil
            completion = CleanSummary(selectedCount: count, removedCount: result.removedCount,
                                      freedBytes: result.freedBytes, errorMessages: result.errors.map(\.error))
        }
    }

    /// Move the selection into ~/Pictures/Screenshots, then rescan in place.
    private func archive() {
        let archive = ScreenshotsScanner.archiveFolder.path(percentEncoded: false)
        let urls = selectedItems.filter { !$0.path(percentEncoded: false).hasPrefix(archive + "/") }
        guard !urls.isEmpty else { return }
        Task {
            _ = await Task.detached { ScreenshotsScanner.archive(Array(urls)) }.value
            let found = await Task.detached { ScreenshotsScanner().scan() }.value
            selectedItems = []
            apply(found)
            NSWorkspace.shared.activateFileViewerSelecting([ScreenshotsScanner.archiveFolder])
        }
    }

    private func reset() {
        results = []; groups = []; selectedItems = []; completion = nil; cleaning = nil; cleanTask = nil; scanComplete = false
    }
}

struct ScreenshotsReview: View {
    let groups: [ScreenshotsScanner.Group]
    @Binding var selectedItems: Set<URL>
    let onArchive: () -> Void
    @State private var focused = "all"

    private var current: ScreenshotsScanner.Group? { groups.first { $0.id == focused } ?? groups.first }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary).font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in groupRow(group) }
                    }
                }
            }
            .frame(width: 250)

            if let current {
                grid(current).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .foregroundStyle(TypeScale.primaryText)
    }

    private var summary: String {
        let all = groups.first { $0.id == "all" }?.items ?? []
        return "\(all.count) captures · \(FileSizeFormatter.format(all.reduce(0) { $0 + $1.size }))"
    }

    private func groupRow(_ group: ScreenshotsScanner.Group) -> some View {
        let urls = group.items.map(\.url)
        let selected = urls.filter(selectedItems.contains).count
        let state: CheckState = selected == 0 ? .off : (selected == urls.count ? .on : .mixed)
        return HStack(spacing: 10) {
            TriStateCheckbox(state: state) {
                if state == .on { selectedItems.subtract(urls) } else { selectedItems.formUnion(urls) }
            }
            Image(systemName: group.symbol).font(.system(size: 13)).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.title).font(TypeScale.row).lineLimit(1)
                Text("\(group.items.count)").font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
            }
            Spacer(minLength: 4)
            Text(FileSizeFormatter.format(group.items.reduce(0) { $0 + $1.size }))
                .font(TypeScale.rowSize)
                .foregroundStyle(.white.opacity(state == .off ? 0.45 : 0.8))
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: Surface.rowRadius, style: .continuous)
            .fill(group.id == current?.id ? Surface.rowSelection : .clear))
        .contentShape(Rectangle())
        .onTapGesture { focused = group.id }
    }

    private func grid(_ group: ScreenshotsScanner.Group) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.title).font(TypeScale.reviewTitle)
                Spacer()
                Button("Move to Pictures", action: onArchive)
                    .buttonStyle(.ghostPill)
                    .disabled(selectedItems.isEmpty)
                    .help("Move the selected captures into Pictures › Screenshots, one folder per month.")
                Menu {
                    Button("Older Than a Week") { selectOlder(than: 7, in: group) }
                    Button("Older Than a Month") { selectOlder(than: 30, in: group) }
                    Button("Older Than a Year") { selectOlder(than: 365, in: group) }
                    Button("Everything Here") { selectedItems.formUnion(group.items.map(\.url)) }
                    Divider()
                    Button("Deselect Everything") { selectedItems = [] }
                } label: {
                    HStack(spacing: 3) {
                        Text("Select")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(TypeScale.secondaryText)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            Text("Double-click to open in Quick Look.")
                .font(TypeScale.reviewDescription)
                .foregroundStyle(.white.opacity(0.7))
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 120), spacing: 12, alignment: .top)],
                          alignment: .leading, spacing: 14) {
                    ForEach(group.items, id: \.url) { item in cell(item) }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func cell(_ item: FileItem) -> some View {
        let isSelected = selectedItems.contains(item.url)
        let date = ScreenshotsScanner.date(item)
        return PhotoCell(
            url: item.url, caption: date.formatted(date: .abbreviated, time: .omitted) + " · " + item.formattedSize,
            isSelected: isSelected,
            onToggle: { if isSelected { selectedItems.remove(item.url) } else { selectedItems.insert(item.url) } },
            onOpen: { QuickLookPreview.show([item.url]) })
            .overlay(alignment: .center) {
                if ScreenshotsScanner.videoExtensions.contains(item.fileExtension) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 4)
                        .offset(y: -8)
                        .allowsHitTesting(false)
                }
            }
            .contextMenu {
                Button("Quick Look") { QuickLookPreview.show([item.url]) }
                Button(L10n.tr("在 Finder 中显示", "Reveal in Finder", "Показать в Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
            }
    }

    private func selectOlder(than days: Double, in group: ScreenshotsScanner.Group) {
        let cutoff = Date().addingTimeInterval(-days * 24 * 3600)
        selectedItems.formUnion(group.items.filter { ScreenshotsScanner.date($0) < cutoff }.map(\.url))
    }
}
