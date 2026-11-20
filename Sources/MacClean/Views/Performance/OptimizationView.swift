import SwiftUI
import MacCleanKit

struct OptimizationView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var loginItems: [AutoStartItem] = []
    @State private var launchAgents: [AutoStartItem] = []
    @State private var launchDaemons: [AutoStartItem] = []
    @State private var selectedTab = 0
    @State private var isLoading = true
    @State private var showAlert = false
    @State private var alertMessage = ""

    private let manager = AutoStartManager()

    @State private var showList = false

    private var tabTitles: [(id: Int, title: String)] {
        [
            (0, L10n.tr("占用资源", "Heavy Consumers", "Нагрузка")),
            (1, L10n.tr("登录项", "Login Items", "Объекты входа")),
            (2, L10n.tr("启动代理", "Launch Agents", "Агенты запуска")),
            (3, L10n.tr("启动守护进程", "Launch Daemons", "Демоны запуска")),
            (4, L10n.tr("文件打开方式", "File Associations", "Связи файлов")),
        ]
    }

    private var itemCount: Int { loginItems.count + launchAgents.count + launchDaemons.count }

    private func count(for tab: Int) -> Int? {
        switch tab {
        case 1: loginItems.count
        case 2: launchAgents.count
        case 3: launchDaemons.count
        default: nil
        }
    }

    var body: some View {
        IntroGate(item: .optimization, primaryMeta: isLoading ? nil : "\(itemCount) items",
                  showContent: $showList, control: {
            Button("View All \(itemCount) Items…") { selectedTab = 1; showList = true }
                .buttonStyle(.secondaryPill)
        }, content: {
            ListFirstTemplate(
                groups: [FilterGroup(id: "kinds", items: tabTitles.map {
                    FilterItem(id: String($0.id), title: $0.title, count: count(for: $0.id))
                })],
                selectedFilter: Binding(get: { String(selectedTab) }, set: { selectedTab = Int($0) ?? 0 }),
                title: tabTitles[selectedTab].title,
                description: description(for: selectedTab),
                trailingHeader: {
                    Button { refresh() } label: {
                        Label(L10n.tr("刷新", "Refresh", "Обновить"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.ghostPill)
                },
                list: { tabContent.cardList() })
        })
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK") { showAlert = false }
        }
        .task { refresh() }
    }

    private func description(for tab: Int) -> String {
        switch tab {
        case 0: "Apps using the most CPU and memory right now. Updates every couple of seconds."
        case 1: "Apps that open when you log in."
        case 2: "Helpers that run in the background for your user."
        case 3: "System-wide helpers. Some belong to macOS and are locked."
        default: "Which app opens each kind of file."
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if selectedTab == 0 {
            ResourceHogsView()
        } else if selectedTab == 4 {
            FileHandlerView()
        } else if isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch selectedTab {
            case 2: itemList(items: launchAgents)
            case 3: itemList(items: launchDaemons)
            default: itemList(items: loginItems)
            }
        }
    }

    // MARK: - Item List

    @ViewBuilder
    private func itemList(items: [AutoStartItem]) -> some View {
        if items.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text(L10n.tr("没有找到项目", "No items found", "Объекты не найдены"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(items, id: \.id) { item in
                    ItemRow(item: item, onToggle: { newVal in
                        do {
                            try manager.toggleItem(item, enabled: newVal)
                            refresh()
                        } catch {
                            alertMessage = error.localizedDescription
                            showAlert = true
                        }
                    }, onOpenConfig: {
                        manager.openConfigInFinder(item)
                    })
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Refresh

    private func refresh() {
        loginItems = manager.getLoginItems()
        launchAgents = manager.getLaunchAgents()
        launchDaemons = manager.getLaunchDaemons()
        isLoading = false
    }
}

// MARK: - Item Row

private struct ItemRow: View {
    let item: AutoStartItem
    let onToggle: (Bool) -> Void
    let onOpenConfig: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // App Icon
            if let bid = item.bundleIdentifier,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 28, height: 28)
            } else if let path = item.programPath,
                      FileManager.default.fileExists(atPath: path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 28)
            }

            // Name and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Source type badge
                    Text(item.sourceType.localizedName)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(sourceTypeColor.opacity(0.2))
                        .foregroundStyle(sourceTypeColor)
                        .clipShape(Capsule())

                    if item.isSystem {
                        Text(L10n.tr("系统", "System", "Системный"))
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 0)

            // Toggle (or lock for read-only system items)
            if item.sourceType != .loginItem && item.isSystem {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Toggle("", isOn: Binding(
                    get: { item.isEnabled },
                    set: { onToggle($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // Folder button (right of toggle)
            if item.hasConfigFile {
                Button(action: onOpenConfig) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .help(L10n.tr("在 Finder 中查看配置文件", "Show config in Finder", "Показать файл конфигурации в Finder"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private var sourceTypeColor: Color {
        switch item.sourceType {
        case .loginItem:    return .blue
        case .launchAgent:  return .orange
        case .launchDaemon: return .purple
        }
    }
}
