import SwiftUI
import MacCleanKit

struct ContentView: View {
    @Environment(AppState.self) private var appState

    /// Module views the user has visited at least once. Once a view is here it
    /// stays in the hierarchy (hidden via opacity, NOT destroyed) when the user
    /// switches tabs — so in-flight scans keep running and large result lists
    /// don't re-render on every switch (fixes the switch-back lag and the
    /// mid-scan "cancel"). Views are created lazily on first visit so we don't
    /// front-load every module's `.task` (app discovery, login items, …) at
    /// launch.
    @State private var visited: Set<SidebarItem> = []
    @State private var updateCoordinator = UpdateCoordinator()
    @State private var selfUpdater = SelfUpdateController.shared
    @Environment(\.scenePhase) private var scenePhase

    /// Right-to-left applies inside the sidebar and the module panes, not to
    /// the shell: the sidebar always floats over the card's left edge.
    private var contentDirection: LayoutDirection {
        AppLanguage.current.isRightToLeft ? .rightToLeft : .leftToRight
    }

    @State private var isFullScreen = false

    var body: some View {
        GeometryReader { proxy in
            let metrics = ShellMetrics(windowSize: proxy.size, isFullScreen: isFullScreen)
            ZStack(alignment: .topLeading) {
                if !metrics.isFullScreen { ResizeEdgeBand() }
                card(metrics)
                sidebarPanel(metrics)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(
                WindowConfigurator(
                    trafficLightOrigin: metrics.trafficLightOrigin,
                    interactiveRects: [metrics.card, metrics.sidebar],
                    onFullScreenChange: { value in
                        withAnimation(.easeInOut(duration: 0.25)) { isFullScreen = value }
                    }))
        }
        .ignoresSafeArea()
        // Clean1: the app is always "on colour" with white text (UI_SPEC §2.1).
        .preferredColorScheme(.dark)
        .disabled(selfUpdater.isPreparingInstallation)
        .overlay {
            if selfUpdater.isPreparingInstallation {
                SelfUpdatePreparationOverlay(
                    canCancel: selfUpdater.canCancelPreparation,
                    onCancel: { selfUpdater.cancelPreparation() })
                .environment(\.layoutDirection, contentDirection)
            }
        }
        // Mark the current selection visited (runs initially too) so its view
        // is created on first visit and then retained.
        .onChange(of: appState.selectedSidebarItem, initial: true) { _, newValue in
            if let newValue { visited.insert(newValue) }
        }
        // Automatic update check: ~3s after launch (never blocks startup) and
        // again whenever the app becomes active. UpdateCoordinator throttles to
        // once per day and one popup per session.
        .task {
            try? await Task.sleep(for: .seconds(3))
            if !selfUpdater.usesInAppUpdates { await updateCoordinator.runCheckIfDue() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { if !selfUpdater.usesInAppUpdates { await updateCoordinator.runCheckIfDue() } }
            }
        }
        .alert(
            L10n.tr("发现新版本", "Update available", "Доступно обновление"),
            isPresented: Binding(
                get: { updateCoordinator.pendingUpdate != nil },
                set: { if !$0 { updateCoordinator.dismiss() } }
            ),
            presenting: updateCoordinator.pendingUpdate
        ) { pending in
            switch pending.action {
            case .brewCommand:
                Button(L10n.tr("复制升级命令", "Copy Upgrade Command", "Скопировать команду обновления")) {
                    updateCoordinator.performPrimaryAction()
                }
            case .openRelease:
                Button(L10n.tr("下载", "Download", "Загрузить")) {
                    updateCoordinator.performPrimaryAction()
                }
            }
            Button(L10n.tr("跳过此版本", "Skip This Version", "Пропустить эту версию")) {
                updateCoordinator.skip(pending.version)
            }
            Button(L10n.tr("稍后", "Later", "Позже"), role: .cancel) {
                updateCoordinator.dismiss()
            }
        } message: { pending in
            switch pending.action {
            case .brewCommand(let cmd):
                Text(L10n.tr(
                    "Mac Sai \(pending.version) 已发布。使用 Homebrew 升级：\n\(cmd)",
                    "Mac Sai \(pending.version) is available. Upgrade with Homebrew:\n\(cmd)",
                    "Доступна версия Mac Sai \(pending.version). Обновите через Homebrew:\n\(cmd)"))
            case .openRelease:
                Text(L10n.tr(
                    "Mac Sai \(pending.version) 已发布。",
                    "Mac Sai \(pending.version) is available.",
                    "Доступна версия Mac Sai \(pending.version)."))
            }
        }
    }

    // MARK: Shell (UI_SPEC §1.1)

    private var currentItem: SidebarItem { appState.selectedSidebarItem ?? .smartScan }

    /// The gradient card: backdrop, drag area, module host and top bar.
    private func card(_ metrics: ShellMetrics) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.cardRadius, style: .continuous)
        return ZStack(alignment: .topLeading) {
            ModuleBackdrop(item: currentItem)
            WindowDragArea()
            moduleHost
                .frame(width: metrics.content.width, height: metrics.content.height)
                .offset(x: metrics.content.minX, y: metrics.content.minY)
                .environment(\.layoutDirection, contentDirection)
        }
        .frame(width: metrics.card.width, height: metrics.card.height, alignment: .topLeading)
        .overlayPreferenceValue(TopBarPreferenceKey.self) { content in
            TopBar(item: currentItem, content: content)
                .padding(.leading, metrics.content.minX)
                .padding(.trailing, CardLayout.statusButtonInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environment(\.layoutDirection, contentDirection)
        }
        .clipShape(shape)
        .background(
            shape
                .fill(currentItem.palette.bottom)
                .shadow(color: .black.opacity(metrics.isFullScreen ? 0 : 0.35), radius: 30, y: 14))
        .offset(x: metrics.card.minX, y: metrics.card.minY)
    }

    /// The sidebar, floating over the card's left edge.
    private func sidebarPanel(_ metrics: ShellMetrics) -> some View {
        @Bindable var state = appState
        let shape = RoundedRectangle(cornerRadius: Surface.sidebarRadius, style: .continuous)
        return SidebarView(selection: $state.selectedSidebarItem)
            .environment(\.layoutDirection, contentDirection)
            .frame(width: metrics.sidebar.width, height: metrics.sidebar.height)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Surface.sidebarFill)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Surface.sidebarStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
            .offset(x: metrics.sidebar.minX, y: metrics.sidebar.minY)
    }

    /// Every visited module stays alive (hidden, not torn down) so scans keep
    /// running and big result lists don't re-render on each switch. Views are
    /// created on first visit so launch doesn't run every module's `.task`.
    private var moduleHost: some View {
        ZStack {
            ForEach(SidebarItem.allCases, id: \.self) { item in
                if visited.contains(item) || item == appState.selectedSidebarItem {
                    let isSelected = item == appState.selectedSidebarItem
                    moduleView(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(isSelected ? 1 : 0)
                        .allowsHitTesting(isSelected)
                        .accessibilityHidden(!isSelected)
                        .environment(\.moduleIsSelected, isSelected)
                        // Only the visible module talks to the top bar.
                        .transformPreference(TopBarPreferenceKey.self) { value in
                            if !isSelected { value = TopBarContent() }
                        }
                }
            }

            if appState.selectedSidebarItem == nil {
                Text(L10n.tr("请从侧边栏选择一个模块", "Select a module from the sidebar", "Выберите модуль на боковой панели"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func moduleView(for item: SidebarItem) -> some View {
        switch item {
        case .smartScan:
            SmartScanView()
        case .systemJunk:
            SystemJunkView()
        case .mailAttachments:
            MailAttachmentsView()
        case .trashBins:
            TrashBinsView()
        case .diskHogs:
            DiskHogsView()
        case .projectJunk:
            ProjectJunkView()
        case .cleanHistory:
            CleanHistoryView()
        case .malwareRemoval:
            MalwareView()
        case .privacy:
            PrivacyView()
        case .browserExtensions:
            BrowserExtensionsView()
        case .wifiNetworks:
            WiFiNetworksView()
        case .appPermissions:
            AppPermissionsView()
        case .optimization:
            OptimizationView()
        case .maintenance:
            MaintenanceView()
        case .uninstaller:
            UninstallerView()
        case .unusedApps:
            UnusedAppsView()
        case .extensions:
            ExtensionsView()
        case .updater:
            UpdaterView()
        case .spaceLens:
            SpaceLensView()
        case .largeOldFiles:
            LargeOldFilesView()
        case .duplicates:
            DuplicatesView()
        case .shredder:
            ShredderView()
        case .settings:
            SettingsPageView()
        }
    }
}

/// A near-invisible band along the window's edges. Fully transparent pixels
/// pass clicks through to whatever is behind the window, which would also
/// make the resize edges ungrabbable; this keeps a thin strip catchable while
/// the rest of the margin stays click-through (UI_SPEC §1.1).
private struct ResizeEdgeBand: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Color.black.opacity(0.012), lineWidth: 6)
            .allowsHitTesting(false)
    }
}
