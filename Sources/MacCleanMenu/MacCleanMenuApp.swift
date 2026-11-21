import SwiftUI
import AppKit
import MacCleanKit

@main
struct MacCleanMenuApp: App {
    init() {
        AppLanguage.registerDefault(.system)
        // Single-instance enforcement. macOS does NOT auto-deduplicate
        // LSUIElement apps by bundle id the way it does for regular apps,
        // and we have two launch paths (SMAppService + NSWorkspace). Keep
        // the oldest copy; never `exit(0)` from every sibling — that took
        // the extra down when both copies started at once (issue #138).
        // Only enforce when we have a real bundle id (i.e. running from
        // the .app). Under `swift run` the bare executable has no bundle
        // id, and matching against other nil-bundle processes would make
        // the dev build exit immediately.
        if let myBundleID = Bundle.main.bundleIdentifier {
            let myPID = ProcessInfo.processInfo.processIdentifier
            let running = NSWorkspace.shared.runningApplications
            let me = running.first { $0.processIdentifier == myPID }
            let siblings = running.compactMap { app -> MenuBarInstance? in
                guard app.bundleIdentifier == myBundleID,
                      app.processIdentifier != myPID else { return nil }
                return MenuBarInstance(pid: app.processIdentifier, launchDate: app.launchDate)
            }
            // Keep-one, never both-exit. The old any-sibling check killed
            // every copy when SMAppService and NSWorkspace raced
            // (issue #138).
            if MenuBarInstancePolicy.shouldExitAsDuplicate(
                selfPID: myPID,
                selfLaunchDate: me?.launchDate,
                siblings: siblings
            ) {
                exit(0)
            }
        }
    }

    // Polling runs continuously from launch in MenuStatsModel (started by the
    // app delegate), NOT from the popover's onAppear (see MenuStatsModel for
    // why). The App just observes the model and renders it.
    @NSApplicationDelegateAdaptor(MenuAppDelegate.self) private var appDelegate
    @State private var model = MenuStatsModel.shared
    @AppStorage(AppLanguage.defaultsKey, store: SharedAppState.defaults) private var appLanguageRaw = AppLanguage.system.rawValue
    @AppStorage(MenuBarMetric.defaultsKey, store: SharedAppState.defaults) private var menuBarMetricRaw = MenuBarMetric.diskFree.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .fallback
    }

    /// Menu-bar label icon: an SF Symbol rendered as a template image so
    /// macOS automatically tints it to match the current menu bar appearance
    /// (dark in light mode, light in dark mode).
    private static let labelIcon: NSImage = {
        let img = NSImage(systemSymbolName: "sparkles",
                          accessibilityDescription: "Clean My Life")!
        img.isTemplate = true
        return img
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuPopover(model: model)
                .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
                .environment(\.layoutDirection, appLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
                .id(appLanguage.rawValue)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: StatusGlyph.image(working: model.isWorking, alert: model.hasAlert))
                if let stats = model.stats,
                   let value = MenuBarMetric.resolve(menuBarMetricRaw).formattedValue(
                       diskFree: stats.diskFree,
                       gpuUsage: stats.gpuUsage,
                       memoryUsage: stats.memoryTotal > 0
                           ? Double(stats.memoryUsed) / Double(stats.memoryTotal)
                           : 0,
                       batteryTemperature: stats.batteryTemperature
                   ) {
                    Text(value)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Palette

enum MenuPalette {
    static let bgTop = Color(red: 0.33, green: 0.18, blue: 0.55)
    static let bgBottom = Color(red: 0.13, green: 0.08, blue: 0.28)
    static let card = Color(red: 0.10, green: 0.07, blue: 0.22)
    static let teal = Color(red: 0.40, green: 0.85, blue: 0.82)
    static let yellow = Color(red: 0.98, green: 0.82, blue: 0.30)
    static let green = Color(red: 0.24, green: 0.80, blue: 0.47)
    static let red = Color(red: 0.93, green: 0.33, blue: 0.34)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.58)

    static func barColor(_ v: Double) -> Color {
        if v > 0.85 { return Color(red: 0.98, green: 0.42, blue: 0.45) }   // soft red
        if v > 0.65 { return yellow }
        return teal
    }
}

// MARK: - Ring gauge

struct RingGauge: View {
    let value: Double
    let color: Color
    let center: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(center).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
    }
}

// MARK: - Glass card modifier

private extension View {
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        self
            .background(MenuPalette.card.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(.ultraThinMaterial.opacity(0.30),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            }
    }
}
