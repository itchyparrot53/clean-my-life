import SwiftUI
import MacCleanKit

// Clean1 top bar (UI_SPEC §1.1, §1.3, §2.3). Modules describe what goes in it
// with preferences; the shell draws it on the card. Hidden modules have their
// preferences cleared by the shell, so only the selected module is shown.

/// What a module is doing, as far as the status button cares (UI_SPEC §1.3).
enum ModuleStage: Equatable, Sendable {
    /// Intro / nothing running: small circle, teal dot.
    case idle
    /// Scanning or cleaning: small circle, animated dot.
    case working
    /// Results, review or done: grows into the Tips pill.
    case results
    /// Something needs the user (threats, missing access): amber Tips pill.
    case attention

    var showsTipsPill: Bool { self == .results || self == .attention }
}

struct TopBarBack {
    let label: String
    let action: () -> Void
}

struct TopBarAccessory: Identifiable {
    let id: String
    let view: AnyView
}

struct TopBarContent {
    var title: String?
    var back: TopBarBack?
    var search: Binding<String>?
    var searchPrompt: String = ""
    var accessories: [TopBarAccessory] = []
    var stage: ModuleStage?
}

struct TopBarPreferenceKey: PreferenceKey {
    static var defaultValue: TopBarContent { TopBarContent() }

    static func reduce(value: inout TopBarContent, nextValue: () -> TopBarContent) {
        let next = nextValue()
        if let title = next.title { value.title = title }
        if let back = next.back { value.back = back }
        if let search = next.search {
            value.search = search
            value.searchPrompt = next.searchPrompt
        }
        value.accessories += next.accessories
        if let stage = next.stage { value.stage = stage }
    }
}

extension View {
    /// Centred title in the top bar (review and list screens).
    func topBarTitle(_ title: String?) -> some View {
        transformPreference(TopBarPreferenceKey.self) { $0.title = title ?? $0.title }
    }

    /// "‹ Back" label at the top bar's leading edge.
    func topBarBack(_ label: String, action: @escaping () -> Void) -> some View {
        transformPreference(TopBarPreferenceKey.self) { $0.back = TopBarBack(label: label, action: action) }
    }

    /// Fills the top bar's search slot.
    func topBarSearch(text: Binding<String>, prompt: String) -> some View {
        transformPreference(TopBarPreferenceKey.self) {
            $0.search = text
            $0.searchPrompt = prompt
        }
    }

    /// Extra control shown just before the status button.
    func topBarAccessory<Accessory: View>(id: String, @ViewBuilder _ accessory: () -> Accessory) -> some View {
        let item = TopBarAccessory(id: id, view: AnyView(accessory()))
        return transformPreference(TopBarPreferenceKey.self) { $0.accessories.append(item) }
    }

    /// Tells the status button and the sidebar what this module is doing.
    func moduleStage(_ stage: ModuleStage) -> some View {
        transformPreference(TopBarPreferenceKey.self) { $0.stage = stage }
            .transformPreference(ModuleStatusKey.self) { $0.stage = stage }
    }

    /// The badge on this module's sidebar row (UI_SPEC §3.2). An outer call
    /// overrides an inner one, so a module can replace its container's.
    func sidebarBadge(_ badge: SidebarBadge?) -> some View {
        transformPreference(ModuleStatusKey.self) { $0.badge = badge }
    }

    /// Asks the sidebar to dim or focus while this module is showing (UI_SPEC §3.3).
    func sidebarMode(_ mode: SidebarMode) -> some View {
        transformPreference(ModuleStatusKey.self) { $0.mode = mode }
    }
}

// MARK: Sidebar status

enum SidebarBadge: Equatable, Sendable {
    /// Found size, e.g. "27.09 GB".
    case size(UInt64)
    /// Threat count, shown in amber.
    case threats(Int)
    /// Available updates.
    case updates(Int)
}

enum SidebarMode: Equatable, Sendable {
    case normal
    /// Checkup review sheet open: whole panel at 35 %, not interactive.
    case dimmed
    /// Inside a list view: only the active group header and item stay.
    case focused
}

/// What a module tells the sidebar about itself.
struct ModuleStatus: Equatable, Sendable {
    var stage: ModuleStage?
    var badge: SidebarBadge?
    var mode: SidebarMode?
}

struct ModuleStatusKey: PreferenceKey {
    static var defaultValue: ModuleStatus { ModuleStatus() }

    static func reduce(value: inout ModuleStatus, nextValue: () -> ModuleStatus) {
        let next = nextValue()
        if let stage = next.stage { value.stage = stage }
        if let badge = next.badge { value.badge = badge }
        if let mode = next.mode { value.mode = mode }
    }
}

/// Latest status per module, collected by the shell for the sidebar.
@MainActor
@Observable
final class SidebarStatusStore {
    private(set) var statuses: [SidebarItem: ModuleStatus] = [:]

    func set(_ status: ModuleStatus, for item: SidebarItem) {
        if statuses[item] != status { statuses[item] = status }
    }
}

struct TopBar: View {
    let item: SidebarItem
    let content: TopBarContent

    var body: some View {
        HStack(spacing: 12) {
            if let back = content.back {
                Button(action: back.action) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text(back.label)
                    }
                    .font(TypeScale.topBarBack)
                    .foregroundStyle(TypeScale.secondaryText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if let search = content.search {
                Clean1SearchField(text: search, prompt: content.searchPrompt)
            }
            ForEach(content.accessories) { accessory in
                accessory.view
            }
            StatusButton(item: item, stage: content.stage ?? .idle)
        }
        .frame(height: CardLayout.topBarHeight)
        .overlay {
            if let title = content.title {
                Text(title)
                    .font(TypeScale.topBarTitle)
                    .foregroundStyle(TypeScale.primaryText)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// 22 pt circle with a status dot; grows into the "Tips" pill once a module
/// has results to talk about (UI_SPEC §1.3).
struct StatusButton: View {
    let item: SidebarItem
    let stage: ModuleStage
    @State private var showTips = false

    private var dotColor: Color {
        stage == .attention ? Color(hex: 0xF8C04E) : Color(hex: 0x5EE6C8)
    }

    var body: some View {
        Button {
            showTips.toggle()
        } label: {
            HStack(spacing: 6) {
                StatusDot(color: dotColor, isWorking: stage == .working)
                if stage.showsTipsPill {
                    Text(L10n.tr("提示", "Tips", "Советы"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TypeScale.primaryText)
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, stage.showsTipsPill ? 10 : 0)
            .frame(minWidth: stage.showsTipsPill ? 0 : 22)
            .frame(height: stage.showsTipsPill ? 26 : 22)
            .background(
                Capsule().fill(Color.white.opacity(stage.showsTipsPill ? 0.15 : 0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: stage.showsTipsPill)
        .help(L10n.tr("提示", "Tips", "Советы"))
        .accessibilityLabel(L10n.tr("提示", "Tips", "Советы"))
        .popover(isPresented: $showTips, arrowEdge: .bottom) {
            TipsPopover(item: item, stage: stage)
        }
    }
}

private struct StatusDot: View {
    let color: Color
    let isWorking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.9), radius: 4)
            .scaleEffect(isWorking && pulse && !reduceMotion ? 1.35 : 1)
            .opacity(isWorking && pulse ? 0.55 : 1)
            .onAppear { pulse = isWorking }
            .onChange(of: isWorking) { _, working in pulse = working }
            .animation(isWorking ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default,
                       value: pulse)
    }
}

/// Our replacement for the branded assistant: a few plain tips per area.
private struct TipsPopover: View {
    let item: SidebarItem
    let stage: ModuleStage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("提示", "Tips", "Советы"))
                .font(.system(size: 13, weight: .semibold))
            ForEach(Tips.for(item), id: \.self) { tip in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: 0xF8C04E))
                    Text(tip)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}

enum Tips {
    static func `for`(_ item: SidebarItem) -> [String] {
        switch item.theme {
        case .smartScan:
            [L10n.tr("每周运行一次体检就足以保持整洁。", "Running a Checkup once a week is plenty to stay tidy.", "Достаточно запускать проверку раз в неделю."),
             L10n.tr("清理前可以逐项查看并取消勾选。", "Open the details to untick anything before you clean.", "Откройте подробности, чтобы снять отметки перед очисткой.")]
        case .cleanup:
            [L10n.tr("缓存会自动重建，删除是安全的。", "Caches rebuild themselves, so clearing them is safe.", "Кэши восстанавливаются сами, их удаление безопасно."),
             L10n.tr("清理后可在清理历史中撤销。", "Changed your mind? Clean History can put things back.", "Передумали? История очистки вернёт файлы.")]
        case .protection:
            [L10n.tr("只从可信来源安装应用。", "Install apps only from sources you trust.", "Устанавливайте приложения только из надёжных источников."),
             L10n.tr("定期检查哪些应用能访问摄像头和麦克风。", "Check now and then which apps can use your camera and mic.", "Время от времени проверяйте доступ к камере и микрофону.")]
        case .performance:
            [L10n.tr("登录项越少，开机越快。", "Fewer login items means a faster start.", "Меньше объектов входа — быстрее запуск."),
             L10n.tr("维护任务每月运行一次即可。", "Maintenance tasks only need running about once a month.", "Обслуживание достаточно запускать раз в месяц.")]
        case .applications:
            [L10n.tr("卸载时一并移除残留文件。", "Uninstall here to take the leftovers with the app.", "Удаляйте здесь, чтобы убрать и остатки приложения."),
             L10n.tr("长期未用的应用可以安全删除。", "Apps you haven't opened in months are safe to let go.", "Приложения, не открывавшиеся месяцами, можно удалить.")]
        case .files:
            [L10n.tr("大文件通常藏在下载文件夹里。", "Big files tend to hide in Downloads.", "Большие файлы часто прячутся в Загрузках."),
             L10n.tr("删除前用空格键快速预览。", "Press Space to preview a file before removing it.", "Нажмите пробел, чтобы просмотреть файл перед удалением.")]
        case .settings:
            [L10n.tr("在忽略列表中添加不想被扫描的文件夹。", "Add folders to the Ignore List to keep them out of scans.", "Добавьте папки в список исключений, чтобы не сканировать их.")]
        }
    }
}
