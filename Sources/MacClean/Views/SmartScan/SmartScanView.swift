import AppKit
import SwiftUI
import MacCleanKit

struct SmartScanView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.moduleIsSelected) private var moduleIsSelected
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var scanState: SmartScanState = .idle
    @State private var completedModules: [CompletedModule] = []
    @State private var currentModuleName: String = ""
    @State private var selectedItems: Set<URL> = []
    @State private var cleanResults: [ScanResult] = []
    @State private var askForSupport = false
    @State private var showCleanConfirm = false
    @State private var showActivityLog = false
    @State private var cleanTask: Task<Void, Never>?
    /// Watches `ScanCoordinator` while a Smart Scan runs. Cancelled by
    /// `cancelScan()` so we stop polling and return to idle promptly (#3).
    @State private var scanWatchTask: Task<Void, Never>?
    /// Cached selected-size total + a url -> size index backing it, so the
    /// footer reads an O(1) value instead of an O(all-items) sum on every body
    /// pass (the sidebar-switch beachball on large Smart Scans).
    @State private var selectedCleanSize: UInt64 = 0
    @State private var cleanSizeIndex: [URL: UInt64] = [:]
    @State private var showReviewSheet = false
    @State private var runningApps: [NSRunningApplication] = []
    @Environment(\.toasts) private var toasts

    private var doneFreed: UInt64? {
        if case .done(let summary, _) = scanState, summary.removedCount > 0, !summary.wasCancelled { return summary.freedBytes }
        return nil
    }

    /// §8: always confirm Checkup's run, listing open apps that own files.
    private func requestRun() {
        let results = cleanResults, selection = selectedItems
        runningApps = []
        showCleanConfirm = true
        Task { @MainActor in
            runningApps = await CleanConfirmation.runningOwners(results: results, selection: selection)
        }
    }
    @State private var reviewArea: Area?
    @Namespace private var morph

    struct CompletedModule: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let fileCount: Int
        let size: UInt64
    }

    enum SmartScanState {
        case idle
        case scanning(phase: String, progress: Double, filesFound: Int, sizeFound: UInt64)
        case results(cleanup: UInt64, protection: Int, performance: Int, totalSize: UInt64, moduleResults: [ModuleScanResult])
        case empty
        case cleaning(progress: Double)
        case done(summary: CleanSummary, breakdown: [SmartScanCleanup.RecentlyCleanedRow])
    }

    private static var moduleOrder: [(id: String, name: String, icon: String, group: String)] {
        [
            ("systemJunk", L10n.tr("系统垃圾", "System Junk", "Системный мусор"), "trash.circle.fill", L10n.tr("清理", "Cleanup", "Очистка")),
            ("mailAttachments", L10n.tr("邮件附件", "Mail Attachments", "Почтовые вложения"), "paperclip.circle.fill", L10n.tr("清理", "Cleanup", "Очистка")),
            ("trashBins", L10n.tr("废纸篓", "Trash Bins", "Корзины"), "trash.fill", L10n.tr("清理", "Cleanup", "Очистка")),
            ("malware", L10n.tr("恶意软件清理", "Malware Removal", "Удаление угроз"), "shield.lefthalf.filled", L10n.tr("防护", "Protection", "Защита")),
            ("privacy", L10n.tr("隐私清理", "Privacy", "Конфиденциальность"), "hand.raised.fill", L10n.tr("防护", "Protection", "Защита")),
            ("optimization", L10n.tr("优化", "Optimization", "Оптимизация"), "gauge.with.dots.needle.67percent", L10n.tr("加速", "Speed", "Ускорение")),
            ("maintenance", L10n.tr("维护", "Maintenance", "Обслуживание"), "wrench.and.screwdriver", L10n.tr("加速", "Speed", "Ускорение")),
            ("uninstaller", L10n.tr("卸载器", "Uninstaller", "Удаление приложений"), "xmark.app.fill", L10n.tr("应用", "Apps", "Приложения")),
            ("updater", L10n.tr("应用更新", "Updater", "Обновления"), "arrow.triangle.2.circlepath", L10n.tr("应用", "Apps", "Приложения")),
            ("largeOldFiles", L10n.tr("大文件与旧文件", "Large & Old Files", "Большие и старые файлы"), "doc.richtext.fill", L10n.tr("文件", "Files", "Файлы")),
        ]
    }

    /// Total found, on the Checkup row (UI_SPEC §3.2).
    private var sidebarBadge: SidebarBadge? {
        if case .results(_, _, _, let totalSize, _) = scanState, totalSize > 0 { return .size(totalSize) }
        return nil
    }

    /// Status button state (UI_SPEC §1.3).
    private var moduleStage: ModuleStage {
        switch scanState {
        case .idle, .empty: .idle
        case .scanning, .cleaning: .working
        case .results, .done: .results
        }
    }

    private var stateKey: String {
        switch scanState {
        case .idle: "idle"
        case .scanning: "scanning"
        case .results: "results"
        case .empty: "empty"
        case .cleaning: "cleaning"
        case .done: "done"
        }
    }

    var body: some View {
        ZStack {
            stateView
                .id(stateKey)
                .transition(TemplateMotion.stateTransition)
        }
        .animation(TemplateMotion.morph, value: stateKey)
        .environment(\.templateNamespace, morph)
        .cardDialog(isPresented: $showCleanConfirm) {
            ConfirmCleanDialog(results: cleanResults, selection: selectedItems, runningApps: runningApps,
                               total: selectedCleanSize,
                               onCancel: { showCleanConfirm = false },
                               onConfirm: { showCleanConfirm = false; runCleanup() })
        }
        .onChange(of: doneFreed) { _, freed in
            if let freed, freed > 0 { toasts?.movedToTrash(FileSizeFormatter.format(freed)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .topBarAccessory(id: "cleanupPermissions") { CleanupPermissionsButton() }
        .moduleStage(moduleStage)
        .sidebarBadge(sidebarBadge)
        .sheet(isPresented: $showActivityLog) { LogViewerView() }
        // Recompute the selected-size total only when the results or selection
        // actually change, NOT on every body pass. The footer reads
        // `selectedCleanSize`, and SwiftUI re-evaluates this body during the
        // layout pass on every sidebar switch; recomputing an O(all-items) sum
        // (with a FileItem copy per item) there froze the switch for seconds on
        // a large Smart Scan (confirmed by a main-thread sample).
        .onChange(of: cleanResultsSignature, initial: true) { _, _ in
            rebuildCleanSizeIndex()
            recomputeSelectedCleanSize()
        }
        .onChange(of: selectedItems) { _, _ in
            recomputeSelectedCleanSize()
        }
        .respondsToModuleShortcuts(
            onScan: startScan,
            onClean: { requestRun() },
            canScan: {
                switch scanState {
                case .idle, .empty, .done, .results: true
                case .scanning, .cleaning: false
                }
            }(),
            canClean: {
                if case .results = scanState { return !selectedItems.isEmpty }
                return false
            }()
        )
    }

    @ViewBuilder
    private var stateView: some View {
        Group {
            switch scanState {
            case .idle:
                idleView
            case .scanning(let phase, let progress, let filesFound, let sizeFound):
                scanningView(phase: phase, progress: progress, filesFound: filesFound, sizeFound: sizeFound)
            case .results(_, _, _, let totalSize, _):
                resultsView(totalSize: totalSize)
            case .empty:
                emptyView
            case .cleaning(let progress):
                cleaningView(progress: progress)
            case .done(let summary, let breakdown):
                doneView(summary: summary, breakdown: breakdown)
            }
        }
    }

    // MARK: - Areas (UI_SPEC §5.1)

    /// Checkup's areas, each a column on the results screen and a lane while scanning.
    enum Area: String, CaseIterable, Identifiable {
        case cleanup, protection, speed, applications, files
        var id: String { rawValue }

        var title: String {
            switch self {
            case .cleanup: L10n.tr("清理", "Cleanup", "Очистка")
            case .protection: L10n.tr("防护", "Protection", "Защита")
            case .speed: L10n.tr("加速", "Speed", "Ускорение")
            case .applications: L10n.tr("应用", "Applications", "Приложения")
            case .files: L10n.tr("文件", "Files", "Файлы")
            }
        }

        var symbol: String {
            switch self {
            case .cleanup: "internaldrive"
            case .protection: "shield.lefthalf.filled"
            case .speed: "gauge.with.dots.needle.67percent"
            case .applications: "shippingbox"
            case .files: "doc.on.doc"
            }
        }

        /// Brand kit illustration for the column.
        var brandArt: String {
            switch self {
            case .cleanup: "Art_Cleanup"
            case .protection: "Art_Protection"
            case .speed: "Art_Speed_Optimisation"
            case .applications: "Art_Applications"
            case .files: "Art_Large_And_Old"
            }
        }

        /// SF Symbol fallback if the brand art is missing.
        var art: String {
            switch self {
            case .cleanup: "takeoutbag.and.cup.and.straw"
            case .protection: "light.beacon.max"
            case .speed: "paperplane"
            case .applications: "shippingbox"
            case .files: "folder"
            }
        }

        var blurb: String {
            switch self {
            case .cleanup: "Caches, logs and leftovers that are safe to remove."
            case .protection: "Threats and privacy traces worth clearing."
            case .speed: "Tasks that keep your Mac running smoothly."
            case .applications: "Leftovers from apps you've removed."
            case .files: "Large, old and duplicate files to look over."
            }
        }

        var moduleIDs: Set<String> {
            switch self {
            case .cleanup: ["system_junk", "mail_attachments", "trash_bins", "systemJunk", "mailAttachments", "trashBins"]
            case .protection: ["malware", "privacy"]
            case .speed: ["optimization", "maintenance"]
            case .applications: ["uninstaller", "updater"]
            case .files: ["large_old_files", "duplicates", "space_lens", "shredder", "largeOldFiles"]
            }
        }

        /// Lane group in `moduleOrder`.
        var laneGroup: String {
            switch self {
            case .cleanup: L10n.tr("清理", "Cleanup", "Очистка")
            case .protection: L10n.tr("防护", "Protection", "Защита")
            case .speed: L10n.tr("加速", "Speed", "Ускорение")
            case .applications: L10n.tr("应用", "Apps", "Приложения")
            case .files: L10n.tr("文件", "Files", "Файлы")
            }
        }
    }

    private var moduleResults: [ModuleScanResult] {
        if case .results(_, _, _, _, let modules) = scanState { return modules }
        return []
    }

    private func results(in area: Area) -> [ScanResult] {
        moduleResults.filter { area.moduleIDs.contains($0.moduleID) }
            .flatMap(\.categories).filter { !$0.items.isEmpty }
    }

    /// Three columns by default; Applications and Files join when they found something.
    private var shownAreas: [Area] {
        Area.allCases.filter { area in
            [.cleanup, .protection, .speed].contains(area) || !results(in: area).isEmpty
        }
    }

    // MARK: - Intro (centred hero)

    private var idleView: some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                TemplateHero(palette: .checkup, symbol: "sparkle.magnifyingglass", artwork: "Art_Checkup", diameter: 0.35 * space.W)
                    .position(x: space.x(0.5), y: space.y(0.38))
                VStack(spacing: 8) {
                    Text("Ready when you are")
                        .font(.system(size: 30, weight: .semibold))
                        .matchedTemplate("title", in: morph)
                    Text("One scan checks junk, threats, speed and updates.")
                        .font(TypeScale.introSubtitle)
                        .foregroundStyle(TypeScale.secondaryText)
                }
                .foregroundStyle(TypeScale.primaryText)
                .multilineTextAlignment(.center)
                .frame(width: 0.6 * space.W)
                .position(x: space.x(0.5), y: space.y(0.38) + 0.175 * space.W + 52)
                PrimarySlot {
                    PrimaryButton(label: L10n.tr("扫描", "Scan", "Сканировать"), action: startScan)
                }
            }
        }
    }

    // MARK: - Scanning (lanes, A15)

    private func scanningView(phase: String, progress: Double, filesFound: Int, sizeFound: UInt64) -> some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                TemplateHero(palette: .checkup, symbol: "sparkle.magnifyingglass", artwork: "Art_Checkup", motion: .scanning,
                             diameter: 0.25 * space.W)
                    .position(x: space.x(0.5), y: space.y(0.28))
                VStack(spacing: 6) {
                    Text(L10n.tr("正在扫描…", "Scanning…", "Сканирование…"))
                        .font(TypeScale.resultsHeadline)
                        .matchedTemplate("title", in: morph)
                    PathTicker(text: phase)
                }
                .foregroundStyle(TypeScale.primaryText)
                .frame(width: 0.5 * space.W)
                .position(x: space.x(0.5), y: space.y(0.28) + 0.125 * space.W + 36)

                HStack(spacing: 14) {
                    ForEach(Array(Area.allCases.enumerated()), id: \.element) { index, area in
                        lane(area, current: phase).staggerIn(index)
                    }
                }
                .frame(width: 0.78 * space.W)
                .position(x: space.x(0.5), y: space.y(0.68))

                PrimarySlot {
                    PrimaryButton(label: "", meta: FileSizeFormatter.format(sizeFound),
                                  progress: progress, onStop: cancelScan) {}
                }
            }
        }
    }

    private func lane(_ area: Area, current: String) -> some View {
        let modules = Self.moduleOrder.filter { $0.group == area.laneGroup }
        let names = Set(modules.map(\.name))
        let finished = completedModules.filter { names.contains($0.name) }
        let size = finished.reduce(UInt64(0)) { $0 + $1.size }
        let total = max(1, modules.count)
        let fraction = modules.isEmpty ? 0 : Double(finished.count) / Double(total)
        let isDone = !modules.isEmpty && finished.count >= modules.count
        let isActive = names.contains(current)
        return VStack(spacing: 8) {
            Image(systemName: isDone ? "checkmark.circle.fill" : area.symbol)
                .font(.system(size: 22))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isDone)
                .opacity(isActive || isDone ? 1 : 0.6)
            Text(area.title)
                .font(.system(size: 13, weight: .semibold))
            Text(modules.isEmpty || (size == 0 && !isDone) ? "—" : FileSizeFormatter.format(size))
                .font(.system(size: 12))
                .foregroundStyle(TypeScale.secondaryText)
                .numericRoll(size)
            GeometryReader { proxy in
                Capsule().fill(Color.white.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(isDone ? 0.45 : 0.95))
                            .frame(width: proxy.size.width * fraction)
                    }
            }
            .frame(height: 2)
            .animation(.easeOut(duration: 0.3), value: fraction)
        }
        .foregroundStyle(TypeScale.primaryText)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results (columns, A33)

    private func resultsView(totalSize: UInt64) -> some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 4) {
                    Text("Here's what Checkup found")
                        .font(TypeScale.resultsHeadline)
                        .matchedTemplate("title", in: morph)
                    Text("Choose what to run, or run everything.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(TypeScale.primaryText)
                .frame(width: space.geometry.content.width)
                .offset(y: space.y(0.08))

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(shownAreas.enumerated()), id: \.element) { index, area in
                        CheckupColumn(
                            area: area, results: results(in: area),
                            selectedItems: $selectedItems,
                            workingProgress: nil,
                            onReview: { reviewArea = area; showReviewSheet = true })
                            .frame(maxWidth: .infinity)
                            .staggerIn(index)
                    }
                }
                .frame(width: space.geometry.content.width)
                .offset(y: space.y(0.22))

                PrimarySlot {
                    PrimaryButton(label: L10n.tr("运行", "Run", "Запустить"),
                                  meta: FileSizeFormatter.format(selectedCleanSize),
                                  isEnabled: !selectedItems.isEmpty && !showReviewSheet) { requestRun() }
                }
            }
        }
        .topBarBack(L10n.tr("重新开始", "Start Over", "Начать заново"), action: resetScan)
        .topBarTitle(L10n.tr("智能扫描", "Checkup", "Проверка"))
        .reviewSheet(isPresented: $showReviewSheet, header: L10n.tr("清理详情", "Cleanup details", "Подробности очистки")) {
            ReviewTemplate(
                results: reviewArea.map(results(in:)) ?? cleanResults,
                selectedItems: $selectedItems, palette: .checkup,
                showsPrimary: false,
                onBack: { showReviewSheet = false }, onAct: {})
        }
    }

    /// Recompute the selected-size total from the url → size index.
    private func rebuildCleanSizeIndex() {
        var map = [URL: UInt64](minimumCapacity: cleanResults.reduce(0) { $0 + $1.items.count })
        for result in cleanResults {
            for item in result.items { map[item.url] = item.size }
        }
        cleanSizeIndex = map
    }

    /// Observe the URLs themselves: selecting only safe items may replace a
    /// selection with different URLs but the same item count.
    private func recomputeSelectedCleanSize() {
        selectedCleanSize = CleanupSelectionPolicy.selectedSize(selectedItems, sizesByURL: cleanSizeIndex)
    }

    /// Include the scan generation so a same-count rescan refreshes sizes.
    private var cleanResultsSignature: String {
        fileListResultsSignature(sort: .default, results: cleanResults)
    }

    // MARK: - Empty / Working / Done

    private var emptyView: some View {
        EmptyTemplate(title: "All clear", subtitle: "Checkup didn't find anything that needs attention.",
                      intro: SidebarItem.smartScan.intro, palette: .checkup, onDone: resetScan)
    }

    /// Working: the columns stay; selected ones show a mini progress ring (§5.1).
    private func cleaningView(progress: Double) -> some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                Text(L10n.tr("正在运行…", "Running…", "Выполняется…"))
                    .font(TypeScale.resultsHeadline)
                    .foregroundStyle(TypeScale.primaryText)
                    .matchedTemplate("title", in: morph)
                    .frame(width: space.geometry.content.width)
                    .offset(y: space.y(0.08))
                HStack(alignment: .top, spacing: 0) {
                    ForEach(shownAreas) { area in
                        CheckupColumn(area: area, results: results(in: area), selectedItems: $selectedItems,
                                      workingProgress: progress, onReview: nil)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: space.geometry.content.width)
                .offset(y: space.y(0.22))
                PrimarySlot {
                    PrimaryButton(label: "", progress: progress, onStop: { cleanTask?.cancel() }) {}
                }
            }
        }
    }

    private func doneView(summary: CleanSummary, breakdown: [SmartScanCleanup.RecentlyCleanedRow]) -> some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                Group {
                    if summary.errorCount > 0 || summary.wasCancelled {
                        Image(systemName: summary.wasCancelled ? "pause.circle" : "exclamationmark.triangle.fill")
                            .font(.system(size: 0.08 * space.W))
                            .foregroundStyle(Color(hex: 0xF8C04E))
                    } else {
                        DrawnCheck(size: 0.12 * space.W)
                    }
                }
                .position(x: space.x(0.5), y: space.y(0.24))

                VStack(spacing: 18) {
                    Text(summary.wasCancelled ? L10n.tr("已停止", "Stopped", "Остановлено")
                         : summary.errorCount > 0 ? L10n.tr("已完成，但有问题", "Done, with a few problems", "Готово, но с ошибками")
                         : L10n.tr("全部完成", "All done", "Готово"))
                        .font(TypeScale.resultsHeadline)
                        .matchedTemplate("title", in: morph)
                    HStack(spacing: 50) {
                        doneMetric(FileSizeFormatter.format(summary.freedBytes), caption: L10n.tr("已释放", "freed", "освобождено"))
                        doneMetric("0", caption: L10n.tr("已移除威胁", "threats removed", "угроз удалено"))
                        doneMetric("\(breakdown.count)", caption: L10n.tr("已运行任务", "tasks run", "задач выполнено"))
                    }
                    if summary.errorCount > 0 {
                        Button(L10n.tr("查看日志", "View Log", "Открыть журнал")) { showActivityLog = true }
                            .buttonStyle(.ghostPill)
                    }
                    Button(L10n.tr("撤销清理…", "Undo cleanup…", "Отменить очистку…")) {
                        appState.selectedSidebarItem = SidebarItem.activityItem
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x5CC8F0))
                    .help("Items moved to the Trash can be put back from Activity.")
                }
                .foregroundStyle(TypeScale.primaryText)
                .frame(width: space.geometry.content.width)
                .offset(y: space.y(0.36))

                PrimarySlot {
                    PrimaryButton(label: L10n.tr("重新开始", "Start Over", "Начать заново"), action: resetScan)
                }
            }
        }
    }

    private func doneMetric(_ value: String, caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(TypeScale.bigMetric).numericRoll(value)
            Text(caption).font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
        }
        .staggerIn(1)
    }

    private func resetScan() {
        cleanTask?.cancel()
        cleanTask = nil
        scanWatchTask?.cancel()
        scanWatchTask = nil
        selectedItems = []
        cleanResults = []
        askForSupport = false
        completedModules = []
        currentModuleName = ""
        scanState = .idle
    }

    /// Abort an in-flight Smart Scan and return to the idle screen (#3).
    private func cancelScan() {
        appState.scanCoordinator.cancel()
        scanWatchTask?.cancel()
        scanWatchTask = nil
        completedModules = []
        currentModuleName = ""
        scanState = .idle
    }

    // MARK: - Actions

    private func startScan() {
        completedModules = []
        currentModuleName = ""
        scanWatchTask?.cancel()

        scanWatchTask = Task {
            scanState = .scanning(phase: L10n.tr("正在分析系统...", "Analyzing system...", "Анализ системы..."), progress: 0, filesFound: 0, sizeFound: 0)
            appState.scanCoordinator.scanAll()

            var previousModule = ""
            var previousFiles = 0
            var previousSize: UInt64 = 0

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                if Task.isCancelled { return }

                switch appState.scanCoordinator.state {
                case .scanning(let progress, let module, let files, let size):
                    // Detect module transitions
                    if module != previousModule && !previousModule.isEmpty {
                        let filesInModule = files - previousFiles
                        let sizeInModule = size - previousSize

                        let icon = Self.moduleOrder.first { $0.name == previousModule }?.icon ?? "circle"
                        completedModules.append(CompletedModule(
                            name: previousModule,
                            icon: icon,
                            fileCount: filesInModule,
                            size: sizeInModule
                        ))

                        previousFiles = files
                        previousSize = size
                    }
                    previousModule = module
                    currentModuleName = module
                    scanState = .scanning(phase: module, progress: progress, filesFound: files, sizeFound: size)

                case .completed(let results):
                    // Mark last module as completed
                    if !previousModule.isEmpty {
                        let totalFiles = results.reduce(0) { $0 + $1.totalFileCount }
                        let totalSize = results.reduce(0 as UInt64) { $0 + $1.totalSize }
                        let filesInModule = totalFiles - previousFiles
                        let sizeInModule = totalSize - previousSize
                        let icon = Self.moduleOrder.first { $0.name == previousModule }?.icon ?? "circle"
                        completedModules.append(CompletedModule(
                            name: previousModule,
                            icon: icon,
                            fileCount: filesInModule,
                            size: sizeInModule
                        ))
                    }

                    let totalSize = results.reduce(0 as UInt64) { $0 + $1.totalSize }
                    if totalSize == 0 && results.allSatisfy({ $0.totalFileCount == 0 }) {
                        scanState = .empty
                    } else {
                        cleanResults = SmartScanCleanup.allResults(from: results)
                        selectedItems = SmartScanCleanup.defaultSelection(from: results)
                        scanState = .results(
                            cleanup: totalSize,
                            protection: 0,
                            performance: 0,
                            totalSize: totalSize,
                            moduleResults: results
                        )
                    }
                    return

                case .failed:
                    scanState = .idle
                    return

                case .idle:
                    // Coordinator starts idle briefly, then moves to .scanning.
                    // After Cancel it stays idle — exit so we don't spin forever.
                    continue
                }
            }
        }
    }

    private func runCleanup() {
        // Snapshot the inputs up-front so the background task can't observe
        // later selection or scan-state mutations.
        let modules: [ModuleScanResult]
        if case .results(_, _, _, _, let moduleResults) = scanState {
            modules = moduleResults
        } else {
            modules = []
        }
        let results = cleanResults
        let selection = selectedItems
        scanState = .cleaning(progress: 0)
        cleanTask = Task {
            let result = await CleanActions.executeUserClean(
                results: results,
                selectedItems: selection,
                engine: appState.cleaningEngine,
                onProgress: { p in Task { @MainActor in
                    // Ignore late progress that lands after we've left the
                    // cleaning phase (cancel/done), so it can't resurrect
                    // a stale .cleaning state.
                    if case .cleaning = scanState {
                        scanState = .cleaning(progress: p.fraction)
                    }
                } }
            )
            let breakdown = SmartScanCleanup.recentlyCleanedBreakdown(
                from: modules,
                selectedItems: result.removedURLs
            )
            let summary = CleanSummary(
                selectedCount: selection.count,
                removedCount: result.removedCount,
                freedBytes: result.freedBytes,
                errorMessages: result.errors.map(\.error),
                wasCancelled: result.wasCancelled
            )
            askForSupport = !summary.wasCancelled && SupportAskLedger.shared.shouldAsk(for: summary)
            scanState = .done(summary: summary, breakdown: breakdown)
        }
    }
}

/// One Checkup area on the results screen (UI_SPEC §5.1): art, title with a
/// tri-state checkbox and hover popover (A33), description, big metric,
/// caption and "Review Details…". While running, the metric becomes a
/// mini progress ring.
private struct CheckupColumn: View {
    let area: SmartScanView.Area
    let results: [ScanResult]
    @Binding var selectedItems: Set<URL>
    let workingProgress: Double?
    let onReview: (() -> Void)?

    @State private var hovering = false
    @State private var showPopover = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var hoveringPopover = false

    private var urls: [URL] { results.flatMap { $0.items.map(\.url) } }
    private var selectedBytes: UInt64 { results.selectedSize(selectedItems) }
    private var state: CheckState {
        let all = urls
        guard !all.isEmpty else { return .off }
        let count = all.filter(selectedItems.contains).count
        return count == 0 ? .off : (count == all.count ? .on : .mixed)
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image = BrandAssets.image(area.brandArt) {
                    HeroDisc(palette: .checkup, symbol: "", artwork: area.brandArt, diameter: 110)
                        .accessibilityHidden(true)
                        .id(image.hash)
                } else {
                    Image(systemName: area.art)
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                }
            }
            .frame(height: 120)

            HStack(spacing: 6) {
                TriStateCheckbox(state: state) { toggle() }
                    .disabled(urls.isEmpty)
                Text(area.title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .onHover(perform: hover)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) { popover }

            Text(area.blurb)
                .font(.system(size: 11))
                .foregroundStyle(TypeScale.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 170)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if let workingProgress, state != .off {
                    ZStack {
                        Circle().stroke(.white.opacity(0.18), lineWidth: 3)
                        Circle().trim(from: 0, to: workingProgress)
                            .stroke(Color(hex: 0xA8E6FF), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(Motion.progress, value: workingProgress)
                    }
                    .frame(width: 40, height: 40)
                } else if urls.isEmpty {
                    Text(L10n.tr("良好", "Clear", "Чисто"))
                        .font(TypeScale.bigMetric)
                        .foregroundStyle(Color(hex: 0x5EE6A0))
                } else {
                    CountUpBytes(bytes: selectedBytes)
                }
            }
            .frame(height: 52)

            Text(urls.isEmpty ? "Nothing to do here" : L10n.tr("已选择", "selected", "выбрано"))
                .font(.system(size: 11))
                .foregroundStyle(TypeScale.tertiaryText)

            if let onReview, !urls.isEmpty {
                Button(L10n.tr("查看详情…", "Review Details…", "Подробнее…"), action: onReview)
                    .buttonStyle(.ghostPill)
            }
        }
        .foregroundStyle(TypeScale.primaryText)
    }

    private func toggle() {
        if state == .on { selectedItems.subtract(urls) } else { selectedItems.formUnion(urls) }
    }

    /// A33: open after a 250 ms hover; close shortly after the pointer has
    /// left both the title and the popover.
    private func hover(_ inside: Bool) {
        hoverTask?.cancel()
        guard !results.isEmpty else { return }
        hovering = inside
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(inside ? 250 : 350))
            guard !Task.isCancelled else { return }
            if inside { showPopover = true }
            else if !hoveringPopover { showPopover = false }
        }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(area.blurb)
                .font(.system(size: 12))
            ForEach(results, id: \.category) { result in
                let resultURLs = result.items.map(\.url)
                let selected = resultURLs.filter(selectedItems.contains).count
                HStack(spacing: 8) {
                    TriStateCheckbox(state: selected == 0 ? .off : (selected == resultURLs.count ? .on : .mixed), size: 14) {
                        if selected == resultURLs.count { selectedItems.subtract(resultURLs) }
                        else { selectedItems.formUnion(resultURLs) }
                    }
                    Text(result.category.displayName).font(.system(size: 12))
                    Spacer(minLength: 12)
                    Text(result.formattedSize).font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            if let onReview {
                Button(L10n.tr("查看详情…", "Review Details…", "Подробнее…")) {
                    showPopover = false
                    onReview()
                }
                .buttonStyle(.ghostPill)
            }
        }
        .padding(12)
        .frame(width: 280)
        .clean1PopoverSurface()
        .onHover { inside in
            hoveringPopover = inside
            if !inside && !hovering { hover(false) }
        }
    }
}
