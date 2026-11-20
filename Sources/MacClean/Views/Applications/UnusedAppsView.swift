import AppKit
import SwiftUI
import MacCleanKit

struct UnusedAppsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var horizon: UnusedAppHorizon = .sixMonths
    @State private var records: [UnusedAppRecord] = []
    @State private var isLoading = true
    @State private var loadGeneration = 0

    private var apps: [UnusedAppRecord] { UnusedApps.unused(from: records, horizon: horizon) }

    @State private var showList = false

    var body: some View {
        IntroGate(item: .unusedApps, primaryMeta: nil, focusSidebar: true,
                  showContent: $showList) {
            legacyContent
        }
    }

    /// List-first (UI_SPEC §4.6): how long unused on the left, apps on the right.
    private var legacyContent: some View {
        ListFirstTemplate(
            groups: [FilterGroup(id: "horizons", header: L10n.tr("未打开超过", "Not opened for", "Не открывались"),
                                 items: UnusedAppHorizon.allCases.map { h in
                FilterItem(id: h.rawValue, title: h.label,
                           count: isLoading ? nil : UnusedApps.unused(from: records, horizon: h).count)
            })],
            selectedFilter: Binding(get: { horizon.rawValue },
                                    set: { horizon = UnusedAppHorizon(rawValue: $0) ?? .sixMonths }),
            title: L10n.tr("未使用的应用", "Unused Apps", "Неиспользуемые приложения"),
            description: "Sorted by how much space they use. Uninstall hands an app to the Uninstaller with its leftovers.",
            trailingHeader: {
                Button { Task { await reload() } } label: {
                    Label(L10n.tr("刷新", "Refresh", "Обновить"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.ghostPill)
                .disabled(isLoading)
            },
            list: { listBody.cardList() })
        .task { await reload() }
        .respondsToModuleShortcuts(onScan: { Task { await reload() } }, canScan: !isLoading)
    }

    @ViewBuilder
    private var listBody: some View {
        if isLoading {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(L10n.tr("正在查找未使用的应用…", "Looking for unused apps…", "Поиск неиспользуемых приложений…"))
                    .font(.system(size: 12)).foregroundStyle(TypeScale.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if UnusedApps.usageDataUnavailable(in: records) {
            VStack(spacing: 6) {
                Text(L10n.tr("Spotlight 没有应用的使用记录", "Spotlight has no usage history for your apps", "В Spotlight нет истории использования приложений"))
                    .font(.system(size: 13, weight: .medium))
                Text("\(MCConstants.appName) can't tell which apps are unused. Check that Spotlight indexing is on.")
                    .font(.system(size: 12)).foregroundStyle(TypeScale.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if apps.isEmpty {
            Text(L10n.tr("没有符合条件的应用", "Nothing unused for this long.", "Нет неиспользуемых приложений за этот период"))
                .font(.system(size: 13)).foregroundStyle(TypeScale.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        row(app).staggerIn(index)
                    }
                }
            }
        }
    }

    private func row(_ app: UnusedAppRecord) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name).font(TypeScale.row).lineLimit(1)
                    if app.runsInBackground {
                        Text(L10n.tr("后台", "Background", "Фоновое"))
                            .font(.system(size: 10))
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                }
                Text(subtitle(for: app))
                    .font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(FileSizeFormatter.format(app.totalBytes))
                .font(TypeScale.rowSize).foregroundStyle(.white.opacity(0.8))
            Button(L10n.tr("卸载…", "Uninstall…", "Удалить…")) {
                appState.openUninstaller(forAppPath: app.path)
            }
            .buttonStyle(.ghostPill)
        }
        .foregroundStyle(TypeScale.primaryText)
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    private func subtitle(for app: UnusedAppRecord) -> String {
        let last: String
        if let date = app.lastUsed {
            last = date.formatted(date: .abbreviated, time: .omitted)
        } else {
            last = L10n.tr("未知", "Unknown", "Неизвестно")
        }
        let support = FileSizeFormatter.format(app.supportBytes)
        let lastLabel = L10n.tr("上次打开", "Last opened", "Открывалось")
        let supportLabel = L10n.tr("支持文件", "Support files", "Файлы поддержки")
        return "\(lastLabel) \(last) · \(supportLabel) \(support)"
    }

    private func reload() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        let running = Set(NSWorkspace.shared.runningApplications.compactMap {
            $0.bundleURL?.path(percentEncoded: false)
        })
        let listed = await Task.detached {
            await UnusedAppsClient().records(runningAppPaths: running)
        }.value
        // A newer refresh started while this one ran: drop the stale result.
        guard generation == loadGeneration else { return }
        records = listed
        isLoading = false
    }
}
