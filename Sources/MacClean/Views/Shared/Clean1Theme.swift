import SwiftUI

// Clean1 reskin: visual tokens from UI_SPEC.md (v2) §2 and §10.
// Kept in one place so colours and timings are tuned without touching views.

extension Color {
    /// `Color(hex: 0xC86C8E)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

/// A two-stop, top-to-bottom module background (UI_SPEC §2.1). The app is always
/// "on colour", so these don't change between Light and Dark.
struct ModulePalette: Equatable {
    let top: Color
    let bottom: Color

    static let checkup = ModulePalette(top: Color(hex: 0x9B6E9E), bottom: Color(hex: 0x45457A))
    static let cleanup = ModulePalette(top: Color(hex: 0xC86C8E), bottom: Color(hex: 0x4B4079))
    static let protection = ModulePalette(top: Color(hex: 0xD57D6F), bottom: Color(hex: 0x4A4174))
    static let optimisation = ModulePalette(top: Color(hex: 0xA37ACB), bottom: Color(hex: 0x4B4B8C))
    static let maintenance = ModulePalette(top: Color(hex: 0xC46FA5), bottom: Color(hex: 0x504A8E))
    static let applications = ModulePalette(top: Color(hex: 0x4E8FC2), bottom: Color(hex: 0x2E4B86))
    static let updater = ModulePalette(top: Color(hex: 0x2FB49B), bottom: Color(hex: 0x2C5D7B))
    static let spaceMap = ModulePalette(top: Color(hex: 0x40A98A), bottom: Color(hex: 0x2C5170))
    static let largeOld = ModulePalette(top: Color(hex: 0xDA725F), bottom: Color(hex: 0x4C3F74))
    static let shredder = ModulePalette(top: Color(hex: 0x4BA7C8), bottom: Color(hex: 0x2E4E86))
    static let slate = ModulePalette(top: Color(hex: 0x6E7A8D), bottom: Color(hex: 0x2D3441))

    /// Neutral background for the "Remove background colors" setting.
    static let neutral = ModulePalette(top: Color(hex: 0x2A2B30), bottom: Color(hex: 0x1C1D21))
}

extension SidebarItem {
    /// Per-module colour family. Finer-grained than `ModuleTheme`, which stays per section.
    var palette: ModulePalette {
        switch self {
        case .smartScan: .checkup
        case .systemJunk, .mailAttachments, .trashBins, .projectJunk, .diskHogs, .cleanHistory: .cleanup
        case .malwareRemoval, .privacy, .wifiNetworks, .appPermissions, .browserExtensions: .protection
        case .optimization: .optimisation
        case .maintenance: .maintenance
        case .uninstaller, .unusedApps, .extensions: .applications
        case .updater: .updater
        case .spaceLens, .duplicates: .spaceMap
        case .largeOldFiles: .largeOld
        case .shredder: .shredder
        case .settings: .slate
        }
    }
}

/// Animation constants named after the A-IDs in UI_SPEC §10.
enum Motion {
    /// A1: module background crossfade.
    static let backdropCrossfade = Animation.easeInOut(duration: 0.45)
    /// A5: primary button hover/press.
    static let buttonPress = Animation.spring(response: 0.25, dampingFraction: 0.7)
    /// A6: idle breathing glow, one half-cycle.
    static let breathing = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
    /// A8: progress ring update.
    static let progress = Animation.linear(duration: 0.15)
}

/// The card background: module gradient, a soft top-right highlight, and a
/// crossfade when the module changes (A1).
struct ModuleBackdrop: View {
    let item: SidebarItem
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false

    private var palette: ModulePalette { removeBackgroundColors ? .neutral : item.palette }

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
                .id(palette.top.description + palette.bottom.description)
                .transition(.opacity)
        }
        .overlay {
            GeometryReader { proxy in
                RadialGradient(
                    colors: [.white.opacity(0.10), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.6)
            }
            .allowsHitTesting(false)
        }
        .animation(Motion.backdropCrossfade, value: palette)
    }
}
