import AppKit
import SwiftUI
import MacCleanKit

struct PrivacyView: View {
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
    @State private var timeFilter: PrivacyModule.TimeFilter = .allTime

    var body: some View {
        ModuleContainerView(
            title: L10n.tr("隐私清理", "Privacy", "Конфиденциальность"),
            subtitle: L10n.tr("清理浏览器数据、历史记录、Cookie 和系统痕迹", "Clean browser data, history, cookies, and system traces", "Удаление данных браузеров, истории, файлов cookie и системных следов"),
            theme: .protection,
            emptyMessage: L10n.tr("未发现隐私痕迹", "No privacy traces found", "Следы активности не найдены"),
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
            onReset: reset
        )
        // Browsers keep their history files open; offer to quit them (UI_SPEC §5.7).
        .overlay(alignment: .top) {
            if !results.isEmpty && !isScanning && cleaning == nil && completion == nil {
                RunningBrowsersBar().padding(.horizontal, 8).padding(.top, 4)
            }
        }
        .onAppear {
            if let e = appState.scanResultsStore.entry(for: .privacy) {
                results = e.results
                selectedItems = e.selection
                scanComplete = e.scanComplete
            }
        }
        .onDisappear {
            appState.scanResultsStore.save(
                results: results,
                selection: selectedItems,
                scanComplete: scanComplete,
                for: .privacy
            )
        }
    }

    private func scan() {
        isScanning = true
        scanComplete = false
        scanProgress = 0
        results = []
        selectedItems = []
        Task {
            let scanStart = Date()

            scanPhase = L10n.tr("正在扫描 Safari 数据...", "Scanning Safari data...", "Сканирование данных Safari...")
            scanProgress = 0.15
            try? await Task.sleep(for: .milliseconds(400))

            scanPhase = L10n.tr("正在扫描 Chrome 数据...", "Scanning Chrome data...", "Сканирование данных Chrome...")
            scanProgress = 0.35

            let module = PrivacyModule(timeFilter: timeFilter)
            async let scanTask = module.scan()

            try? await Task.sleep(for: .milliseconds(400))
            scanPhase = L10n.tr("正在扫描 Firefox 数据...", "Scanning Firefox data...", "Сканирование данных Firefox...")
            scanProgress = 0.55

            try? await Task.sleep(for: .milliseconds(400))
            scanPhase = L10n.tr("正在检查系统痕迹...", "Checking system traces...", "Проверка системных следов...")
            scanProgress = 0.75

            results = await scanTask

            scanPhase = L10n.tr("正在分析结果...", "Analyzing results...", "Анализ результатов...")
            scanProgress = 0.9

            let elapsed = Date().timeIntervalSince(scanStart)
            if elapsed < 2.0 {
                try? await Task.sleep(for: .milliseconds(Int((2.0 - elapsed) * 1000)))
            }
            scanProgress = 1.0

            for r in results { selectedItems.formUnion(r.items.map(\.url)) }
            isScanning = false
            scanComplete = true
        }
    }

    private func clean() {
        let preCleanSelectedCount = selectedItems.count
        cleaning = CleaningEngine.Progress(
            totalItems: preCleanSelectedCount,
            processedItems: 0, removedSoFar: 0, freedBytesSoFar: 0
        )
        cleanTask = Task {
            let result = await CleanActions.executeUserClean(
                results: results,
                selectedItems: selectedItems,
                engine: appState.cleaningEngine,
                onProgress: { progress in
                    Task { @MainActor in cleaning = progress }
                }
            )
            cleaning = nil
            completion = CleanSummary(
                selectedCount: preCleanSelectedCount,
                removedCount: result.removedCount,
                freedBytes: result.freedBytes,
                errorMessages: result.errors.map(\.error)
            )
        }
    }

    private func reset() {
        results = []; selectedItems = []; completion = nil; cleaning = nil; cleanTask = nil; scanComplete = false
    }
}

/// A slim bar listing browsers that are open, each with a "Quit" pill.
private struct RunningBrowsersBar: View {
    @State private var running: [NSRunningApplication] = []

    private static let browserIDs: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser",
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    var body: some View {
        Group {
            if !running.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(hex: 0xF8C04E))
                    Text("Quit open browsers so their data can be cleared.")
                        .font(.system(size: 12))
                    Spacer(minLength: 8)
                    ForEach(running, id: \.processIdentifier) { app in
                        HStack(spacing: 6) {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            }
                            Text(app.localizedName ?? "")
                                .font(.system(size: 12))
                            Button(L10n.tr("退出", "Quit", "Завершить")) { app.terminate() }
                                .buttonStyle(.ghostPill)
                        }
                    }
                }
                .foregroundStyle(TypeScale.primaryText)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refresh() }
    }

    private func refresh() {
        running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier.map(Self.browserIDs.contains) ?? false
        }
    }
}
