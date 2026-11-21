import SwiftUI
import AppKit
import MacCleanKit

struct UninstallerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var apps: [AppInfo] = []
    @State private var selectedApp: AppInfo?
    @State private var associatedFiles: [FileItem] = []
    @State private var selectedFiles: Set<URL> = []
    @State private var isLoading = true
    @State private var isLoadingFiles = false
    @State private var isUninstalling = false
    @State private var isResetting = false
    @State private var appPendingUninstall: AppInfo?
    @State private var appPendingReset: AppInfo?
    @State private var uninstallError: String?
    @State private var resetError: String?
    @State private var filter: AppFilter = .all
    @State private var searchText = ""

    enum AppFilter: String, CaseIterable {
        case all = "全部"
        case unused = "未使用"
        case thirdParty = "第三方"

        var label: String { L10n.tr(rawValue) }
    }

    private let discovery = AppDiscovery()
    private let pathFinder = AppPathFinder()
    private let safetyGuard = SafetyGuard()

    /// HSplitView wraps NSSplitView, which ignores SwiftUI's right-to-left
    /// layout: in Farsi it squeezed the details pane into a thin column. A
    /// plain HStack mirrors correctly, so right-to-left languages use that.
    @ViewBuilder
    private var splitPanes: some View {
        if layoutDirection == .rightToLeft {
            HStack(spacing: 0) {
                appList
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 340)
                Divider()
                detailPane
                    .frame(maxWidth: .infinity)
            }
        } else {
            HSplitView {
                appList
                    .frame(minWidth: 240)
                detailPane
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let app = selectedApp {
            appDetailView(app)
                .frame(minWidth: 280)
        } else {
            VStack {
                Spacer()
                Text(L10n.tr("选择一个应用以查看相关文件", "Select an app to see its files", "Выберите приложение, чтобы увидеть связанные с ним файлы"))
                    .foregroundStyle(.primary.opacity(0.4))
                    .font(.system(size: 13))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    @State private var showList = false

    private var filterGroups: [FilterGroup] {
        [FilterGroup(id: "apps", items: [
            FilterItem(id: AppFilter.all.rawValue, title: L10n.tr("所有应用", "All Applications", "Все приложения"), count: apps.count),
            FilterItem(id: AppFilter.unused.rawValue, title: L10n.tr("未使用", "Unused", "Неиспользуемые"), count: apps.filter(\.isUnused).count),
            FilterItem(id: AppFilter.thirdParty.rawValue, title: L10n.tr("第三方", "Third-Party", "Сторонние"), count: apps.filter { !$0.isAppleApp }.count),
        ])]
    }

    var body: some View {
        IntroGate(item: .uninstaller, primaryMeta: isLoading ? nil : "\(apps.count) apps",
                  showContent: $showList, control: {
            Button(L10n.tr("选择应用…", "Choose Apps…", "Выбрать приложения…")) { showList = true }
                .buttonStyle(.secondaryPill)
        }, content: {
            ListFirstTemplate(
                groups: filterGroups,
                selectedFilter: Binding(get: { filter.rawValue }, set: { filter = AppFilter(rawValue: $0) ?? .all }),
                title: filterGroups[0].items.first { $0.id == filter.rawValue }?.title ?? "",
                description: "Pick an app to see everything it installed. Removing moves it all to the Trash.",
                trailingHeader: { EmptyView() },
                list: {
                    Group {
                        if isLoading {
                            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            singleList
                        }
                    }
                    .cardList()
                })
            .overlay {
                PrimarySlot {
                    PrimaryButton(label: L10n.tr("卸载", "Uninstall", "Удалить"),
                                  meta: checkedApps.isEmpty ? nil : "\(checkedApps.count) application\(checkedApps.count == 1 ? "" : "s")",
                                  tint: checkedApps.isEmpty ? .cyan : .pink,
                                  progress: isUninstalling ? batchProgress : nil,
                                  isEnabled: !checkedApps.isEmpty) { confirmBatch = true }
                }
            }
            .overlay { flyingIcons }
            .coordinateSpace(name: "uninstaller")
            .onPreferenceChange(IconFrameKey.self) { frames in
                Task { @MainActor in iconFrames = frames }
            }
            .topBarSearch(text: $searchText, prompt: L10n.tr("搜索应用", "Search apps", "Поиск приложений"))
        })
        .task { await loadApps() }
        .alert(L10n.tr("卸载 \(checkedApps.count) 个应用？", "Uninstall \(checkedApps.count) app\(checkedApps.count == 1 ? "" : "s")?", "Удалить приложения: \(checkedApps.count)?"),
               isPresented: $confirmBatch) {
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) {}
            Button(L10n.tr("移到废纸篓", "Move to Trash", "Переместить в Корзину"), role: .destructive) { uninstallChecked() }
        } message: {
            Text("The apps and the files they left behind go to the Trash. You can put them back from there.")
        }
        .onChange(of: appState.pendingUninstallerAppPath) { _, path in
            guard let path else { return }
            showList = true
            selectPendingApp(path: path)
        }
        // Attached to the top-level body (not the conditionally-rendered
        // detail pane) so the confirmation can't be torn down mid-present
        // when selectedApp changes. `appPendingUninstall` is the anchor.
        .alert(L10n.tr("将 \(appPendingUninstall?.name ?? "此应用") 移到废纸篓？", "Move \(appPendingUninstall?.name ?? "this app") to the Trash?", "Переместить \(appPendingUninstall?.name ?? "это приложение") в Корзину?"),
               isPresented: Binding(get: { appPendingUninstall != nil },
                                    set: { if !$0 { appPendingUninstall = nil } }),
               presenting: appPendingUninstall) { app in
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) { appPendingUninstall = nil }
            Button(L10n.tr("移到废纸篓", "Move to Trash", "Переместить в Корзину"), role: .destructive) {
                let target = app; appPendingUninstall = nil; uninstall(target)
            }
        } message: { app in
            Text(L10n.tr("\(app.name) 及其关联文件将被移到废纸篓。如有需要，你可以从废纸篓恢复。", "\(app.name) and its associated files will be moved to the Trash. You can restore them from the Trash if needed.", "Приложение \(app.name) и связанные с ним файлы будут перемещены в Корзину. При необходимости их можно восстановить."))
        }
        .alert(L10n.tr("卸载", "Uninstall"),
               isPresented: Binding(get: { uninstallError != nil },
                                    set: { if !$0 { uninstallError = nil } })) {
            Button(L10n.tr("好", "OK"), role: .cancel) { uninstallError = nil }
        } message: {
            Text(uninstallError ?? "")
        }
        .alert(
            L10n.tr(
                "将 \(appPendingReset?.name ?? "此应用") 恢复为默认设置？",
                "Reset \(appPendingReset?.name ?? "this app") to defaults?",
                "Сбросить \(appPendingReset?.name ?? "это приложение") к настройкам по умолчанию?"
            ),
            isPresented: Binding(get: { appPendingReset != nil },
                                 set: { if !$0 { appPendingReset = nil } }),
            presenting: appPendingReset
        ) { app in
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) { appPendingReset = nil }
            Button(L10n.tr("恢复默认", "Reset to Defaults", "Сбросить настройки"), role: .destructive) {
                let target = app; appPendingReset = nil; resetToDefaults(target)
            }
        } message: { app in
            let plan = AppReset.plan(app: app, associatedFiles: associatedFiles, selectedFiles: selectedFiles)
            let count = plan?.items.count ?? 0
            let bytes = plan?.items.reduce(0 as UInt64) { $0 + $1.size } ?? 0
            Text(L10n.tr(
                "将把 \(app.name) 的缓存、偏好设置和保存的状态（\(count) 项，\(FileSizeFormatter.format(bytes))）移到废纸篓。应用本身会保留。若应用正在运行，请先退出，否则它可能会重新写入这些文件。",
                "Caches, preferences, and saved state for \(app.name) (\(count) items, \(FileSizeFormatter.format(bytes))) will be moved to the Trash. The app stays installed. Quit the app first if it is running, or it may rewrite these files.",
                "Кэш, настройки и сохранённое состояние \(app.name) (\(count) \(L10n.russianPlural(count, one: "объект", few: "объекта", many: "объектов")), \(FileSizeFormatter.format(bytes))) будут перемещены в Корзину. Само приложение останется. Если оно запущено, сначала закройте его — иначе файлы могут быть записаны заново."
            ))
        }
        .alert(L10n.tr("恢复默认", "Reset to Defaults", "Сброс настроек"),
               isPresented: Binding(get: { resetError != nil },
                                    set: { if !$0 { resetError = nil } })) {
            Button(L10n.tr("好", "OK"), role: .cancel) { resetError = nil }
        } message: {
            Text(resetError ?? "")
        }
    }

    // MARK: Clean1 single list (UI_SPEC §4.6, §5.11)

    @State private var checkedApps: Set<UUID> = []
    @State private var expandedApp: UUID?
    @State private var filesByApp: [UUID: [FileItem]] = [:]
    @State private var excludedFiles: Set<URL> = []
    @State private var confirmBatch = false
    @State private var batchDone = 0
    @State private var iconFrames: [UUID: CGRect] = [:]
    @State private var flying: [FlyingIcon] = []
    @Environment(\.toasts) private var toasts

    private var batchProgress: Double { Double(batchDone) / Double(max(1, checkedApps.count)) }

    private static let pink = Color(hex: 0xF05A7E)

    private var singleList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredApps) { app in
                    appRow(app)
                        .transition(.asymmetric(insertion: .opacity,
                                                removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .top))))
                    if expandedApp == app.id {
                        componentRows(app)
                    }
                }
            }
            .animation(.easeOut(duration: 0.25), value: filteredApps.map(\.id))
        }
    }

    private func appRow(_ app: AppInfo) -> some View {
        let isChecked = checkedApps.contains(app.id)
        let isProtected = safetyGuard.isProtectedApp(app.bundleIdentifier)
        return HStack(spacing: 10) {
            Button {
                if isChecked { checkedApps.remove(app.id) } else { checkedApps.insert(app.id) }
            } label: {
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(isChecked ? 0 : 0.55), lineWidth: 1.5)
                    Circle().fill(Self.pink).scaleEffect(isChecked ? 1 : 0.01).opacity(isChecked ? 1 : 0)
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .opacity(isChecked ? 1 : 0)
                }
                .frame(width: 16, height: 16)
                .padding(4)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.12), value: isChecked)
            }
            .buttonStyle(.plain)
            .disabled(isProtected)
            .accessibilityLabel(app.name)
            .accessibilityValue(isChecked ? "Selected" : "Not selected")

            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path(percentEncoded: false)))
                .resizable()
                .frame(width: 22, height: 22)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: IconFrameKey.self,
                                           value: [app.id: proxy.frame(in: .named("uninstaller"))])
                })

            if isChecked {
                Menu {
                    Button(L10n.tr("卸载", "Uninstall", "Удалить")) { confirmBatch = true }
                    Button(L10n.tr("恢复默认", "Reset", "Сбросить")) { requestReset(app) }
                } label: {
                    HStack(spacing: 3) {
                        Text(L10n.tr("卸载", "Uninstall", "Удалить"))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(Self.pink.opacity(0.85)))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            Text(app.name).font(TypeScale.row).lineLimit(1)
            if isProtected {
                Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(TypeScale.tertiaryText)
                    .help(L10n.tr("受保护的系统应用", "Protected system app — can't be removed", "Защищённое приложение"))
            }
            Spacer(minLength: 6)
            if app.isUnused {
                Text(L10n.tr("未使用", "Unused", "Не используется"))
                    .font(.system(size: 10))
                    .foregroundStyle(TypeScale.secondaryText)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            Text(app.formattedSize)
                .font(TypeScale.rowSize)
                .foregroundStyle(.white.opacity(0.8))
            Button {
                toggleExpanded(app)
            } label: {
                Image(systemName: expandedApp == app.id ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(TypeScale.tertiaryText)
            .accessibilityLabel(L10n.tr("显示文件", "Show files", "Показать файлы"))
        }
        .foregroundStyle(TypeScale.primaryText)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { toggleExpanded(app) }
    }

    @ViewBuilder
    private func componentRows(_ app: AppInfo) -> some View {
        if let files = filesByApp[app.id] {
            ForEach(files, id: \.url) { file in
                let isOn = !excludedFiles.contains(file.url)
                HStack(spacing: 8) {
                    TriStateCheckbox(state: isOn ? .on : .off, size: 14) {
                        if isOn { excludedFiles.insert(file.url) } else { excludedFiles.remove(file.url) }
                    }
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path(percentEncoded: false)))
                        .resizable().frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(file.name).font(.system(size: 12)).lineLimit(1)
                        Text(file.url.deletingLastPathComponent().path(percentEncoded: false))
                            .font(.system(size: 10)).foregroundStyle(TypeScale.tertiaryText)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    Text(file.formattedSize).font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(TypeScale.secondaryText)
                }
                .foregroundStyle(TypeScale.primaryText)
                .padding(.leading, 38)
                .padding(.trailing, 40)
                .frame(height: 28)
            }
        } else {
            ProgressView().controlSize(.small).frame(height: 28)
        }
    }

    private func toggleExpanded(_ app: AppInfo) {
        withAnimation(.easeOut(duration: 0.2)) {
            expandedApp = expandedApp == app.id ? nil : app.id
        }
        if filesByApp[app.id] == nil { loadFiles(for: app) }
    }

    private func loadFiles(for app: AppInfo) {
        Task {
            let files = pathFinder.findAssociatedFiles(for: app)
            filesByApp[app.id] = files
        }
    }

    private func requestReset(_ app: AppInfo) {
        selectedApp = app
        let files = filesByApp[app.id] ?? pathFinder.findAssociatedFiles(for: app)
        filesByApp[app.id] = files
        associatedFiles = files
        selectedFiles = Set(files.map(\.url)).subtracting(excludedFiles)
        appPendingReset = app
    }

    /// Uninstall every checked app in turn. Each removed row collapses and
    /// its icon flies to the button (A19).
    private func uninstallChecked() {
        let targets = apps.filter { checkedApps.contains($0.id) }
        guard !targets.isEmpty, !isUninstalling else { return }
        isUninstalling = true
        batchDone = 0
        Task {
            var failures: [String] = []
            for app in targets {
                let files = filesByApp[app.id] ?? pathFinder.findAssociatedFiles(for: app)
                let selection = Set(files.map(\.url)).subtracting(excludedFiles)
                guard let plan = AppUninstaller.plan(app: app, associatedFiles: files, selectedFiles: selection,
                                                      safetyGuard: safetyGuard) else {
                    failures.append(app.name)
                    batchDone += 1
                    continue
                }
                let result = await CleanActions.executeUserClean(items: plan.items, selectedItems: plan.selection,
                                                                 engine: appState.cleaningEngine)
                if result.errors.isEmpty {
                    launchFlight(for: app)
                    withAnimation(.easeOut(duration: 0.25)) {
                        apps.removeAll { $0.id == app.id }
                        checkedApps.remove(app.id)
                    }
                } else {
                    failures.append(app.name)
                }
                batchDone += 1
            }
            let removed = targets.count - failures.count
            if removed > 0 { toasts?.movedToTrash("\(removed) app\(removed == 1 ? "" : "s")") }
            if !failures.isEmpty {
                uninstallError = "Some items couldn't be removed for: " + failures.joined(separator: ", ")
                    + ". Quit them if they're running and try again."
            }
            isUninstalling = false
            await loadApps()
        }
    }

    private func launchFlight(for app: AppInfo) {
        guard let frame = iconFrames[app.id] else { return }
        let icon = FlyingIcon(id: UUID(), image: NSWorkspace.shared.icon(forFile: app.path.path(percentEncoded: false)),
                              start: CGPoint(x: frame.midX, y: frame.midY))
        flying.append(icon)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            flying.removeAll { $0.id == icon.id }
        }
    }

    private var flyingIcons: some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                ForEach(flying) { icon in
                    FlyingIconView(icon: icon, target: space.buttonCenter)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var filteredApps: [AppInfo] {
        var filtered = apps
        switch filter {
        case .all: break
        case .unused: filtered = filtered.filter(\.isUnused)
        case .thirdParty: filtered = filtered.filter { !$0.isAppleApp }
        }
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
            }
        }
        return filtered
    }

    private var appList: some View {
        List {
            ForEach(filteredApps) { app in
                Button {
                    selectedApp = app
                    loadAssociatedFiles(for: app)
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path(percentEncoded: false)))
                            .resizable()
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(app.formattedSize)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if app.isUnused {
                            Text(L10n.tr("未使用", "Unused", "Не используется"))
                                .font(.system(size: 10))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.orange.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .background(selectedApp?.id == app.id ? Color.accentColor.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .listStyle(.sidebar)
    }

    private func appDetailView(_ app: AppInfo) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path(percentEncoded: false)))
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.headline)
                    Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                    if let version = app.version {
                        Text("v\(version)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()

                if isUninstalling || isResetting {
                    // In-progress feedback: the button is gone (can't be
                    // re-tapped) and a spinner shows the work is happening.
                    ProgressView()
                        .controlSize(.small)
                    Text(isResetting
                         ? L10n.tr("正在恢复默认…", "Resetting…", "Сброс…")
                         : L10n.tr("正在卸载…", "Uninstalling…", "Удаление…"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    if safetyGuard.isProtectedApp(app.bundleIdentifier) {
                        Text(L10n.tr("受保护的系统应用——无法移除", "Protected system app — can't be removed", "Защищённое системное приложение — удалить нельзя"))
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.6))
                    } else {
                        Button(L10n.tr("卸载", "Uninstall", "Удалить")) { appPendingUninstall = app }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.small)
                    }

                    Button(L10n.tr("恢复默认", "Reset to Defaults", "Сбросить настройки")) {
                        appPendingReset = app
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(AppReset.plan(app: app, associatedFiles: associatedFiles, selectedFiles: selectedFiles) == nil)
                    .help(L10n.tr(
                        "清除缓存、偏好设置和保存的状态，保留应用本身。",
                        "Clears caches, preferences, and saved state. The app stays installed.",
                        "Очищает кэш, настройки и сохранённое состояние. Само приложение остаётся."
                    ))
                }
            }
            .padding()

            if isLoadingFiles {
                Spacer()
                ProgressView(L10n.tr("正在查找关联文件...", "Finding associated files...", "Поиск связанных файлов..."))
                    .tint(.secondary)
                    .font(.system(size: 12))
                Spacer()
            } else if !associatedFiles.isEmpty {
                let totalSize = associatedFiles.reduce(0 as UInt64) { $0 + $1.size }
                Text(L10n.tr("\(associatedFiles.count) 个关联文件（\(FileSizeFormatter.format(totalSize))）", "\(associatedFiles.count) associated files (\(FileSizeFormatter.format(totalSize)))", "\(associatedFiles.count) \(L10n.russianPlural(associatedFiles.count, one: "связанный файл", few: "связанных файла", many: "связанных файлов")) (\(FileSizeFormatter.format(totalSize)))"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                List(associatedFiles) { file in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { selectedFiles.contains(file.url) },
                            set: { on in
                                if on { selectedFiles.insert(file.url) }
                                else { selectedFiles.remove(file.url) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        Image(systemName: file.isDirectory ? "folder" : "doc")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name).font(.system(size: 12))
                            Text(file.url.deletingLastPathComponent().path(percentEncoded: false))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()
                        Text(file.formattedSize)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
            } else {
                Spacer()
                Text(L10n.tr("未找到关联文件", "No associated files found", "Связанные файлы не найдены"))
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                Spacer()
            }
        }
    }

    private func resetToDefaults(_ app: AppInfo) {
        guard !isResetting, !isUninstalling else { return }
        guard let plan = AppReset.plan(
            app: app,
            associatedFiles: associatedFiles,
            selectedFiles: selectedFiles
        ) else { return }

        isResetting = true
        Task {
            let result = await CleanActions.executeUserClean(
                items: plan.items,
                selectedItems: plan.selection,
                engine: appState.cleaningEngine
            )
            if !result.errors.isEmpty {
                resetError = L10n.tr(
                    "恢复 \(app.name) 的默认设置时部分项目失败（\(result.errors.count) 个）。请确认应用已退出后重试。",
                    "Some items couldn't be reset for \(app.name) (\(result.errors.count)). Quit the app if it is running and try again.",
                    "Не удалось сбросить часть данных \(app.name) (\(result.errors.count)). Закройте приложение, если оно запущено, и повторите попытку."
                )
            }
            loadAssociatedFiles(for: app)
            isResetting = false
        }
    }

    private func loadApps() async {
        apps = await discovery.discoverApps()
        isLoading = false
        if let path = appState.pendingUninstallerAppPath {
            selectPendingApp(path: path)
        }
    }

    private func selectPendingApp(path: String) {
        // Consume the request either way, so a stale path (app removed since
        // Unused Apps listed it) can't select something on a later visit.
        appState.pendingUninstallerAppPath = nil
        guard let match = apps.first(where: {
            $0.path.path(percentEncoded: false) == path
        }) else { return }
        selectedApp = match
        loadAssociatedFiles(for: match)
        filter = .all
    }

    private func loadAssociatedFiles(for app: AppInfo) {
        isLoadingFiles = true
        associatedFiles = []
        Task {
            let files = pathFinder.findAssociatedFiles(for: app)
            associatedFiles = files
            selectedFiles = Set(files.map(\.url))
            isLoadingFiles = false
        }
    }

    private func uninstall(_ app: AppInfo) {
        guard !isUninstalling else { return }   // ignore double-taps

        // Build the validated plan. Refuses protected system apps (bundle-id
        // check that SafetyGuard.validatePath can't do) and routes the app
        // bundle through the same validated, logged, trash-first engine as its
        // leftovers, instead of a raw try? trashItem that skipped every guard.
        guard let plan = AppUninstaller.plan(
            app: app,
            associatedFiles: associatedFiles,
            selectedFiles: selectedFiles,
            safetyGuard: safetyGuard
        ) else {
            uninstallError = L10n.tr(
                "\(app.name) 是受保护的系统应用，无法移除。",
                "\(app.name) is a protected system app and can't be removed.")
            return
        }

        isUninstalling = true
        Task {
            let result = await CleanActions.executeUserClean(
                items: plan.items,
                selectedItems: plan.selection,
                engine: appState.cleaningEngine
            )
            // Surface failures instead of silently swallowing them: if the
            // bundle or a leftover couldn't be removed, tell the user.
            if !result.errors.isEmpty {
                uninstallError = L10n.tr(
                    "移除 \(app.name) 时部分项目失败（\(result.errors.count) 个）。请查看该应用是否仍在，如仍在可重试。",
                    "Some items couldn't be removed while uninstalling \(app.name) (\(result.errors.count)). Check whether the app is still there and try again.")
            }
            await loadApps()
            isUninstalling = false
            selectedApp = nil
            associatedFiles = []
        }
    }
}

struct FlyingIcon: Identifiable {
    let id: UUID
    let image: NSImage
    let start: CGPoint
}

/// A19: the icon follows a curve to the button, shrinking to 0.2 and fading, 0.6 s.
private struct FlyingIconView: View {
    let icon: FlyingIcon
    let target: CGPoint
    @State private var began = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                EmptyView()
            } else {
                TimelineView(.animation) { context in
            let raw = min(1, max(0, context.date.timeIntervalSince(began) / 0.6))
            let t = CGFloat(raw * raw) // ease in
            let control = CGPoint(x: (icon.start.x + target.x) / 2, y: min(icon.start.y, target.y) - 80)
            let x = (1 - t) * (1 - t) * icon.start.x + 2 * (1 - t) * t * control.x + t * t * target.x
            let y = (1 - t) * (1 - t) * icon.start.y + 2 * (1 - t) * t * control.y + t * t * target.y
            Image(nsImage: icon.image)
                .resizable()
                .frame(width: 22, height: 22)
                .scaleEffect(1 - 0.8 * t)
                .opacity(Double(1 - t * 0.9))
                .position(x: x, y: y)
                }
            }
        }
        .onAppear { began = Date() }
    }
}

private struct IconFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
