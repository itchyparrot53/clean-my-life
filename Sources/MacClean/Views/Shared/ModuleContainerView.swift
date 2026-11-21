import AppKit
import SwiftUI
import MacCleanKit

struct ModuleContainerView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    let title: String
    let subtitle: String
    let theme: ModuleTheme
    let emptyMessage: String
    let results: [ScanResult]
    @Binding var selectedItems: Set<URL>
    let isScanning: Bool
    let scanProgress: Double
    let scanPhase: String
    let scanComplete: Bool
    /// `nil` until clean has run. When set, the doneView renders one of
    /// three honest end-states (nothing selected / everything errored /
    /// happy path) instead of an ambiguous "0 bytes cleaned up".
    let completion: CleanSummary?
    /// Non-nil while a clean is in flight. The container renders a
    /// progress ring + cancel button instead of the results list during
    /// this window. nil means "no clean in flight" — either before any
    /// clean or after one finishes (then `completion` takes over).
    let cleaning: CleaningEngine.Progress?
    /// True when the scan came back empty because a target couldn't be read
    /// (Full Disk Access not granted) rather than because there was nothing
    /// to clean. Drives the "Grant Full Disk Access" empty-state instead of
    /// the misleading "nothing to clean up" one.
    let permissionDenied: Bool
    let onScan: () -> Void
    let onClean: () -> Void
    let onCancelClean: (() -> Void)?
    let onReset: () -> Void
    /// Opens System Settings → Full Disk Access. Required when
    /// `permissionDenied` can be true; the empty-state button calls it.
    let onGrantAccess: (() -> Void)?
    /// When true, the Clean button ALWAYS shows an irreversible
    /// "Empty the Trash?" confirmation, regardless of selection size.
    /// Used only by the Trash Bins module, whose Clean permanently
    /// deletes (it empties ~/.Trash) rather than moving items to the Trash.
    let confirmEmptyTrash: Bool
    /// Optional replacement for the default flat `FileListView` in the results
    /// screen. When provided, the container keeps all of its chrome (selection
    /// header, Clean button + confirmations, cleaning/progress/done states) but
    /// renders this view for the item list instead. The Duplicates module uses
    /// it to show a grouped, keep-the-original layout while reusing everything
    /// else. The closure should read/write the same `selectedItems` binding.
    let resultsContent: (() -> AnyView)?
    /// Overrides the primary action button's label (default "Clean"). The
    /// Duplicates module sets "Consolidate" when in consolidate mode so the
    /// button reflects that it clones rather than deletes.
    let actionLabel: String?
    /// Optional control under the intro bullets ("Configure…", disk picker).
    let introControl: AnyView?
    /// "Last scan …" line on the intro.
    let lastScan: String?
    /// Hero animation while scanning (A9 sweep, or A16 radar for Malware).
    let scanningMotion: TemplateHero.Motion
    /// Verdict-type results (UI_SPEC §4.3 B) instead of the size summary.
    let verdict: [VerdictTemplate.Metric]?
    let verdictCaption: String?
    /// `resultsContent` replaces both review columns.
    let resultsFullWidth: Bool

    init(
        title: String,
        subtitle: String,
        theme: ModuleTheme,
        emptyMessage: String = L10n.tr("未找到项目", "No items found", "Ничего не найдено"),
        results: [ScanResult],
        selectedItems: Binding<Set<URL>>,
        isScanning: Bool,
        scanProgress: Double = 0.5,
        scanPhase: String = L10n.tr("正在扫描...", "Scanning...", "Сканирование..."),
        scanComplete: Bool = false,
        completion: CleanSummary? = nil,
        cleaning: CleaningEngine.Progress? = nil,
        permissionDenied: Bool = false,
        onScan: @escaping () -> Void,
        onClean: @escaping () -> Void,
        onCancelClean: (() -> Void)? = nil,
        onReset: @escaping () -> Void,
        onGrantAccess: (() -> Void)? = nil,
        confirmEmptyTrash: Bool = false,
        resultsContent: (() -> AnyView)? = nil,
        actionLabel: String? = nil,
        introControl: AnyView? = nil,
        lastScan: String? = nil,
        scanningMotion: TemplateHero.Motion = .scanning,
        verdict: [VerdictTemplate.Metric]? = nil,
        verdictCaption: String? = nil,
        resultsFullWidth: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.emptyMessage = emptyMessage
        self.results = results
        self._selectedItems = selectedItems
        self.isScanning = isScanning
        self.scanProgress = scanProgress
        self.scanPhase = scanPhase
        self.scanComplete = scanComplete
        self.completion = completion
        self.cleaning = cleaning
        self.permissionDenied = permissionDenied
        self.onScan = onScan
        self.onClean = onClean
        self.onCancelClean = onCancelClean
        self.onReset = onReset
        self.onGrantAccess = onGrantAccess
        self.confirmEmptyTrash = confirmEmptyTrash
        self.resultsContent = resultsContent
        self.actionLabel = actionLabel
        self.introControl = introControl
        self.lastScan = lastScan
        self.scanningMotion = scanningMotion
        self.verdict = verdict
        self.verdictCaption = verdictCaption
        self.resultsFullWidth = resultsFullWidth
    }

    @State private var showLargeSelectionConfirm = false
    @State private var showEmptyTrashConfirm = false
    @State private var showActivityLog = false

    private var totalSelected: UInt64 {
        // Dedupe by URL: a file can appear in two categories (large + old)
        // and Clean trashes it once, so summing per-item would over-report
        // versus what actually gets freed.
        results.selectedSize(selectedItems)
    }

    private var selectedCount: Int {
        selectedItems.count
    }

    private var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSelected), countStyle: .file)
    }

    /// Status button state (UI_SPEC §1.3).
    private var moduleStage: ModuleStage {
        if completion != nil { return .results }
        if cleaning != nil || isScanning { return .working }
        if !results.isEmpty { return .results }
        if scanComplete && permissionDenied { return .attention }
        return .idle
    }

    /// Found size on the sidebar row while results are showing (UI_SPEC §3.2).
    private var sidebarBadge: SidebarBadge? {
        guard completion == nil, cleaning == nil, !isScanning, !results.isEmpty else { return nil }
        let total = results.reduce(UInt64(0)) { $0 + $1.totalSize }
        return total > 0 ? .size(total) : nil
    }

    @Environment(\.currentModule) private var module
    @Namespace private var morph
    @State private var showReview = false
    @State private var showConfirm = false
    @State private var runningApps: [NSRunningApplication] = []
    @Environment(\.toasts) private var toasts

    private var intro: ModuleIntro { (module ?? .systemJunk).intro }
    private var palette: ModulePalette { module?.palette ?? theme.palette }

    /// Which template is showing; drives the A11 morph.
    private var stateKey: String {
        if completion != nil { return "done" }
        if cleaning != nil { return "cleaning" }
        if isScanning { return "scanning" }
        if !results.isEmpty { return showReview ? "review" : "results" }
        if scanComplete { return permissionDenied ? "permission" : "empty" }
        return "intro"
    }

    var body: some View {
        ZStack {
            content
                .id(stateKey)
                .transition(TemplateMotion.stateTransition)
        }
        .animation(TemplateMotion.morph, value: stateKey)
        .environment(\.templateNamespace, morph)
        .cardDialog(isPresented: $showConfirm) {
            ConfirmCleanDialog(results: results, selection: selectedItems, runningApps: runningApps,
                               onCancel: { showConfirm = false },
                               onConfirm: { showConfirm = false; onClean() })
        }
        .onChange(of: completion?.freedBytes) { _, freed in
            // A26: offer Undo after anything went to the Trash (not Empty Trash).
            guard let completion, completion.removedCount > 0, !confirmEmptyTrash, let freed else { return }
            toasts?.movedToTrash(FileSizeFormatter.format(freed))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .moduleStage(moduleStage)
        .sidebarBadge(sidebarBadge)
        .topBarTitle(showReview && !results.isEmpty ? title : nil)
        .onChange(of: results.isEmpty) { _, empty in if empty { showReview = false } }
        // Trash Bins empties ~/.Trash permanently — there is no recovery,
        // so this confirmation fires on every Empty regardless of count.
        .alert(
            L10n.tr("清空废纸篓？", "Empty the Trash?", "Очистить Корзину?"),
            isPresented: $showEmptyTrashConfirm
        ) {
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) { }
            Button(L10n.tr("清空废纸篓", "Empty Trash", "Очистить Корзину"), role: .destructive) { onClean() }
        } message: {
            Text(L10n.tr("这会永久删除 \(selectedCount.formatted()) 项（\(formattedSelectedSize)），且无法撤销。", "This permanently deletes \(selectedCount.formatted()) item\(selectedCount == 1 ? "" : "s") (\(formattedSelectedSize)) and cannot be undone.", "Безвозвратное удаление: \(selectedCount.formatted()) \(L10n.russianPlural(selectedCount, one: "объект", few: "объекта", many: "объектов")) (\(formattedSelectedSize)). Отменить это действие нельзя."))
        }
        .sheet(isPresented: $showActivityLog) { LogViewerView() }
        .respondsToModuleShortcuts(
            onScan: onScan,
            onClean: requestClean,
            canScan: cleaning == nil && !isScanning && completion == nil,
            canClean: cleaning == nil && completion == nil && !results.isEmpty && selectedCount > 0
        )
    }

    @ViewBuilder
    private var content: some View {
        if let completion {
            doneView(summary: completion)
        } else if let cleaning {
            ScanningTemplate(
                title: L10n.tr("正在清理…", "Cleaning…", "Очистка…"),
                intro: intro, palette: palette,
                path: cleaning.totalItems > 0
                    ? L10n.tr("已处理 \(cleaning.processedItems.formatted()) / \(cleaning.totalItems.formatted()) 项", "\(cleaning.processedItems.formatted()) of \(cleaning.totalItems.formatted()) items", "Обработано \(cleaning.processedItems.formatted()) из \(cleaning.totalItems.formatted())")
                    : L10n.tr("正在开始清理...", "Starting cleanup...", "Подготовка к очистке..."),
                progress: cleaning.fraction,
                onStop: onCancelClean)
        } else if isScanning {
            ScanningTemplate(intro: intro, palette: palette, path: scanPhase, progress: scanProgress,
                             heroMotion: scanningMotion)
        } else if !results.isEmpty {
            if showReview {
                ReviewTemplate(
                    results: results, selectedItems: $selectedItems, palette: palette,
                    customContent: resultsContent,
                    customFullWidth: resultsFullWidth,
                    actionLabel: actionLabel ?? L10n.tr("清理", "Clean", "Очистить"),
                    onBack: { showReview = false },
                    onAct: requestClean)
            } else if let verdict {
                VerdictTemplate(
                    intro: intro, palette: palette, metrics: verdict,
                    reviewCaption: verdictCaption,
                    actionLabel: actionLabel ?? L10n.tr("移除", "Remove", "Удалить"),
                    primaryMeta: selectedCount > 0 ? formattedSelectedSize : nil,
                    canAct: selectedCount > 0,
                    onReview: { showReview = true },
                    onAct: requestClean)
            } else {
                ResultsTemplate(
                    intro: intro, palette: palette, selectedBytes: totalSelected,
                    actionLabel: actionLabel ?? L10n.tr("清理", "Clean", "Очистить"),
                    canAct: selectedCount > 0,
                    onReview: { showReview = true },
                    onAct: requestClean)
            }
        } else if scanComplete {
            if permissionDenied {
                PermissionCard(palette: palette, onOpenSettings: onGrantAccess, onRescan: onScan, onDone: onReset)
            } else {
                EmptyTemplate(title: emptyMessage, intro: intro, palette: palette, onDone: onReset)
            }
        } else {
            if let introControl {
                IntroTemplate(title: title, intro: intro, palette: palette, lastScan: lastScan,
                              control: { introControl }, onPrimary: onScan)
            } else {
                IntroTemplate(title: title, intro: intro, palette: palette, lastScan: lastScan, onPrimary: onScan)
            }
        }
    }

    /// Clean, with Clean My Life's confirmations: Trash Bins always asks (it's
    /// permanent); big selections ask too.
    private func requestClean() {
        guard selectedCount > 0 else { return }
        if confirmEmptyTrash {
            showEmptyTrashConfirm = true
            return
        }
        // §8: totals per category, plus any open apps that own the files.
        let snapshot = results, selection = selectedItems
        // Open at once; the open-apps check can take a while on big scans.
        runningApps = []
        let ask = CleanConfirmation.isNeeded(results: snapshot, selection: selection)
        if ask { showConfirm = true }
        Task { @MainActor in
            let owners = await CleanConfirmation.runningOwners(results: snapshot, selection: selection)
            if ask { runningApps = owners }
            else if owners.isEmpty { onClean() }
            else { runningApps = owners; showConfirm = true }
        }
    }

    /// Three honest end-states: nothing selected, nothing removed, or the
    /// normal "N GB cleaned up". Each says what happened.
    @ViewBuilder
    private func doneView(summary: CleanSummary) -> some View {
        if summary.selectedCount == 0 {
            DoneTemplate(
                title: L10n.tr("未选择任何项目", "Nothing was selected", "Ничего не выбрано"),
                subtitle: L10n.tr("请重新扫描，勾选要移除的项目，然后点击“清理”。", "Re-run the scan, check the items you want to remove, then click Clean.", "Повторите сканирование, отметьте объекты для удаления и нажмите «Очистить»."),
                palette: palette, isWarning: true, onDone: onReset)
        } else if summary.removedCount == 0 {
            DoneTemplate(
                title: L10n.tr("\(summary.selectedCount) 项无法清理", "\(summary.selectedCount) item\(summary.selectedCount == 1 ? "" : "s") couldn't be cleaned", "Не удалось очистить \(summary.selectedCount) \(L10n.russianPlural(summary.selectedCount, one: "объект", few: "объекта", many: "объектов"))"),
                palette: palette, isWarning: true,
                extra: {
                    VStack(alignment: .leading, spacing: 10) {
                        cleanErrorDetail(for: summary)
                        viewLogButton
                    }
                },
                onDone: onReset)
        } else {
            DoneTemplate(
                title: L10n.tr("已清理 \(FileSizeFormatter.format(summary.freedBytes))", "\(FileSizeFormatter.format(summary.freedBytes)) cleaned up", "Очищено \(FileSizeFormatter.format(summary.freedBytes))"),
                subtitle: summary.removedCount < summary.selectedCount
                    ? L10n.tr("已移除 \(summary.removedCount) / \(summary.selectedCount) 项", "\(summary.removedCount) of \(summary.selectedCount) items removed", "Выбрано \(summary.selectedCount) \(L10n.russianPlural(summary.selectedCount, one: "объект", few: "объекта", many: "объектов")), удалено \(summary.removedCount)")
                        + (summary.errorCount > 0 ? L10n.tr(" — \(summary.errorCount) 个错误", " — \(summary.errorCount) error\(summary.errorCount == 1 ? "" : "s")", " — \(summary.errorCount) \(L10n.russianPlural(summary.errorCount, one: "ошибка", few: "ошибки", many: "ошибок"))") : "")
                    : L10n.tr("可在清理历史中撤销。", "Moved to the Trash. You can put things back from Activity.", "Перемещено в Корзину. Вернуть можно в разделе «Активность»."),
                palette: palette,
                extra: {
                    if summary.errorCount > 0 { viewLogButton }
                },
                onDone: onReset)
        }
    }

    private var viewLogButton: some View {
        Button {
            showActivityLog = true
        } label: {
            Label(L10n.tr("查看日志", "View Log", "Открыть журнал"), systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.ghostPill)
        .help(L10n.tr("打开活动日志，查看每个错误并复制详情用于反馈问题", "Open the activity log to see every error and copy details for a bug report", "Открыть журнал операций, просмотреть каждую ошибку и скопировать сведения для отчёта"))
    }

    /// Renders the error summary on the post-clean screen. Single error
    /// gets the full message; multi-error shows the top-3 groups
    /// ("X items: <message>") sorted by count, so the user immediately
    /// sees what kind of failure dominated rather than a flat count
    /// pointing them at Console.app.
    @ViewBuilder
    private func cleanErrorDetail(for summary: CleanSummary) -> some View {
        if summary.errorCount == 1, let msg = summary.firstErrorMessage {
            Text(msg)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.leading)
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
                if summary.errorCount > summary.topErrorGroups.reduce(0, { $0 + $1.count }) {
                    let shownTotal = summary.topErrorGroups.reduce(0) { $0 + $1.count }
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

}
