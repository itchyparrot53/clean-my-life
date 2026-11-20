import AppKit
import SwiftUI
import MacCleanKit

// Clean1 shared components (UI_SPEC §2.2, §2.4–2.6, §4.1, §4.3, §4.4).
// Screens are built from these in Phase 4+.

// MARK: - Primary button (§2.6)

/// The 72 pt glass circle. Idle: breathing ring (A6). Working: progress ring
/// (A8) that reads "Stop" on hover when `onStop` is given. Disabled: 45 %.
/// Meta text sits 14 pt to the right, laid out as an overlay so the circle
/// itself stays where the screen puts it.
struct PrimaryButton: View {
    enum Tint {
        /// Default light cyan ring.
        case cyan
        /// Selection-dependent actions (Uninstall with items selected).
        case pink

        var color: Color {
            switch self {
            case .cyan: Color(hex: 0xA8E6FF)
            case .pink: Color(hex: 0xF3A3C7)
            }
        }
    }

    let label: String
    var meta: String?
    var tint: Tint = .cyan
    /// nil = idle; a value = working, shown as a progress ring.
    var progress: Double?
    var isEnabled = true
    var onStop: (() -> Void)?
    let action: () -> Void

    @State private var hovering = false

    private var stopLabel: String { L10n.tr("停止", "Stop", "Стоп") }

    var body: some View {
        Group {
            if let progress {
                let showStop = hovering && onStop != nil
                Button { onStop?() } label: {
                    PrimaryCircle(
                        label: showStop ? stopLabel : "\(Int(progress * 100))%",
                        progress: progress, isEnabled: true, ringColor: tint.color)
                }
                .buttonStyle(PrimaryCircleButtonStyle())
                .disabled(onStop == nil)
                .onHover { hovering = $0 }
            } else {
                Button(action: action) {
                    PrimaryCircle(label: label, progress: nil, isEnabled: isEnabled, ringColor: tint.color)
                }
                .buttonStyle(PrimaryCircleButtonStyle())
                .disabled(!isEnabled)
            }
        }
        .overlay(alignment: .leading) {
            if let meta {
                Text(meta)
                    .font(TypeScale.meta.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: meta)
                    .fixedSize()
                    .offset(x: PrimaryCircle.diameter + 14)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tint == .pink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.map { "\(label), \(Int($0 * 100)) percent" } ?? label)
    }
}

// MARK: - Pills, search, popover surface (§2.2)

/// Cyan pill: "Configure…", "View All 44 Items…". 26 pt tall, radius 6.
struct SecondaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: Surface.pillRadius, style: .continuous)
                    .fill(Surface.secondaryPill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Surface.pillRadius, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                                 startPoint: .top, endPoint: .bottom)))
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.buttonPress, value: configuration.isPressed)
    }
}

/// Ghost pill: "Review Details…". White 14 %, 24 pt tall, radius 6.
struct GhostPillButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: Surface.pillRadius, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.24 : (hovering ? 0.19 : 0.14))))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension ButtonStyle where Self == SecondaryPillButtonStyle {
    static var secondaryPill: SecondaryPillButtonStyle { SecondaryPillButtonStyle() }
}

extension ButtonStyle where Self == GhostPillButtonStyle {
    static var ghostPill: GhostPillButtonStyle { GhostPillButtonStyle() }
}

/// White 12 % search field, 26 pt tall, radius 7, magnifier glyph. ⌘F focuses it.
struct Clean1SearchField: View {
    @Binding var text: String
    var prompt: String = L10n.tr("搜索", "Search", "Поиск")
    var width: CGFloat = 180
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TypeScale.tertiaryText)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(TypeScale.primaryText)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(TypeScale.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("清除", "Clear", "Очистить"))
            }
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: 26)
        .background(Surface.searchFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .background {
            // ⌘F focuses the field (UI_SPEC §11).
            Button("") { focused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Dark popover body: near-black 78 % + material, radius 10, white text.
    func clean1PopoverSurface() -> some View {
        self
            .foregroundStyle(.white.opacity(0.9))
            .background {
                let shape = RoundedRectangle(cornerRadius: Surface.popoverRadius, style: .continuous)
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Surface.popoverFill)
                }
            }
            .environment(\.colorScheme, .dark)
    }

    /// A4: sizes and counts roll digit by digit when they change.
    func numericRoll<V: Equatable>(_ value: V) -> some View {
        self
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy, value: value)
    }
}

// MARK: - Tri-state checkbox (§4.4, A28)

enum CheckState: Equatable {
    case off, on, mixed
}

/// Circular checkbox: filled cyan with a check, a dash for partly selected,
/// or an empty ring. The fill scales from the centre in 0.12 s (A28).
struct TriStateCheckbox: View {
    let state: CheckState
    var size: CGFloat = 16
    let toggle: () -> Void

    private static let fill = Color(hex: 0x5CC8F0)

    var body: some View {
        Button(action: toggle) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(state == .off ? 0.55 : 0), lineWidth: 1.5)
                Circle()
                    .fill(Self.fill)
                    .scaleEffect(state == .off ? 0.01 : 1)
                    .opacity(state == .off ? 0 : 1)
                Image(systemName: state == .mixed ? "minus" : "checkmark")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .opacity(state == .off ? 0 : 1)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: state)
        .accessibilityLabel(L10n.tr("选择", "Select", "Выбрать"))
        .accessibilityValue(state == .on ? L10n.tr("已选择", "Selected", "Выбрано")
                            : state == .mixed ? L10n.tr("部分选择", "Partly selected", "Частично выбрано")
                            : L10n.tr("未选择", "Not selected", "Не выбрано"))
    }
}

// MARK: - Tiles (§2.4)

/// 26 pt circle in the module's top colour at 85 % with a white 14 pt symbol.
struct CategoryTile: View {
    let symbol: String
    var tint: Color
    var size: CGFloat = 26

    /// Threat categories use the same tile in red.
    static func threat(_ symbol: String, size: CGFloat = 26) -> CategoryTile {
        CategoryTile(symbol: symbol, tint: Color(hex: 0xD9534F), size: size)
    }

    var body: some View {
        Circle()
            .fill(tint.opacity(0.85))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.54))
                    .foregroundStyle(.white))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Hero disc (§2.5)

/// 260 pt translucent disc in the module colour, holding the illustration.
/// Until our original art exists it holds a large SF Symbol placeholder.
struct HeroDisc: View {
    let palette: ModulePalette
    let symbol: String
    var diameter: CGFloat = CardLayout.heroDiameter

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [palette.top.lightened(0.2), palette.top],
                    center: .center, startRadius: 0, endRadius: diameter / 2))
                .opacity(0.85)
                .shadow(color: palette.top.opacity(0.4), radius: 40)
            // Inner shadow: a soft dark rim fading inwards.
            Circle()
                .strokeBorder(
                    RadialGradient(colors: [.clear, .black.opacity(0.18)],
                                   center: .center, startRadius: diameter * 0.38, endRadius: diameter / 2),
                    lineWidth: diameter * 0.12)
            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)

            // An empty symbol leaves the disc bare (for overlays like the drawn check).
            Image(systemName: symbol.isEmpty ? "circle" : symbol)
                .opacity(symbol.isEmpty ? 0 : 1)
                .font(.system(size: diameter * 0.58, weight: .regular))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.75)],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

extension Color {
    /// Mixes the colour towards white by `amount` (0…1).
    func lightened(_ amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        func mix(_ c: CGFloat) -> Double { Double(c) + (1 - Double(c)) * amount }
        return Color(.sRGB, red: mix(ns.redComponent), green: mix(ns.greenComponent),
                     blue: mix(ns.blueComponent), opacity: Double(ns.alphaComponent))
    }
}

// MARK: - Metric row (§4.3 B)

/// 20 pt status icon, 17 pt semibold metric, 11 pt grey sub-line.
struct MetricRow: View {
    enum Status { case ok, warning }

    let status: Status
    let metric: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(status == .ok ? Color(hex: 0x5EE6C8) : Color(hex: 0xF8C04E))
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(metric)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(TypeScale.primaryText)
                    .numericRoll(metric)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(TypeScale.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Disk picker (§4.1)

/// A disk or folder the user can point a scan at.
struct ScanLocation: Hashable, Identifiable {
    let url: URL
    let name: String
    let total: Int64?
    let available: Int64?

    var id: URL { url }
    var used: Int64? { total.flatMap { t in available.map { t - $0 } } }

    static var home: ScanLocation {
        let url = FileManager.default.homeDirectoryForCurrentUser
        return ScanLocation(url: url, name: FileManager.default.displayName(atPath: url.path), total: nil, available: nil)
    }

    static func volume(_ url: URL) -> ScanLocation? {
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeIsBrowsableKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsBrowsable != false else { return nil }
        return ScanLocation(
            url: url,
            name: values.volumeLocalizedName ?? url.lastPathComponent,
            total: values.volumeTotalCapacity.map(Int64.init),
            available: values.volumeAvailableCapacityForImportantUsage)
    }

    /// Mounted, browsable volumes, the startup disk first.
    static func volumes() -> [ScanLocation] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap(volume)
    }
}

/// 300 × 44 pt control: drive icon, name + capacity, usage bar, "N GB used",
/// chevrons. Opens a menu of disks, the home folder and "Choose Folder…".
struct DiskPicker: View {
    @Binding var selection: ScanLocation
    @State private var volumes: [ScanLocation] = []

    var body: some View {
        Menu {
            ForEach(volumes) { volume in
                Button(volume.name) { selection = volume }
            }
            Button(ScanLocation.home.name) { selection = .home }
            Divider()
            Button(L10n.tr("选择文件夹…", "Choose Folder…", "Выбрать папку…")) { chooseFolder() }
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { volumes = ScanLocation.volumes() }
        .accessibilityLabel(L10n.tr("扫描位置", "Scan location", "Место сканирования"))
        .accessibilityValue(selection.name)
    }

    private var label: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: selection.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(selection.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let total = selection.total {
                        Text(Self.rounded(total))
                            .font(.system(size: 11))
                            .foregroundStyle(TypeScale.tertiaryText)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                    if let used = selection.used {
                        Text(L10n.tr("已用 \(Self.rounded(used))",
                                     "\(Self.rounded(used)) used",
                                     "Занято \(Self.rounded(used))"))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(TypeScale.tertiaryText)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                if let total = selection.total, let used = selection.used, total > 0 {
                    GeometryReader { proxy in
                        Capsule().fill(Color.white.opacity(0.2))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color(hex: 0x5EE6A0))
                                    .frame(width: proxy.size.width * CGFloat(used) / CGFloat(total))
                            }
                    }
                    .frame(height: 4)
                }
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(TypeScale.secondaryText)
        }
        .foregroundStyle(TypeScale.primaryText)
        .padding(.horizontal, 10)
        .frame(width: 300, height: 44)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Whole gigabytes (one decimal for terabytes) so the name keeps its room.
    static func rounded(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = bytes >= 1_000_000_000_000 ? [.useTB] : [.useGB]
        let text = formatter.string(fromByteCount: bytes)
        guard bytes < 1_000_000_000_000 else { return text }
        let gb = (Double(bytes) / 1_000_000_000).rounded()
        return text.replacingOccurrences(of: #"^[\d.,\s\u00a0]+"#, with: "\(Int(gb)) ", options: .regularExpression)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selection = ScanLocation(url: url, name: FileManager.default.displayName(atPath: url.path),
                                 total: nil, available: nil)
    }
}

// MARK: - Component gallery

/// Every shared component on one card, for checking against the spec.
/// Shown in place of the modules when the app runs with CLEAN1_GALLERY=1.
struct ComponentGallery: View {
    @State private var checks: [CheckState] = [.on, .mixed, .off]
    @State private var search = ""
    @State private var location = ScanLocation.volumes().first ?? .home
    @State private var size: UInt64 = 16_690_000_000
    @State private var progress = 0.42

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 120) {
                    PrimaryButton(label: L10n.tr("扫描", "Scan", "Сканировать"), meta: "One-click care") {}
                    PrimaryButton(label: L10n.tr("卸载", "Uninstall", "Удалить"), meta: "1 application", tint: .pink) {}
                }
                HStack(spacing: 120) {
                    PrimaryButton(label: "Scan", progress: progress, onStop: {}) {}
                    PrimaryButton(label: "Clean", meta: "0 bytes", isEnabled: false) {}
                }
                HStack(spacing: 12) {
                    Button("Configure…") {}.buttonStyle(.secondaryPill)
                    Button("View All 44 Items…") {}.buttonStyle(.secondaryPill)
                    Button("Review Details…") {}.buttonStyle(.ghostPill)
                    Clean1SearchField(text: $search)
                }
                HStack(spacing: 14) {
                    ForEach(checks.indices, id: \.self) { index in
                        TriStateCheckbox(state: checks[index]) {
                            checks[index] = checks[index] == .on ? .off : .on
                        }
                    }
                    CategoryTile(symbol: "folder", tint: ModulePalette.cleanup.top)
                    CategoryTile(symbol: "doc.text", tint: ModulePalette.cleanup.top)
                    CategoryTile.threat("ladybug.fill")
                    Text(FileSizeFormatter.format(size))
                        .font(TypeScale.bigMetric)
                        .numericRoll(size)
                    Button("Roll") {
                        size += 1_234_567_890
                        progress = min(1, progress + 0.13)
                    }
                    .buttonStyle(.ghostPill)
                }
                HStack(alignment: .top, spacing: 30) {
                    HeroDisc(palette: .cleanup, symbol: "internaldrive", diameter: 180)
                    VStack(alignment: .leading, spacing: 14) {
                        MetricRow(status: .ok, metric: "38,489 items checked", detail: "Mode: Balanced")
                        MetricRow(status: .warning, metric: "24 threats found", detail: "Review and remove them")
                        DiskPicker(selection: $location)
                        Text("Popover surface")
                            .font(.system(size: 12))
                            .padding(12)
                            .clean1PopoverSurface()
                    }
                }
            }
            .padding(.vertical, 24)
        }
        .foregroundStyle(.white)
    }
}
