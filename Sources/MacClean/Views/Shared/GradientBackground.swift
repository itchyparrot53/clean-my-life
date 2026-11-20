import SwiftUI
import AppKit

extension Color {
    /// A color that resolves to `light` or `dark` based on the active
    /// appearance, so the same value renders correctly in both Light and Dark
    /// without threading `colorScheme` through every view.
    init(light: Color, dark: Color) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }
}

/// Neutral background used when "Remove background colors" is enabled in
/// Settings, replacing per-module themed gradients. Light-grey in Light mode,
/// near-black in Dark.
private let neutralGradient = LinearGradient(
    colors: [
        Color(light: Color(red: 0.95, green: 0.95, blue: 0.96), dark: Color(red: 0.12, green: 0.12, blue: 0.14)),
        Color(light: Color(red: 0.92, green: 0.92, blue: 0.94), dark: Color(red: 0.16, green: 0.16, blue: 0.18)),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

public enum ModuleTheme {
    case smartScan
    case cleanup
    case protection
    case performance
    case applications
    case files
    case settings

    public var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public var buttonGradient: LinearGradient {
        LinearGradient(colors: buttonColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Clean1: the section's colour family from UI_SPEC §2.1. Always on colour
    /// (no Light/Dark variants); per-module backgrounds use `SidebarItem.palette`.
    var palette: ModulePalette {
        switch self {
        case .smartScan: .checkup
        case .cleanup: .cleanup
        case .protection: .protection
        case .performance: .optimisation
        case .applications: .applications
        case .files: .spaceMap
        case .settings: .slate
        }
    }

    /// Full-screen background gradient, top to bottom.
    public var colors: [Color] {
        [palette.top, palette.bottom]
    }

    /// Buttons stay vivid in both modes so their white labels remain legible.
    /// Secondary buttons still drawn as gradients (until each screen is restyled).
    public var buttonColors: [Color] {
        [palette.top, palette.bottom]
    }

    /// Accent for icons/highlights: the section's top colour.
    public var accentColor: Color {
        palette.top
    }
}

public struct GradientBackgroundView: View {
    let theme: ModuleTheme
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false

    public init(theme: ModuleTheme) {
        self.theme = theme
    }

    public var body: some View {
        if removeBackgroundColors {
            neutralGradient
        } else {
            theme.gradient
        }
    }
}
