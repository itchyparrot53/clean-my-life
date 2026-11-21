#if DEBUG
import SwiftUI

// Phase 11 §12: previews for the shared templates with fake data. These are
// compile-time only; they never ship in a release build.

#Preview("Primary button") {
    HStack(spacing: 40) {
        PrimaryButton(label: "Scan", meta: "1.2 GB", action: {})
        PrimaryButton(label: "Clean", meta: "0 bytes", isEnabled: false, action: {})
        PrimaryButton(label: "Stop", progress: 0.42, onStop: {}, action: {})
        PrimaryButton(label: "Uninstall", meta: "2 applications", tint: .pink, action: {})
    }
    .padding(50)
    .background(LinearGradient(colors: [ModulePalette.cleanup.top, ModulePalette.cleanup.bottom],
                               startPoint: .top, endPoint: .bottom))
}

#Preview("Checkboxes and tiles") {
    VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 18) {
            TriStateCheckbox(state: .off, toggle: {})
            TriStateCheckbox(state: .mixed, toggle: {})
            TriStateCheckbox(state: .on, toggle: {})
        }
        HStack(spacing: 18) {
            CategoryTile(symbol: "internaldrive", tint: ModulePalette.cleanup.top)
            CategoryTile.threat("ladybug")
            PrimaryCircle(label: "Scan", progress: nil, isEnabled: true)
        }
    }
    .padding(40)
    .background(LinearGradient(colors: [ModulePalette.protection.top, ModulePalette.protection.bottom],
                               startPoint: .top, endPoint: .bottom))
}

#Preview("Intro and scanning") {
    HStack(spacing: 24) {
        VStack(alignment: .leading, spacing: 14) {
            Text("Malware Removal").font(TypeScale.introTitle)
            Text("Scans for adware, unwanted apps and known threats.")
                .font(TypeScale.introSubtitle)
                .foregroundStyle(TypeScale.secondaryText)
        }
        TemplateHero(palette: .protection, symbol: "ladybug", motion: .scanning, diameter: 220)
    }
    .padding(40)
    .background(LinearGradient(colors: [ModulePalette.protection.top, ModulePalette.protection.bottom],
                               startPoint: .top, endPoint: .bottom))
}

#Preview("Results") {
    VStack(alignment: .leading, spacing: 8) {
        Text("Scan complete").font(TypeScale.resultsHeadline)
        CountUpBytes(bytes: 1_190_000_000)
        Text("selected to clean").font(TypeScale.meta).foregroundStyle(TypeScale.secondaryText)
    }
    .padding(50)
    .background(LinearGradient(colors: [ModulePalette.cleanup.top, ModulePalette.cleanup.bottom],
                               startPoint: .top, endPoint: .bottom))
}

#endif
