import AppKit
import SwiftUI
import MacCleanKit

struct SystemJunkView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.moduleIsSelected) private var moduleIsSelected
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var viewModel = SystemJunkViewModel()
    @State private var showLargeSelectionConfirm = false
    @State private var showActivityLog = false

    private func sidebarSize(_ results: [ScanResult]) -> SidebarBadge? {
        let total = results.reduce(UInt64(0)) { $0 + $1.totalSize }
        return total > 0 ? .size(total) : nil
    }

    /// Status button state (UI_SPEC §1.3).
    private var moduleStage: ModuleStage {
        switch viewModel.state {
        case .idle, .empty: .idle
        case .scanning, .cleaning: .working
        case .results, .done:
            viewModel.isScanComplete && !viewModel.permissionDeniedPaths.isEmpty ? .attention : .results
        }
    }

    @State private var showReview = false
    @State private var runningApps: [NSRunningApplication] = []
    @Environment(\.toasts) private var toasts
    @Namespace private var morph

    private var stateKey: String {
        switch viewModel.state {
        case .idle: "idle"
        case .scanning: "scanning"
        case .results: showReview ? "review" : "results"
        case .empty: "empty"
        case .cleaning: "cleaning"
        case .done: "done"
        }
    }

    var body: some View {
        ZStack {
            Group {
                switch viewModel.state {
                case .idle: idleView
                case .scanning(let progress): scanningView(progress: progress)
                case .results: resultsView
                case .empty: emptyView
                case .cleaning(let progress): cleaningView(progress: progress)
                case .done(let summary): doneView(summary: summary)
                }
            }
            .id(stateKey)
            .transition(TemplateMotion.stateTransition)
        }
        .animation(TemplateMotion.morph, value: stateKey)
        .environment(\.templateNamespace, morph)
        .overlay(alignment: .top) {
            if viewModel.isScanComplete && !viewModel.permissionDeniedPaths.isEmpty {
                permissionWarning.padding(.top, 4)
            }
        }
        .topBarTitle(showReview && viewModel.state.isResults ? L10n.tr("系统垃圾", "System Junk", "Системный мусор") : nil)
        .onChange(of: viewModel.state.isResults) { _, isResults in if !isResults { showReview = false } }
        .cardDialog(isPresented: $showLargeSelectionConfirm) {
            ConfirmCleanDialog(results: viewModel.results, selection: viewModel.selectedItems, runningApps: runningApps,
                               total: viewModel.totalSelectedSize,
                               onCancel: { showLargeSelectionConfirm = false },
                               onConfirm: {
                                   showLargeSelectionConfirm = false
                                   viewModel.startCleaning(engine: appState.cleaningEngine)
                               })
        }
        .onChange(of: viewModel.state.doneFreed) { _, freed in
            if let freed, freed > 0 { toasts?.movedToTrash(FileSizeFormatter.format(freed)) }
        }
        .sheet(isPresented: $showActivityLog) { LogViewerView() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .topBarAccessory(id: "cleanupPermissions") { CleanupPermissionsButton() }
        .moduleStage(moduleStage)
        .sidebarBadge(viewModel.state.isResults ? sidebarSize(viewModel.results) : nil)
        .onAppear {
            if let e = appState.scanResultsStore.entry(for: .systemJunk) {
                viewModel.restore(results: e.results, selection: e.selection, scanComplete: e.scanComplete, permissionDeniedPaths: e.permissionDeniedPaths)
            }
        }
        .onDisappear {
            appState.scanResultsStore.save(
                results: viewModel.results,
                selection: viewModel.selectedItems,
                scanComplete: viewModel.isScanComplete,
                for: .systemJunk,
                permissionDeniedPaths: viewModel.permissionDeniedPaths
            )
        }
        .respondsToModuleShortcuts(
            onScan: { viewModel.startScan() },
            onClean: { requestCleanup() },
            canScan: {
                switch viewModel.state {
                case .idle, .empty, .done, .results: true
                case .scanning, .cleaning: false
                }
            }(),
            canClean: {
                if case .results = viewModel.state { return viewModel.selectedCount > 0 }
                return false
            }()
        )
    }

    /// Some folders couldn't be read (UI_SPEC §8 banner).
    private var permissionWarning: some View {
        ErrorBanner(
            message: L10n.tr("扫描未完成：部分文件夹无法读取。", "Scan incomplete: some folders couldn't be read. Grant Full Disk Access, restart \(MCConstants.appName) and scan again.", "Сканирование неполное: некоторые папки недоступны. Предоставьте полный доступ к диску, перезапустите \(MCConstants.appName) и повторите сканирование."),
            actionLabel: L10n.tr("打开设置", "Open Settings", "Открыть настройки"),
            action: { PermissionManager.shared.openFullDiskAccessSettings() })
            .help(viewModel.permissionDeniedPaths.map { $0.path(percentEncoded: false) }.joined(separator: "\n"))
            .padding(.horizontal, 8)
    }

    private var idleView: some View {
        IntroTemplate(title: L10n.tr("系统垃圾", "System Junk", "Системный мусор"),
                      intro: SidebarItem.systemJunk.intro, palette: .cleanup,
                      onPrimary: { viewModel.startScan() })
    }

    private func scanningView(progress: Double) -> some View {
        ScanningTemplate(
            intro: SidebarItem.systemJunk.intro, palette: .cleanup,
            path: viewModel.scanPhase,
            found: L10n.tr("发现 \(viewModel.filesFound) 个文件", "\(viewModel.filesFound.formatted()) files found", "Найдено файлов: \(viewModel.filesFound)"),
            progress: progress)
    }

    @ViewBuilder
    private var resultsView: some View {
        if showReview {
            ReviewTemplate(
                results: viewModel.results, selectedItems: $viewModel.selectedItems, palette: .cleanup,
                onBack: { showReview = false }, onAct: requestCleanup)
        } else {
            ResultsTemplate(
                intro: SidebarItem.systemJunk.intro, palette: .cleanup,
                selectedBytes: viewModel.totalSelectedSize,
                canAct: viewModel.selectedCount > 0,
                onReview: { showReview = true }, onAct: requestCleanup)
        }
    }

    private func requestCleanup() {
        guard viewModel.selectedCount > 0 else { return }
        let results = viewModel.results, selection = viewModel.selectedItems
        // Clean My Life's review rule still always asks; ours adds the safe-item
        // opt-out. Open at once; the open-apps check fills in afterwards.
        runningApps = []
        let ask = CleanupSelectionPolicy.requiresReview(in: results, selection: selection)
            || CleanConfirmation.isNeeded(results: results, selection: selection)
        if ask { showLargeSelectionConfirm = true }
        Task { @MainActor in
            let owners = await CleanConfirmation.runningOwners(results: results, selection: selection)
            if ask { runningApps = owners }
            else if owners.isEmpty { viewModel.startCleaning(engine: appState.cleaningEngine) }
            else { runningApps = owners; showLargeSelectionConfirm = true }
        }
    }

    private var emptyView: some View {
        EmptyTemplate(title: L10n.tr("没有发现垃圾", "No junk found", "Мусор не найден"),
                      intro: SidebarItem.systemJunk.intro, palette: .cleanup,
                      onDone: { viewModel.reset() })
    }

    private func cleaningView(progress: CleaningEngine.Progress?) -> some View {
        ScanningTemplate(
            title: L10n.tr("正在清理…", "Cleaning…", "Очистка…"),
            intro: SidebarItem.systemJunk.intro, palette: .cleanup,
            path: progress.map { L10n.tr("已处理 \($0.processedItems.formatted()) / \($0.totalItems.formatted()) 项", "\($0.processedItems.formatted()) of \($0.totalItems.formatted()) items", "Обработано \($0.processedItems.formatted()) из \($0.totalItems.formatted())") },
            progress: progress?.fraction ?? 0,
            onStop: { viewModel.cancelCleaning() })
    }

    @ViewBuilder
    private func cleanErrorDetail(for summary: CleanSummary) -> some View {
        if summary.errorCount == 1, let msg = summary.firstErrorMessage {
            Text(msg)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .textSelection(.enabled)
        } else if !summary.topErrorGroups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(summary.topErrorGroups, id: \.message) { group in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(group.count.formatted())×")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.6))
                            .frame(minWidth: 50, alignment: .trailing)
                        Text(group.message)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.8))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                let shownTotal = summary.topErrorGroups.reduce(0) { $0 + $1.count }
                if summary.errorCount > shownTotal {
                    Text(L10n.tr("…以及另外 \((summary.errorCount - shownTotal).formatted()) 项", "…and \((summary.errorCount - shownTotal).formatted()) more", "…и ещё \((summary.errorCount - shownTotal).formatted()) \(L10n.russianPlural(summary.errorCount - shownTotal, one: "ошибка", few: "ошибки", many: "ошибок"))"))
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.5))
                        .padding(.top, 2)
                }
                Text(L10n.tr("完整日志：~/Library/Logs/MacClean/operations.log", "Full log: ~/Library/Logs/MacClean/operations.log", "Полный журнал: ~/Library/Logs/MacClean/operations.log"))
                    .font(.system(size: 11, design: .monospacedUnlessRightToLeft))
                    .foregroundStyle(.primary.opacity(0.45))
                    .padding(.top, 4)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)
        }
    }

    private func cleaningPhaseText(_ progress: CleaningEngine.Progress?) -> String {
        guard let progress, progress.totalItems > 0 else {
            return L10n.tr("正在开始清理...", "Starting cleanup...", "Подготовка к очистке...")
        }
        let pct = Int((progress.fraction * 100).rounded())
        return L10n.tr("正在清理… \(pct)%", "Cleaning… \(pct)%", "Очистка… \(pct)%")
    }

    /// Distinguishable end-states: stopped, nothing selected, nothing
    /// removed, or the normal "N GB cleaned up".
    @ViewBuilder
    private func doneView(summary: CleanSummary) -> some View {
        if summary.wasCancelled {
            DoneTemplate(
                title: L10n.tr("清理已停止", "Cleanup stopped", "Очистка остановлена"),
                subtitle: L10n.tr("已处理 \(FileSizeFormatter.format(summary.freedBytes))", "\(FileSizeFormatter.format(summary.freedBytes)) processed before stopping.", "Обработано \(FileSizeFormatter.format(summary.freedBytes))"),
                palette: .cleanup, isWarning: true,
                extra: { cleanErrorDetail(for: summary) },
                onDone: { viewModel.reset() })
        } else if summary.selectedCount == 0 {
            DoneTemplate(
                title: L10n.tr("未选择任何项目", "Nothing was selected", "Ничего не выбрано"),
                subtitle: L10n.tr("请勾选要移除的项目，然后点击“清理”。", "Check the items you want to remove, then click Clean.", "Отметьте объекты для удаления и нажмите «Очистить»."),
                palette: .cleanup, isWarning: true, onDone: { viewModel.reset() })
        } else if summary.removedCount == 0 {
            DoneTemplate(
                title: L10n.tr("\(summary.selectedCount) 项无法清理", "\(summary.selectedCount) item\(summary.selectedCount == 1 ? "" : "s") couldn't be cleaned", "Не удалось очистить \(summary.selectedCount)"),
                palette: .cleanup, isWarning: true,
                extra: {
                    VStack(alignment: .leading, spacing: 10) {
                        cleanErrorDetail(for: summary)
                        Button(L10n.tr("查看日志", "View Log", "Открыть журнал")) { showActivityLog = true }
                            .buttonStyle(.ghostPill)
                    }
                },
                onDone: { viewModel.reset() })
        } else {
            DoneTemplate(
                title: L10n.tr("已清理 \(FileSizeFormatter.format(summary.freedBytes))", "\(FileSizeFormatter.format(summary.freedBytes)) cleaned up", "Очищено \(FileSizeFormatter.format(summary.freedBytes))"),
                subtitle: summary.errorCount > 0
                    ? L10n.tr("已移除 \(summary.removedCount) / \(summary.selectedCount) 项", "\(summary.removedCount) of \(summary.selectedCount) items removed.", "Удалено \(summary.removedCount) из \(summary.selectedCount)")
                    : L10n.tr("已移到废纸篓。", "Moved to the Trash. You can put things back from Activity.", "Перемещено в Корзину. Вернуть можно в разделе «Активность»."),
                palette: .cleanup,
                extra: {
                    if summary.errorCount > 0 {
                        Button(L10n.tr("查看日志", "View Log", "Открыть журнал")) { showActivityLog = true }
                            .buttonStyle(.ghostPill)
                    }
                },
                onDone: { viewModel.reset() })
        }
    }
}
