import SwiftUI
import MacCleanKit

/// Downloads (UI_SPEC §5.18): grouped by source, plus installers and
/// duplicate downloads, on the shared templates.
struct DownloadsView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [ScanResult] = []
    @State private var groups: [DownloadsScanner.Group] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanComplete = false
    @State private var completion: CleanSummary?
    @State private var cleaning: CleaningEngine.Progress?
    @State private var cleanTask: Task<Void, Never>?

    var body: some View {
        ModuleContainerView(
            title: L10n.tr("下载项", "Downloads", "Загрузки"),
            subtitle: "",
            theme: .files,
            emptyMessage: "Your Downloads folder is empty",
            results: results,
            selectedItems: $selectedItems,
            isScanning: isScanning,
            scanProgress: scanProgress,
            scanPhase: "Reading your Downloads folder…",
            scanComplete: scanComplete,
            completion: completion,
            cleaning: cleaning,
            onScan: scan,
            onClean: clean,
            onCancelClean: { cleanTask?.cancel() },
            onReset: reset,
            resultsContent: {
                AnyView(GroupedFileReview(
                    results: results, selectedItems: $selectedItems,
                    fixedGroups: groups.map { .init(id: $0.id, title: $0.title, symbol: $0.symbol, items: $0.items) }))
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
            let found = await Task.detached { DownloadsScanner().scan() }.value
            groups = found.groups
            results = found.result.map { [$0] }?.filteringUncleanable() ?? []
            // Installers and exact duplicate downloads start ticked; the rest is yours to choose.
            selectedItems = Set(found.groups.filter { $0.id == "installers" || $0.id == "duplicates" }
                .flatMap { $0.items.map(\.url) })
            scanProgress = 1
            isScanning = false
            scanComplete = true
        }
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

    private func reset() {
        results = []; groups = []; selectedItems = []; completion = nil; cleaning = nil; cleanTask = nil; scanComplete = false
    }
}
