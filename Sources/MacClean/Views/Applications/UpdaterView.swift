import SwiftUI
import AppKit
import MacCleanKit

struct UpdaterView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var updates: [AppUpdateChecker.AppUpdate] = []
    @State private var isChecking = false
    @State private var hasChecked = false
    @State private var apps: [AppInfo] = []
    /// Update rows currently mid-action — drives the per-row spinner + disable.
    @State private var updatingIDs: Set<UUID> = []

    private let discovery = AppDiscovery()
    private let checker = AppUpdateChecker()

    @State private var showList = false

    var body: some View {
        IntroGate(item: .updater, primaryMeta: hasChecked ? "\(updates.count) updates" : nil, focusSidebar: true,
                  showContent: $showList) {
            legacyContent
        }
        .onChange(of: showList) { _, open in
            if open && !hasChecked && !isChecking { checkUpdates() }
        }
        .moduleStage(isChecking ? .working : (updates.isEmpty ? .idle : .results))
        .sidebarBadge(updates.isEmpty ? nil : .updates(updates.count))
    }

    // MARK: Clean1 list (UI_SPEC §5.12)

    @State private var sourceFilter = "all"
    @State private var expanded: UUID?
    @State private var unchecked: Set<UUID> = []
    @AppStorage("clean1.updater.ignored") private var ignoredRaw = ""

    /// "bundleID@version" for each skipped update.
    private var ignored: Set<String> { Set(ignoredRaw.split(separator: "|").map(String.init)) }
    private func key(_ update: AppUpdateChecker.AppUpdate) -> String {
        update.app.bundleIdentifier + "@" + (update.availableVersion ?? "")
    }
    private func isAppStore(_ update: AppUpdateChecker.AppUpdate) -> Bool {
        UpdaterActions.isMacAppStoreApp(at: update.app.path)
    }

    private var visible: [AppUpdateChecker.AppUpdate] {
        updates.filter { update in
            let skipped = ignored.contains(key(update))
            switch sourceFilter {
            case "ignored": return skipped
            case "sparkle": return !skipped && !isAppStore(update)
            case "appstore": return !skipped && isAppStore(update)
            default: return !skipped
            }
        }
    }

    private var toUpdate: [AppUpdateChecker.AppUpdate] {
        updates.filter { !ignored.contains(key($0)) && !unchecked.contains($0.id) }
    }

    private var legacyContent: some View {
        ListFirstTemplate(
            groups: [FilterGroup(id: "sources", items: [
                FilterItem(id: "all", title: L10n.tr("全部", "All Updates", "Все"),
                           count: updates.filter { !ignored.contains(key($0)) }.count),
                FilterItem(id: "sparkle", title: "Sparkle",
                           count: updates.filter { !ignored.contains(key($0)) && !isAppStore($0) }.count),
                FilterItem(id: "appstore", title: "App Store",
                           count: updates.filter { !ignored.contains(key($0)) && isAppStore($0) }.count),
                FilterItem(id: "ignored", title: L10n.tr("已忽略", "Ignored", "Пропущенные"),
                           count: updates.filter { ignored.contains(key($0)) }.count),
            ])],
            selectedFilter: $sourceFilter,
            title: sourceFilter == "ignored" ? L10n.tr("已忽略", "Ignored", "Пропущенные") : L10n.tr("更新", "Updates", "Обновления"),
            description: "Updates come from each app's own feed. The Update button opens the download, or the App Store.",
            trailingHeader: {
                Button { checkUpdates() } label: {
                    Label(L10n.tr("重新检查", "Check Again", "Проверить снова"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.ghostPill)
                .disabled(isChecking)
            },
            list: {
                Group {
                    if isChecking {
                        VStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(L10n.tr("正在检查更新…", "Checking for updates…", "Проверка обновлений…"))
                                .font(.system(size: 12)).foregroundStyle(TypeScale.secondaryText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if visible.isEmpty {
                        Text(hasChecked ? L10n.tr("所有应用均为最新", "Everything here is up to date.", "Все приложения обновлены") : "")
                            .font(.system(size: 13)).foregroundStyle(TypeScale.secondaryText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(visible) { update in updateRow(update) }
                            }
                        }
                    }
                }
                .cardList()
            })
        .overlay {
            PrimarySlot {
                PrimaryButton(label: L10n.tr("更新", "Update", "Обновить"),
                              meta: toUpdate.isEmpty ? nil : "\(toUpdate.count) app\(toUpdate.count == 1 ? "" : "s")",
                              isEnabled: !toUpdate.isEmpty && sourceFilter != "ignored") {
                    toUpdate.forEach(startUpdate)
                }
            }
        }
    }

    private func updateRow(_ update: AppUpdateChecker.AppUpdate) -> some View {
        let isOn = !unchecked.contains(update.id)
        let isOpen = expanded == update.id
        let skipped = ignored.contains(key(update))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                TriStateCheckbox(state: isOn ? .on : .off) {
                    if isOn { unchecked.insert(update.id) } else { unchecked.remove(update.id) }
                }
                .disabled(skipped)
                Image(nsImage: NSWorkspace.shared.icon(forFile: update.app.path.path(percentEncoded: false)))
                    .resizable().frame(width: 22, height: 22)
                Text(update.app.name).font(TypeScale.row).lineLimit(1)
                Text("\(update.currentVersion) → \(update.availableVersion ?? "?")")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(TypeScale.secondaryText)
                Spacer(minLength: 6)
                Text(isAppStore(update) ? "App Store" : "Sparkle")
                    .font(.system(size: 10))
                    .foregroundStyle(TypeScale.tertiaryText)
                if updatingIDs.contains(update.id) {
                    ProgressView().controlSize(.small).frame(width: 60)
                } else if isAppStore(update) {
                    Button(L10n.tr("打开 App Store", "Open App Store", "Открыть App Store")) { startUpdate(update) }
                        .buttonStyle(.ghostPill)
                } else {
                    Button(L10n.tr("更新", "Update", "Обновить")) { startUpdate(update) }
                        .buttonStyle(.ghostPill)
                }
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { expanded = isOpen ? nil : update.id }
                } label: {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(TypeScale.tertiaryText)
                .accessibilityLabel(L10n.tr("发行说明", "Release notes", "Что нового"))
            }
            .frame(height: 34)
            .contextMenu {
                if skipped {
                    Button(L10n.tr("取消忽略", "Stop Ignoring", "Не пропускать")) { setIgnored(update, false) }
                } else {
                    Button(L10n.tr("忽略此版本", "Ignore This Version", "Пропустить версию")) { setIgnored(update, true) }
                }
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    if let notes = update.releaseNotes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 12))
                            .foregroundStyle(TypeScale.secondaryText)
                            .textSelection(.enabled)
                            .lineLimit(14)
                    } else {
                        Text(L10n.tr("此更新没有附带说明。", "This update didn't come with notes.", "Описание не приложено."))
                            .font(.system(size: 12))
                            .foregroundStyle(TypeScale.tertiaryText)
                    }
                    if let link = update.releaseNotesURL, UpdaterActions.isSafeDownloadURL(link) {
                        Link(L10n.tr("完整说明…", "Full release notes…", "Подробнее…"), destination: link)
                            .font(.system(size: 12, weight: .medium))
                    }
                    Button(skipped ? L10n.tr("取消忽略", "Stop Ignoring", "Не пропускать")
                                   : L10n.tr("忽略此版本", "Ignore This Version", "Пропустить версию")) {
                        setIgnored(update, !skipped)
                    }
                    .buttonStyle(.ghostPill)
                }
                .padding(.leading, 58)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .foregroundStyle(TypeScale.primaryText)
        .padding(.horizontal, 10)
    }

    private func setIgnored(_ update: AppUpdateChecker.AppUpdate, _ on: Bool) {
        var set = ignored
        if on { set.insert(key(update)) } else { set.remove(key(update)) }
        ignoredRaw = set.sorted().joined(separator: "|")
    }

    private func checkUpdates() {
        isChecking = true
        Task {
            apps = await discovery.discoverApps()
            updates = await checker.checkForUpdates(apps: apps)
            isChecking = false
            hasChecked = true
        }
    }

    /// Flip the row to a spinner + disable it the instant Update is tapped,
    /// fire the action, then hold the indicator briefly so the user clearly
    /// sees that the tap registered and something is happening.
    private func startUpdate(_ update: AppUpdateChecker.AppUpdate) {
        guard !updatingIDs.contains(update.id) else { return }
        updatingIDs.insert(update.id)
        Task {
            UpdaterActions.perform(update)
            try? await Task.sleep(for: .milliseconds(1200))
            updatingIDs.remove(update.id)
        }
    }
}
