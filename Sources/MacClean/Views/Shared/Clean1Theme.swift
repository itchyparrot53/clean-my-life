import AppKit
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

    /// Malware with threats found (A17).
    static let threat = ModulePalette(top: Color(hex: 0xD9665A), bottom: Color(hex: 0x4E3368))

    /// Neutral background for the "Remove background colors" setting.
    static let neutral = ModulePalette(top: Color(hex: 0x2A2B30), bottom: Color(hex: 0x1C1D21))
}

extension SidebarItem {
    /// Per-module colour family. Finer-grained than `ModuleTheme`, which stays per section.
    var palette: ModulePalette {
        switch self {
        case .smartScan: .checkup
        case .systemJunk, .mailAttachments, .trashBins, .projectJunk, .diskHogs, .cleanHistory, .aiClutter: .cleanup
        case .malwareRemoval, .privacy, .wifiNetworks, .appPermissions, .browserExtensions: .protection
        case .optimization: .optimisation
        case .maintenance: .maintenance
        case .uninstaller, .unusedApps, .extensions: .applications
        case .updater: .updater
        case .spaceLens, .duplicates, .similarPhotos: .spaceMap
        case .screenshots, .browserTabs: .largeOld
        case .largeOldFiles, .downloadsCleanup: .largeOld
        case .shredder: .shredder
        case .settings, .tools: .slate
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

/// Translucent surfaces (UI_SPEC §2.2). Fills sit on top of a material.
enum Surface {
    static let sidebarFill = Color.white.opacity(0.16)
    static let sidebarStroke = Color.white.opacity(0.18)
    static let sidebarSelection = Color.black.opacity(0.16)
    static let rowSelection = Color.white.opacity(0.12)
    static let sheetFill = Color.black.opacity(0.22)
    static let popoverFill = Color.black.opacity(0.78)
    static let searchFill = Color.white.opacity(0.12)
    static let ghostPillFill = Color.white.opacity(0.14)
    static let secondaryPill = Color(hex: 0x5CC8F0)
    static let hairline = Color.white.opacity(0.15)
    static let dimmed: Double = 0.35

    static let cardRadius: CGFloat = 12
    static let sidebarRadius: CGFloat = 12
    static let selectionRadius: CGFloat = 7
    static let rowRadius: CGFloat = 8
    static let popoverRadius: CGFloat = 10
    static let pillRadius: CGFloat = 6
}

/// Type scale (UI_SPEC §2.3). White text over the gradients.
enum TypeScale {
    static let sidebarItem = Font.system(size: 13)
    static let sidebarHeader = Font.system(size: 12)
    static let sidebarBadge = Font.system(size: 11)
    static let topBarTitle = Font.system(size: 13, weight: .medium)
    static let topBarBack = Font.system(size: 13)
    static let introTitle = Font.system(size: 26, weight: .semibold)
    static let introSubtitle = Font.system(size: 13)
    static let bulletTitle = Font.system(size: 13, weight: .semibold)
    static let bulletBody = Font.system(size: 11)
    static let resultsHeadline = Font.system(size: 22, weight: .semibold)
    static let bigMetric = Font.system(size: 40, weight: .light).monospacedDigit()
    static let bigMetricUnit = Font.system(size: 14)
    static let reviewTitle = Font.system(size: 26, weight: .semibold)
    static let reviewDescription = Font.system(size: 13)
    static let row = Font.system(size: 13)
    static let rowSize = Font.system(size: 13).monospacedDigit()
    static let primaryButton = Font.system(size: 14, weight: .semibold)
    static let meta = Font.system(size: 13)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.75)
    static let tertiaryText = Color.white.opacity(0.55)
    static let headerText = Color.white.opacity(0.55)
}

/// Window measurements (UI_SPEC §1.2) as fractions of the card width W /
/// height H, with the pt values at the default 976 × 640 card.
enum CardLayout {
    static let defaultCard = CGSize(width: 976, height: 640)
    static let minimumCard = CGSize(width: 820, height: 560)
    static let sidebarWidth: CGFloat = 205          // 0.21 W
    static let sidebarOverhang: CGFloat = 34        // 0.035 W
    static let sidebarTopInset: CGFloat = 46  // traffic lights centred above the sidebar: 16 pt gap each side
    static let sidebarBottomInset: CGFloat = 26
    static let topBarHeight: CGFloat = 44
    static let primaryButtonDiameter: CGFloat = 72  // 0.072 W
    static let primaryButtonBottomInset: CGFloat = 36
    static let heroDiameter: CGFloat = 260          // 0.27 W
    static let heroCenter = CGPoint(x: 0.76, y: 0.45) // × (W, H)
    static let introTextLeading: CGFloat = 0.31     // × W
    static let introTextMaxWidth: CGFloat = 0.30    // × W
    static let trafficLightInset = CGPoint(x: 18, y: 16)
    static let contentLeadingGap: CGFloat = 24      // after the sidebar
    static let contentTrailingInset: CGFloat = 28
    static let statusButtonInset: CGFloat = 16

    /// Transparent room around the card for its shadow (UI_SPEC §1.1). The
    /// sidebar overhang is added on the left on top of this.
    static let windowMargins = NSEdgeInsets(top: 16, left: 18, bottom: 38, right: 26)

    static var cardRadius: CGFloat {
        if #available(macOS 26, *) { 16 } else { 12 }
    }

    /// Window size for a given card size.
    static func windowSize(forCard card: CGSize) -> CGSize {
        CGSize(width: card.width + sidebarOverhang + windowMargins.left + windowMargins.right,
               height: card.height + windowMargins.top + windowMargins.bottom)
    }
}

/// Where everything sits for a given window size (UI_SPEC §1.1, §1.2). In
/// full screen the margins and overhang go away and the sidebar tucks inside.
struct ShellMetrics {
    let card: CGRect
    let sidebar: CGRect
    /// Module area, in card coordinates.
    let content: CGRect
    let cardRadius: CGFloat
    let isFullScreen: Bool

    init(windowSize size: CGSize, isFullScreen: Bool) {
        self.isFullScreen = isFullScreen
        let margins = isFullScreen ? NSEdgeInsets() : CardLayout.windowMargins
        let overhang = isFullScreen ? 0 : CardLayout.sidebarOverhang
        card = CGRect(
            x: margins.left + overhang,
            y: margins.top,
            width: max(0, size.width - margins.left - overhang - margins.right),
            height: max(0, size.height - margins.top - margins.bottom))
        let sidebarX = isFullScreen ? card.minX + 12 : card.minX - overhang
        sidebar = CGRect(
            x: sidebarX,
            y: card.minY + CardLayout.sidebarTopInset,
            width: CardLayout.sidebarWidth,
            height: max(0, card.height - CardLayout.sidebarTopInset - CardLayout.sidebarBottomInset))
        let contentX = sidebar.maxX - card.minX + CardLayout.contentLeadingGap
        content = CGRect(
            x: contentX,
            y: CardLayout.topBarHeight,
            width: max(0, card.width - contentX - CardLayout.contentTrailingInset),
            height: max(0, card.height - CardLayout.topBarHeight))
        cardRadius = isFullScreen ? 0 : CardLayout.cardRadius
    }

    /// Close button's top-left, from the window's top-left.
    var trafficLightOrigin: CGPoint {
        CGPoint(x: card.minX + CardLayout.trafficLightInset.x, y: card.minY + CardLayout.trafficLightInset.y)
    }
}

/// A small tiling grain texture laid over the gradients at low opacity so they
/// don't band (UI_SPEC §2.1). Generated once, deterministically.
enum GrainTexture {
    static let tile: CGImage? = {
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size)
        var seed: UInt32 = 0x9E37_79B9
        for index in pixels.indices {
            // xorshift32: cheap, deterministic noise.
            seed ^= seed << 13
            seed ^= seed >> 17
            seed ^= seed << 5
            pixels[index] = UInt8(truncatingIfNeeded: seed)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()
}

/// The card background: module gradient, grain, a soft top-right highlight,
/// and a crossfade when the module changes (A1).
struct ModuleBackdrop: View {
    let item: SidebarItem
    /// A17: blend towards red while threats are showing.
    var threat = false
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false

    private var palette: ModulePalette {
        if removeBackgroundColors { return .neutral }
        return threat ? .threat : item.palette
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
                .id(palette.top.description + palette.bottom.description)
                .transition(.opacity)
        }
        .overlay {
            if let tile = GrainTexture.tile {
                Image(decorative: tile, scale: 2)
                    .resizable(resizingMode: .tile)
                    .blendMode(.overlay)
                    .opacity(0.06)
                    .allowsHitTesting(false)
            }
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
        .animation(threat ? .easeInOut(duration: 0.8) : Motion.backdropCrossfade, value: palette)
    }
}
