import AppKit
import SwiftUI
import MacCleanKit

public enum SidebarItem: String, CaseIterable, Identifiable {
    // Main
    case smartScan = "智能扫描"

    // Cleanup
    case systemJunk = "系统垃圾"
    case mailAttachments = "邮件附件"
    case trashBins = "废纸篓"

    // Protection
    case malwareRemoval = "恶意软件清理"
    case privacy = "隐私清理"
    case wifiNetworks = "已保存的 Wi-Fi"
    case appPermissions = "权限总览"

    // Performance
    case optimization = "优化"
    case maintenance = "维护"

    // Applications
    case uninstaller = "卸载器"
    case unusedApps = "未使用的应用"
    case extensions = "扩展"
    case updater = "应用更新"

    // Files
    case spaceLens = "空间透视"
    case largeOldFiles = "大文件与旧文件"
    case duplicates = "重复文件"
    case shredder = "文件粉碎"
    case browserExtensions = "浏览器扩展"

    // Cleanup, declared last so the ⌘1…⌘9 shortcuts above keep their digits
    case diskHogs = "开发者磁盘占用"
    // Listed under Cleanup (see `section`); declared last so it doesn't
    // shift the Cmd+1...9 shortcuts of the items above.
    case projectJunk = "项目垃圾"
    // Cleanup (declared last so the ⌘1-⌘9 shortcuts, which follow
    // declaration order, keep pointing at the same modules)
    case cleanHistory = "清理历史"

    // Footer (pinned below the list, not rendered in any section)
    case settings = "设置"

    public var id: String { rawValue }
    public var title: String { L10n.tr(rawValue) }

    /// Stable slug used in `macclean://module/<id>` deep links.
    public var deepLinkID: String {
        switch self {
        case .smartScan: "smart-scan"
        case .systemJunk: "system-junk"
        case .mailAttachments: "mail-attachments"
        case .trashBins: "trash-bins"
        case .malwareRemoval: "malware"
        case .privacy: "privacy"
        case .wifiNetworks: "wifi-networks"
        case .appPermissions: "app-permissions"
        case .optimization: "optimization"
        case .maintenance: "maintenance"
        case .uninstaller: "uninstaller"
        case .extensions: "extensions"
        case .updater: "updater"
        case .spaceLens: "space-lens"
        case .largeOldFiles: "large-old-files"
        case .duplicates: "duplicates"
        case .shredder: "shredder"
        case .browserExtensions: "browser-extensions"
        case .diskHogs: "disk-hogs"
        case .projectJunk: "project-junk"
        case .cleanHistory: "clean-history"
        case .unusedApps: "unused-apps"
        case .settings: "settings"
        }
    }

    public init?(deepLinkID: String) {
        guard let match = Self.allCases.first(where: { $0.deepLinkID == deepLinkID }) else { return nil }
        self = match
    }

    /// Clean1 icon map (UI_SPEC §2.4). Outline symbols; the selected row shows
    /// the `.fill` variant where one exists (Phase 2).
    public var icon: String {
        switch self {
        case .smartScan: "sparkle.magnifyingglass"
        case .systemJunk: "internaldrive"
        case .mailAttachments: "paperclip"
        case .trashBins: "trash"
        case .malwareRemoval: "ladybug"
        case .privacy: "lock"
        case .wifiNetworks: "wifi"
        case .appPermissions: "key"
        case .optimization: "slider.horizontal.3"
        case .maintenance: "gearshape.2"
        case .uninstaller: "shippingbox"
        case .extensions: "puzzlepiece.extension"
        case .updater: "arrow.up.circle"
        case .spaceLens: "chart.pie"
        case .largeOldFiles: "archivebox"
        case .duplicates: "doc.on.doc"
        case .shredder: "scissors"
        case .browserExtensions: "globe"
        case .diskHogs: "externaldrive.badge.xmark"
        case .projectJunk: "hammer"
        case .cleanHistory: "arrow.uturn.backward.circle"
        case .unusedApps: "moon.zzz"
        case .settings: "gearshape"
        }
    }

    public var theme: ModuleTheme {
        switch self {
        case .smartScan: .smartScan
        case .systemJunk, .mailAttachments, .trashBins, .projectJunk, .diskHogs, .cleanHistory: .cleanup
        case .malwareRemoval, .privacy, .browserExtensions, .wifiNetworks, .appPermissions: .protection
        case .optimization, .maintenance: .performance
        case .uninstaller, .unusedApps, .extensions, .updater: .applications
        case .spaceLens, .largeOldFiles, .duplicates, .shredder: .files
        case .settings: .settings
        }
    }

    public var section: SidebarSection {
        switch self {
        case .smartScan: .main
        case .systemJunk, .mailAttachments, .trashBins, .projectJunk, .diskHogs, .cleanHistory: .cleanup
        case .malwareRemoval, .privacy, .browserExtensions, .wifiNetworks, .appPermissions: .protection
        case .optimization, .maintenance: .performance
        case .uninstaller, .unusedApps, .extensions, .updater: .applications
        case .spaceLens, .largeOldFiles, .duplicates, .shredder: .files
        case .settings: .main
        }
    }

    /// Modules jumpable via ⌘1…⌘9: the first nine rows of the sidebar, in
    /// the order they're shown.
    public static var keyboardShortcutItems: [SidebarItem] {
        Array(SidebarSection.allCases.flatMap(\.items).prefix(9))
    }

    /// Mac Sai modules that aren't in the Clean1 sidebar (UI_SPEC §3.1).
    /// They open from the Tools button in the sidebar footer.
    public static var toolItems: [SidebarItem] { [
        .diskHogs, .projectJunk, .unusedApps, .browserExtensions, .wifiNetworks,
    ] }

    /// Footer button that opens Activity (built on Clean History for now).
    public static var activityItem: SidebarItem { .cleanHistory }

    /// The selected row shows the filled symbol where one exists (A3).
    public var selectedIcon: String { SidebarView.filled(icon) }

    /// 1-based digit → sidebar item for ⌘1…⌘9. Returns nil out of range.
    public static func item(forShortcutDigit digit: Int) -> SidebarItem? {
        let items = keyboardShortcutItems
        guard digit >= 1, digit <= items.count else { return nil }
        return items[digit - 1]
    }
}

public enum SidebarSection: String, CaseIterable, Identifiable {
    case main = ""
    case cleanup = "清理"
    case protection = "防护"
    case performance = "性能"
    case applications = "应用"
    case files = "文件"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        // Clean1 calls this group "Speed" (UI_SPEC §3.1).
        case .performance: L10n.tr("加速", "Speed", "Ускорение")
        default: L10n.tr(rawValue)
        }
    }

    /// Rows in sidebar order (UI_SPEC §3.1). Settings, Activity and the
    /// Tools modules live in the footer, never in a section.
    public var items: [SidebarItem] {
        switch self {
        case .main: [.smartScan]
        case .cleanup: [.systemJunk, .mailAttachments, .trashBins]
        case .protection: [.malwareRemoval, .privacy, .appPermissions]
        case .performance: [.optimization, .maintenance]
        case .applications: [.uninstaller, .updater, .extensions]
        case .files: [.spaceLens, .largeOldFiles, .duplicates, .shredder]
        }
    }
}

/// Clean1 sidebar (UI_SPEC §3): a floating translucent panel with custom
/// rows, a sliding selection pill, badges and three modes.
public struct SidebarView: View {
    @Binding var selection: SidebarItem?
    var statuses: [SidebarItem: ModuleStatus]
    var mode: SidebarMode

    @Namespace private var pillSpace
    @State private var hovered: SidebarItem?
    @State private var showTools = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<SidebarItem?>) {
        self.init(selection: selection, statuses: [:], mode: .normal)
    }

    init(selection: Binding<SidebarItem?>, statuses: [SidebarItem: ModuleStatus], mode: SidebarMode) {
        self._selection = selection
        self.statuses = statuses
        self.mode = mode
    }

    private enum Metrics {
        static let rowHeight: CGFloat = 26
        static let headerHeight: CGFloat = 22
        static let headerGap: CGFloat = 10
        static let iconLeading: CGFloat = 12
        static let iconColumn: CGFloat = 18
        static let labelLeading: CGFloat = 38
        static let badgeTrailing: CGFloat = 12
        static let pillInset: CGFloat = 6
        static let padding: CGFloat = 12
        static let fade: CGFloat = 12
    }

    /// A2: the pill slides between rows.
    private var pillAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Surface.sidebarRadius, style: .continuous)
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                        group(section, index: index)
                    }
                }
                .padding(.vertical, Metrics.padding)
            }
            .mask(fadeMask)

            footer
        }
        .background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Surface.sidebarFill)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Surface.sidebarStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        .opacity(mode == .dimmed ? Surface.dimmed : 1)
        .allowsHitTesting(mode != .dimmed)
        .animation(.easeInOut(duration: 0.25), value: mode == .dimmed)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Groups and rows (UI_SPEC §3.2)

    /// A31: in focused mode every group but the active one fades and slides
    /// 8 pt left, staggered; the active header and row stay where they are.
    private func group(_ section: SidebarSection, index: Int) -> some View {
        let isActive = selection.map(section.items.contains) ?? false
        let hidden = mode == .focused && !isActive
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.2)
            : .easeOut(duration: 0.3).delay(Double(index) * 0.015)
        return VStack(alignment: .leading, spacing: 0) {
            if section != .main {
                header(section)
            }
            ForEach(section.items) { item in
                row(item)
                    .opacity(mode == .focused && item != selection ? 0 : 1)
                    .allowsHitTesting(!(mode == .focused && item != selection))
            }
        }
        .opacity(hidden ? 0 : 1)
        .offset(x: hidden && !reduceMotion ? -8 : 0)
        .allowsHitTesting(!hidden)
        .animation(animation, value: mode)
    }

    private func header(_ section: SidebarSection) -> some View {
        Text(section.title)
            .font(TypeScale.sidebarHeader)
            .foregroundStyle(TypeScale.headerText)
            .lineLimit(1)
            .padding(.leading, Metrics.iconLeading)
            .frame(maxWidth: .infinity, minHeight: Metrics.headerHeight, alignment: .leading)
            .padding(.top, Metrics.headerGap)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: SidebarItem) -> some View {
        let isSelected = item == selection
        return Button {
            withAnimation(pillAnimation) { selection = item }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: isSelected ? item.selectedIcon : item.icon)
                    .font(.system(size: 14))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Metrics.iconColumn)
                    .padding(.leading, Metrics.iconLeading)
                Text(item.title)
                    .font(TypeScale.sidebarItem)
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, Metrics.labelLeading - Metrics.iconLeading - Metrics.iconColumn)
                    .layoutPriority(0)
                Spacer(minLength: 6)
                trailing(for: item)
                    .fixedSize()
                    .layoutPriority(1)
                    .padding(.trailing, Metrics.badgeTrailing)
            }
            .foregroundStyle(TypeScale.primaryText)
            .frame(height: Metrics.rowHeight)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Surface.selectionRadius, style: .continuous)
                        .fill(Surface.sidebarSelection)
                        .padding(.horizontal, Metrics.pillInset)
                        .matchedGeometryEffect(id: "selectionPill", in: pillSpace)
                } else if hovered == item {
                    RoundedRectangle(cornerRadius: Surface.selectionRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .padding(.horizontal, Metrics.pillInset)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = item } else if hovered == item { hovered = nil }
        }
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityValue(for: item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Badge, or the A7 working arc while the module is busy.
    @ViewBuilder
    private func trailing(for item: SidebarItem) -> some View {
        let status = statuses[item]
        if status?.stage == .working {
            WorkingArc()
        } else if let badge = status?.badge {
            switch badge {
            case .size(let bytes):
                Text(FileSizeFormatter.format(bytes))
                    .font(TypeScale.sidebarBadge.monospacedDigit())
                    .foregroundStyle(TypeScale.secondaryText)
            case .threats(let count):
                Text(Self.threatsLabel(count))
                    .font(TypeScale.sidebarBadge.weight(.medium))
                    .foregroundStyle(Color(hex: 0xF8C04E))
            case .updates(let count):
                Text("\(count)")
                    .font(TypeScale.sidebarBadge.weight(.semibold).monospacedDigit())
                    .foregroundStyle(TypeScale.primaryText)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(Capsule().fill(Color.white.opacity(0.22)))
            }
        }
    }

    static func threatsLabel(_ count: Int) -> String {
        L10n.tr("\(count) 个威胁",
                count == 1 ? "1 threat" : "\(count) threats",
                "\(count) \(L10n.russianPlural(count, one: "угроза", few: "угрозы", many: "угроз"))")
    }

    private func accessibilityValue(for item: SidebarItem) -> String {
        guard let status = statuses[item] else { return "" }
        if status.stage == .working { return L10n.tr("正在处理", "Working", "Выполняется") }
        switch status.badge {
        case .size(let bytes): return FileSizeFormatter.format(bytes)
        case .threats(let count): return Self.threatsLabel(count)
        case .updates(let count): return L10n.tr("\(count) 个更新", "\(count) updates", "Обновлений: \(count)")
        case nil: return ""
        }
    }

    /// 12 pt fades at the top and bottom of the scrolling list.
    private var fadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: Metrics.fade)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Metrics.fade)
        }
    }

    // MARK: Footer (UI_SPEC §3.1): Tools · Activity · Settings

    private var footer: some View {
        HStack(spacing: 4) {
            footerButton(
                symbol: "square.grid.2x2",
                label: L10n.tr("工具", "Tools", "Инструменты"),
                isSelected: selection.map(SidebarItem.toolItems.contains) ?? false
            ) { showTools.toggle() }
            .popover(isPresented: $showTools, arrowEdge: .top) { toolsMenu }

            footerButton(
                symbol: "clock.arrow.circlepath",
                label: L10n.tr("活动", "Activity", "Активность"),
                isSelected: selection == SidebarItem.activityItem
            ) { select(SidebarItem.activityItem) }

            footerButton(
                symbol: "gearshape",
                label: L10n.tr("设置", "Settings", "Настройки"),
                isSelected: selection == .settings
            ) { select(.settings) }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.pillInset)
        .padding(.top, 6)
        .padding(.bottom, Metrics.padding)
        .overlay(alignment: .top) {
            Rectangle().fill(Surface.hairline).frame(height: 1).padding(.horizontal, Metrics.padding)
        }
    }

    private func footerButton(symbol: String, label: String, isSelected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isSelected ? Self.filled(symbol) : symbol)
                .font(.system(size: 17))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isSelected ? TypeScale.primaryText : TypeScale.secondaryText)
                .frame(width: 34, height: 30)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Surface.selectionRadius, style: .continuous)
                            .fill(Surface.sidebarSelection)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Until the Tools page lands (Phase 9), Tools is a short menu of the
    /// extra modules.
    private var toolsMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SidebarItem.toolItems) { item in
                Button {
                    showTools = false
                    select(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13))
                            .frame(width: 18)
                        Text(item.title)
                            .font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Surface.selectionRadius, style: .continuous)
                            .fill(item == selection ? Color.primary.opacity(0.12) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 230)
    }

    static func filled(_ symbol: String) -> String {
        NSImage(systemSymbolName: symbol + ".fill", accessibilityDescription: nil) == nil ? symbol : symbol + ".fill"
    }

    private func select(_ item: SidebarItem) {
        withAnimation(pillAnimation) { selection = item }
    }
}

/// A7: 10 pt arc, one turn per second.
private struct WorkingArc: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(TypeScale.secondaryText, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
            .accessibilityHidden(true)
    }
}
