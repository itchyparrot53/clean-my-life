import AppKit
import SwiftUI
import MacCleanKit

struct AppPermissionsView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var snapshot = AppPermissionsSnapshot(grants: [], listing: .loaded)
    @State private var isLoading = true
    private let client = AppPermissionsClient.live()

    private var apps: [AppPermissionApp] {
        AppPermissionOverview.apps(from: snapshot.grants)
    }

    @State private var showList = false
    @State private var filter = "all"

    private var grantsForFilter: [AppPermissionApp] {
        guard filter != "all" else { return apps }
        return apps.filter { $0.grants.contains { $0.permission.rawValue == filter } }
    }

    private var filterGroups: [FilterGroup] {
        [
            FilterGroup(id: "all", items: [
                FilterItem(id: "all", title: L10n.tr("所有应用", "All Apps", "Все приложения"), count: apps.count),
            ]),
            FilterGroup(id: "services", header: L10n.tr("服务", "Services", "Службы"), items: PrivacyPermission.allCases.map { permission in
                FilterItem(id: permission.rawValue, title: permissionTitle(permission),
                           count: apps.filter { $0.grants.contains { $0.permission == permission } }.count)
            }),
        ]
    }

    var body: some View {
        Group {
            if showList {
                ListFirstTemplate(
                    groups: filterGroups, selectedFilter: $filter,
                    title: filter == "all" ? L10n.tr("所有应用", "All Apps", "Все приложения")
                        : PrivacyPermission(rawValue: filter).map(permissionTitle) ?? "",
                    description: "Read-only overview. Changing a grant happens in System Settings.",
                    onBack: { showList = false },
                    trailingHeader: {
                        Button {
                            Task { await reload() }
                        } label: {
                            Label(L10n.tr("刷新", "Refresh", "Обновить"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.ghostPill)
                        .disabled(isLoading)
                    },
                    list: { listContent })
                .transition(TemplateMotion.stateTransition)
            } else {
                IntroTemplate(title: L10n.tr("权限总览", "Permissions", "Обзор разрешений"),
                              intro: SidebarItem.appPermissions.intro, palette: .protection,
                              primaryMeta: isLoading ? nil : "\(apps.count) apps",
                              onPrimary: { showList = true })
                .transition(TemplateMotion.stateTransition)
            }
        }
        .animation(TemplateMotion.morph, value: showList)
        .task { await reload() }
        .respondsToModuleShortcuts(onScan: { Task { await reload() } }, canScan: !isLoading)
    }

    @ViewBuilder
    private var listContent: some View {
        if isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if snapshot.listing != .loaded {
                        listingBanner.padding(.bottom, 8)
                    }
                    ForEach(grantsForFilter) { app in
                        appRow(app)
                    }
                    if snapshot.listing == .loaded && grantsForFilter.isEmpty {
                        Text(L10n.tr("未列出任何应用。", "No apps listed.", "Приложения не показаны."))
                            .font(.system(size: 13))
                            .foregroundStyle(TypeScale.tertiaryText)
                            .padding(.top, 12)
                    }
                }
            }
        }
    }

    /// 30 pt row: icon, name, the grants as small symbols, and a jump to
    /// System Settings for the filtered service.
    private func appRow(_ app: AppPermissionApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon(for: app))
                .resizable()
                .frame(width: 22, height: 22)
            Text(displayName(for: app))
                .font(TypeScale.row)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach(app.grants) { grant in
                    Image(systemName: permissionIcon(grant.permission))
                        .font(.system(size: 11))
                        .foregroundStyle(TypeScale.secondaryText)
                        .help(permissionTitle(grant.permission) + (grant.isLimited ? " (limited)" : ""))
                }
            }
            Button(L10n.tr("打开设置", "Open Settings", "Настройки")) {
                let permission = PrivacyPermission(rawValue: filter) ?? app.grants.first?.permission
                if let permission { client.openSettings(for: permission) }
            }
            .buttonStyle(.ghostPill)
        }
        .foregroundStyle(TypeScale.primaryText)
        .padding(.horizontal, 8)
        .frame(height: 34)
    }

    private var listingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                snapshot.listing == .needsFullDiskAccess
                    ? L10n.tr("需要完全磁盘访问权限才能列出应用", "Full Disk Access needed to list apps", "Чтобы показать приложения, нужен полный доступ к диску")
                    : L10n.tr("无法读取权限数据库", "Couldn't read the permission database", "Не удалось прочитать базу разрешений")
            )
            .font(.system(size: 13, weight: .semibold))
            Text(
                snapshot.listing == .needsFullDiskAccess
                    ? L10n.tr(
                        "macOS 正在阻止按应用汇总。请为 \(MCConstants.appName) 授予完全磁盘访问权限，然后刷新。下方按钮仍会打开系统设置。",
                        "macOS is blocking the by-app overview. Grant \(MCConstants.appName) Full Disk Access, then refresh. The buttons below still open System Settings.",
                        "macOS блокирует сводку по приложениям. Предоставьте \(MCConstants.appName) полный доступ к диску и обновите. Кнопки ниже по-прежнему открывают Системные настройки."
                    )
                    : L10n.tr(
                        "无法列出哪些应用持有哪些权限。仍可通过下方按钮打开系统设置。",
                        "This app can't list which apps hold which grants. You can still open System Settings with the buttons below.",
                        "Не получается показать, какие приложения какими разрешениями владеют. По-прежнему можно открыть Системные настройки кнопками ниже."
                    )
            )
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.7))
            if snapshot.listing == .needsFullDiskAccess {
                Button(L10n.tr("在系统设置中打开", "Open in System Settings", "Открыть в Системных настройках")) {
                    client.openFullDiskAccessSettings()
                }
                .buttonStyle(.secondaryPill)
            }
        }
        .padding(.vertical, 6)
    }

    private func reload() async {
        isLoading = true
        snapshot = await client.load()
        isLoading = false
    }

    private func grantCountLabel(_ count: Int) -> String {
        L10n.tr(
            "\(count) 项权限",
            count == 1 ? "1 grant" : "\(count) grants",
            "\(count) \(L10n.russianPlural(count, one: "разрешение", few: "разрешения", many: "разрешений"))"
        )
    }

    private func permissionTitle(_ permission: PrivacyPermission) -> String {
        switch permission {
        case .camera: L10n.tr("相机", "Camera", "Камера")
        case .microphone: L10n.tr("麦克风", "Microphone", "Микрофон")
        case .fullDiskAccess: L10n.tr("完全磁盘访问权限", "Full Disk Access", "Полный доступ к диску")
        case .screenRecording: L10n.tr("屏幕录制", "Screen Recording", "Запись экрана")
        case .automation: L10n.tr("自动化", "Automation", "Автоматизация")
        }
    }

    private func permissionIcon(_ permission: PrivacyPermission) -> String {
        switch permission {
        case .camera: "web.camera"
        case .microphone: "mic"
        case .fullDiskAccess: "externaldrive"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .automation: "gearshape.2"
        }
    }

    private func displayName(for app: AppPermissionApp) -> String {
        if app.clientIsPath {
            return URL(filePath: app.client).deletingPathExtension().lastPathComponent
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.client) {
            return FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        }
        return app.client
    }

    private func icon(for app: AppPermissionApp) -> NSImage {
        if app.clientIsPath {
            return NSWorkspace.shared.icon(forFile: app.client)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.client) {
            return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }
}
