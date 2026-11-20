import SwiftUI
import MacCleanKit

/// AI Clutter (UI_SPEC §5.3) on the shared templates.
struct AIClutterView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [ScanResult] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanPhase = ""
    @State private var scanComplete = false
    @State private var completion: CleanSummary?
    @State private var cleaning: CleaningEngine.Progress?
    @State private var cleanTask: Task<Void, Never>?

    var body: some View {
        ModuleContainerView(
            title: L10n.tr("AI 杂物", "AI Clutter", "AI-мусор"),
            subtitle: "",
            theme: .cleanup,
            emptyMessage: "No AI clutter found",
            results: results,
            selectedItems: $selectedItems,
            isScanning: isScanning,
            scanProgress: scanProgress,
            scanPhase: scanPhase,
            scanComplete: scanComplete,
            completion: completion,
            cleaning: cleaning,
            onScan: scan,
            onClean: clean,
            onCancelClean: { cleanTask?.cancel() },
            onReset: reset)
    }

    private func scan() {
        isScanning = true
        scanComplete = false
        results = []
        selectedItems = []
        Task {
            scanPhase = "Looking at AI app caches…"
            scanProgress = 0.3
            let found = await Task.detached { await AIClutterScanner().scan() }.value
            scanPhase = "Measuring local models…"
            scanProgress = 0.9
            results = found
            selectedItems = Set(found.filter(\.autoSelect).flatMap { $0.items.map(\.url) })
            scanProgress = 1
            isScanning = false
            scanComplete = true
        }
    }

    private func clean() {
        let count = selectedItems.count
        let removedOllama = selectedItems.contains { $0.path(percentEncoded: false).contains("/.ollama/models/manifests/") }
        cleaning = CleaningEngine.Progress(totalItems: count, processedItems: 0, removedSoFar: 0, freedBytesSoFar: 0)
        cleanTask = Task {
            var result = await CleanActions.executeUserClean(
                results: results, selectedItems: selectedItems, engine: appState.cleaningEngine,
                onProgress: { progress in Task { @MainActor in cleaning = progress } })
            var freed = result.freedBytes
            var removed = result.removedCount
            // Removing an Ollama model's manifest leaves its weights behind;
            // move the blobs no remaining model uses to the Trash too.
            if removedOllama {
                let orphans = AIClutterScanner.orphanedOllamaBlobs().map {
                    FileItem(url: $0, name: $0.lastPathComponent, size: AIClutterScanner.allocated($0),
                             allocatedSize: AIClutterScanner.allocated($0), isDirectory: false)
                }
                if !orphans.isEmpty {
                    let extra = await CleanActions.executeUserClean(
                        items: orphans, selectedItems: Set(orphans.map(\.url)), engine: appState.cleaningEngine)
                    freed += extra.freedBytes
                    removed += extra.removedCount
                    result = CleaningEngine.CleanResult(removedCount: removed, freedBytes: freed,
                                                        removedURLs: result.removedURLs.union(extra.removedURLs),
                                                        errors: result.errors + extra.errors, skippedCount: result.skippedCount)
                }
            }
            cleaning = nil
            completion = CleanSummary(selectedCount: count, removedCount: removed, freedBytes: freed,
                                      errorMessages: result.errors.map(\.error))
        }
    }

    private func reset() {
        results = []; selectedItems = []; completion = nil; cleaning = nil; cleanTask = nil; scanComplete = false
    }
}
