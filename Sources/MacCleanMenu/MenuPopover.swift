import AppKit
import SwiftUI
import MacCleanKit

// Clean1 menu bar popover (UI_SPEC §6): two panels side by side on the
// deepened Checkup gradient. Left = storage; right = tips and overview.

extension Color {
    init(menuHex hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

enum MenuStyle {
    static let top = Color(menuHex: 0x4A3A7A)
    static let bottom = Color(menuHex: 0x2B2552)
    static let card = Color.white.opacity(0.08)
    static let teal = Color(menuHex: 0x3DE0C8)
    static let coral = Color(menuHex: 0xFF6F7D)
    static let amber = Color(menuHex: 0xF8C04E)
    static let periwinkle = Color(menuHex: 0x8C9BFF)
    static let mint = Color(menuHex: 0x5EE6A0)
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.45)
}

struct MenuPopover: View {
    let model: MenuStatsModel
    @Namespace private var expand
    @State private var expanded: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            storagePanel
            overviewPanel
        }
        .padding(12)
        .background(
            LinearGradient(colors: [MenuStyle.top, MenuStyle.bottom], startPoint: .top, endPoint: .bottom))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Left panel: storage

    private var storagePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(volumeName).font(.system(size: 15, weight: .semibold))
            if let s = model.stats {
                HStack(spacing: 14) {
                    StorageDonut(total: s.diskTotal, free: s.diskFree)
                        .frame(width: 132, height: 132)
                    VStack(alignment: .leading, spacing: 6) {
                        legend(color: MenuStyle.coral, name: "Used", value: s.diskTotal - s.diskFree)
                        legend(color: MenuStyle.teal, name: "Free", value: s.diskFree)
                        if let trash = model.trashBytes, trash > 0 {
                            legend(color: MenuStyle.amber, name: "Trash", value: trash)
                        }
                    }
                }
                HStack(spacing: 8) {
                    infoCard(symbol: "heart", title: healthTitle(s), detail: healthDetail(s)) {
                        TipAction.open(moduleID: "maintenance")
                    }
                    infoCard(symbol: "thermometer.medium", title: temperature(s), detail: temperatureDetail(s), action: nil)
                }
                componentsRow
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 200)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 300, height: 420, alignment: .topLeading)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var volumeName: String {
        let root = URL(filePath: "/")
        return (try? root.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? "Macintosh HD"
    }

    private func legend(color: Color, name: String, value: UInt64) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).font(.system(size: 11))
            Spacer(minLength: 4)
            Text(FileSizeFormatter.format(value)).font(.system(size: 11).monospacedDigit()).foregroundStyle(MenuStyle.secondary)
                .lineLimit(1).fixedSize()
        }
    }

    private func infoCard(symbol: String, title: String, detail: String, action: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(title).font(.system(size: 14, weight: .semibold)).monospacedDigit()
            }
            Text(detail).font(.system(size: 10)).foregroundStyle(MenuStyle.secondary).lineLimit(2)
            if let action {
                Button("Details ↗", action: action).buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(MenuStyle.teal)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(MenuStyle.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func healthTitle(_ s: SystemStatsCollector.SystemStats) -> String {
        if let health = s.batteryHealth { return "\(Int((health * 100).rounded())) %" }
        return s.diskTotal > 0 && s.diskFree > 10 * 1024 * 1024 * 1024 ? "Good" : "Check"
    }

    private func healthDetail(_ s: SystemStatsCollector.SystemStats) -> String {
        if s.batteryHealth != nil {
            return "Battery health" + (s.batteryCycleCount.map { " · \($0) cycles" } ?? "")
        }
        return "Disk and memory look fine"
    }

    private func temperature(_ s: SystemStatsCollector.SystemStats) -> String {
        if let t = s.cpuTemperature ?? s.batteryTemperature { return "\(Int(t.rounded())) °C" }
        return "—"
    }

    private func temperatureDetail(_ s: SystemStatsCollector.SystemStats) -> String {
        guard let t = s.cpuTemperature ?? s.batteryTemperature else { return "Not reported on this Mac" }
        return t < 70 ? "Running cool" : t < 85 ? "Warm" : "Hot: close heavy apps"
    }

    /// Connected drives, then the Trash with its "Empty" shortcut.
    private var componentsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Components").font(.system(size: 11, weight: .semibold)).foregroundStyle(MenuStyle.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let devices = model.devices {
                        ForEach(devices.externalVolumes) { volume in
                            componentCard(symbol: "externaldrive", name: volume.name,
                                          used: volume.totalBytes - volume.freeBytes, total: volume.totalBytes,
                                          action: nil)
                        }
                    }
                    componentCard(symbol: "trash", name: "Trash", used: model.trashBytes ?? 0,
                                  total: max(model.trashBytes ?? 0, 1), action: ("Empty", { TipAction.open(moduleID: "trash-bins") }))
                }
            }
        }
    }

    private func componentCard(symbol: String, name: String, used: UInt64, total: UInt64,
                               action: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            Text(FileSizeFormatter.format(used)).font(.system(size: 10).monospacedDigit()).foregroundStyle(MenuStyle.secondary)
            GeometryReader { proxy in
                Capsule().fill(Color.white.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule().fill(MenuStyle.teal).frame(width: proxy.size.width * min(1, CGFloat(used) / CGFloat(max(total, 1))))
                    }
            }
            .frame(height: 3)
            if let action {
                Button(action.0, action: action.1).buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(MenuStyle.amber)
            }
        }
        .padding(8)
        .frame(width: 118, alignment: .leading)
        .background(MenuStyle.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Right panel: overview

    private var overviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.hasAlert { alertBanner }
            if !model.tips.isEmpty { tipsCarousel }
            protectionCard
            if let s = model.stats {
                if let key = expanded {
                    expandedCard(key, s)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        gridCard("disk", s)
                        gridCard("memory", s)
                        gridCard("battery", s)
                        gridCard("cpu", s)
                    }
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(14)
        .frame(width: 300, height: 420, alignment: .topLeading)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: expanded)
    }

    private var alertBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(MenuStyle.amber)
            Text(alertText).font(.system(size: 11)).lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MenuStyle.amber.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var alertText: String {
        if let p = model.protection, p.threatsFound > 0 { return "\(p.threatsFound) threat\(p.threatsFound == 1 ? "" : "s") found. Open Malware Removal to review." }
        return "Your startup disk is nearly full."
    }

    /// Horizontally scrolling tip cards with an amber action (UI_SPEC §6).
    private var tipsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.tips, id: \.id) { tip in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: tip.symbol).font(.system(size: 14))
                            Spacer()
                            Button { model.dismissTip(id: tip.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain).foregroundStyle(MenuStyle.tertiary)
                        }
                        Text(tip.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                        Spacer(minLength: 0)
                        Button {
                            TipAction.open(moduleID: MenuTipRouting.moduleID(forTipID: tip.id))
                        } label: {
                            Text(tip.estimatedSavings > 0 ? "Free \(FileSizeFormatter.format(tip.estimatedSavings))" : "Open")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.8))
                                .padding(.horizontal, 8).frame(height: 20)
                                .background(MenuStyle.amber, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .frame(width: 140, height: 112, alignment: .topLeading)
                    .background(MenuStyle.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var protectionCard: some View {
        let p = model.protection
        let clean = (p?.threatsFound ?? 0) == 0
        return HStack(spacing: 10) {
            Image(systemName: clean ? "checkmark.shield" : "exclamationmark.shield")
                .font(.system(size: 20))
                .foregroundStyle(clean ? MenuStyle.mint : MenuStyle.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(p == nil ? "Not scanned yet" : clean ? "Protected" : "\(p!.threatsFound) threats found")
                    .font(.system(size: 13, weight: .semibold))
                Text(p.map { "Last scan " + $0.lastScanDate.formatted(.relative(presentation: .named)) } ?? "Run a malware scan to check")
                    .font(.system(size: 10)).foregroundStyle(MenuStyle.secondary)
            }
            Spacer()
            Button("Check now") { TipAction.open(moduleID: "malware") }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(MenuStyle.teal)
        }
        .padding(10)
        .background(MenuStyle.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // 2×2 grid; a card expands to a detail view with a bigger graph (A27).

    private func gridInfo(_ key: String, _ s: SystemStatsCollector.SystemStats)
        -> (symbol: String, title: String, value: String, detail: String, history: [Double]?, action: (String, String)?) {
        switch key {
        case "disk":
            return ("internaldrive", "Disk", FileSizeFormatter.format(s.diskFree), "free of \(FileSizeFormatter.format(s.diskTotal))",
                    nil, ("Free Up", "system-junk"))
        case "memory":
            let available = s.memoryTotal > s.memoryUsed ? s.memoryTotal - s.memoryUsed : 0
            return ("memorychip", "Memory", FileSizeFormatter.format(available), "available · pressure \(Int((s.memoryPressure * 100).rounded())) %",
                    model.memoryHistory, ("Free Up", "maintenance"))
        case "battery":
            if let level = s.batteryLevel {
                return (s.batteryIsCharging ? "battery.100.bolt" : "battery.75", "Battery", "\(Int((level * 100).rounded())) %",
                        s.batteryIsCharging ? "Charging" : "On battery", nil, nil)
            }
            return ("powerplug", "Power", "Mains", "No battery", nil, nil)
        default:
            return ("cpu", "CPU", "\(Int((s.cpuUsage * 100).rounded())) %",
                    s.cpuTemperature.map { "\(Int($0.rounded())) °C" } ?? "load", model.cpuHistory, nil)
        }
    }

    private func gridCard(_ key: String, _ s: SystemStatsCollector.SystemStats) -> some View {
        let info = gridInfo(key, s)
        return Button { expanded = key } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: info.symbol).font(.system(size: 11))
                    Text(info.title).font(.system(size: 10)).foregroundStyle(MenuStyle.secondary)
                        .lineLimit(1).fixedSize()
                    Spacer(minLength: 4)
                    if let history = info.history { Sparkline(values: history).frame(width: 36, height: 14) }
                }
                Text(info.value).font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText()).animation(.snappy, value: info.value)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            .background(MenuStyle.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .matchedGeometryEffect(id: key, in: expand)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func expandedCard(_ key: String, _ s: SystemStatsCollector.SystemStats) -> some View {
        let info = gridInfo(key, s)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: info.symbol)
                Text(info.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { expanded = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(MenuStyle.tertiary)
            }
            Text(info.value).font(.system(size: 26, weight: .light).monospacedDigit())
            Text(info.detail).font(.system(size: 11)).foregroundStyle(MenuStyle.secondary)
            if let history = info.history {
                Sparkline(values: history).frame(height: 44)
            }
            if let action = info.action {
                Button(action.0) { TipAction.open(moduleID: action.1) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.black.opacity(0.8))
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(MenuStyle.amber, in: Capsule())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(MenuStyle.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .matchedGeometryEffect(id: key, in: expand)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button { TipAction.open() } label: {
                HStack(spacing: 6) {
                    Image(nsImage: StatusGlyph.image(working: false, alert: false, size: 14))
                        .renderingMode(.template)
                    Text("Open \(MCConstants.appName)").font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            Menu {
                Button("Settings…") { TipAction.open(moduleID: "settings") }
                Button("Screen Cleaning Mode") { ScreenCleaning.shared.start() }
                Divider()
                Button("Quit Menu Bar Monitor") {
                    MenuBarKeepAlive.setUserQuit(true, defaults: SharedAppState.defaults)
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape").frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
    }
}

// MARK: - Pieces

/// Donut: used vs free, centre shows the free space (UI_SPEC §6).
private struct StorageDonut: View {
    let total: UInt64
    let free: UInt64
    @State private var grow: CGFloat = 0

    var body: some View {
        let used = total > 0 ? CGFloat(total - free) / CGFloat(total) : 0
        ZStack {
            Circle().stroke(MenuStyle.teal.opacity(0.85), lineWidth: 16)
            Circle().trim(from: 0, to: used * grow)
                .stroke(MenuStyle.coral, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(FileSizeFormatter.format(free)).font(.system(size: 20, weight: .light).monospacedDigit())
                Text("free of \(FileSizeFormatter.format(total))").font(.system(size: 9)).foregroundStyle(MenuStyle.secondary)
            }
        }
        .padding(8)
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { grow = 1 } }
    }
}

/// A24: a small line graph that slides left as new samples arrive.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let points = values.suffix(40)
            let count = max(points.count - 1, 1)
            Path { path in
                for (index, value) in points.enumerated() {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(count)
                    let y = proxy.size.height * (1 - CGFloat(min(max(value, 0), 1)))
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(MenuStyle.teal, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .animation(.linear(duration: 0.4), value: values)
        }
    }
}

/// The status item glyph: a pebble with a sparkle, a ring while the main
/// app is working, and an amber dot when something needs attention.
/// Placeholder until the real icon is drawn.
enum StatusGlyph {
    static func image(working: Bool, alert: Bool, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = rect.insetBy(dx: size * 0.12, dy: size * 0.2)
            let pebble = NSBezierPath(ovalIn: inset.offsetBy(dx: 0, dy: -size * 0.04))
            pebble.lineWidth = size * 0.09
            NSColor.black.setStroke()
            pebble.stroke()
            // Sparkle on top.
            let c = NSPoint(x: rect.midX + size * 0.12, y: rect.midY + size * 0.04)
            let r = size * 0.16
            let star = NSBezierPath()
            star.move(to: NSPoint(x: c.x, y: c.y + r))
            star.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: NSPoint(x: c.x + r * 0.15, y: c.y + r * 0.15), controlPoint2: NSPoint(x: c.x + r * 0.15, y: c.y + r * 0.15))
            star.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: NSPoint(x: c.x + r * 0.15, y: c.y - r * 0.15), controlPoint2: NSPoint(x: c.x + r * 0.15, y: c.y - r * 0.15))
            star.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: NSPoint(x: c.x - r * 0.15, y: c.y - r * 0.15), controlPoint2: NSPoint(x: c.x - r * 0.15, y: c.y - r * 0.15))
            star.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: NSPoint(x: c.x - r * 0.15, y: c.y + r * 0.15), controlPoint2: NSPoint(x: c.x - r * 0.15, y: c.y + r * 0.15))
            NSColor.black.setFill()
            star.fill()
            if working {
                let ring = NSBezierPath()
                ring.appendArc(withCenter: NSPoint(x: rect.maxX - size * 0.18, y: rect.minY + size * 0.18),
                               radius: size * 0.14, startAngle: 90, endAngle: 360)
                ring.lineWidth = size * 0.07
                ring.stroke()
            }
            if alert {
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - size * 0.3, y: rect.maxY - size * 0.3,
                                            width: size * 0.28, height: size * 0.28)).fill()
            }
            return true
        }
        // Template so the menu bar tints it; the alert dot shows as a
        // filled dot (macOS doesn't allow colour in template glyphs).
        image.isTemplate = true
        image.accessibilityDescription = MCConstants.appName
        return image
    }
}
