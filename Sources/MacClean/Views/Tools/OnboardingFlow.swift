import AppKit
import SwiftUI
import MacCleanKit

/// First-run flow (UI_SPEC §7), shown inside the card with the sidebar
/// hidden: Welcome → Full Disk Access (live check) → Admin helper → Menu bar.
struct OnboardingFlow: View {
    let onFinish: (_ runCheckup: Bool) -> Void
    @State private var step = 0
    @State private var hasAccess = OnboardingFlow.hasFullDiskAccess()
    @AppStorage("showMenuBarWidget") private var showMenuBar = true

    var body: some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                hero(space)
                    .position(x: space.x(0.72), y: space.y(0.44))
                text
                    .frame(width: 0.36 * space.W, alignment: .leading)
                    .offset(x: space.x(0.12), y: space.y(0.28))
                    .id(step)
                    .transition(.offset(y: 12).combined(with: .opacity))
                dots
                    .position(x: space.buttonCenter.x, y: space.buttonCenter.y - 58)
                PrimarySlot {
                    PrimaryButton(label: buttonLabel, meta: step == 3 ? "Runs a Checkup" : nil, action: primary)
                }
                if step > 0 {
                    Button(L10n.tr("返回", "Back", "Назад")) { withAnimation(TemplateMotion.morph) { step -= 1 } }
                        .buttonStyle(.plain)
                        .font(TypeScale.topBarBack)
                        .foregroundStyle(TypeScale.secondaryText)
                        .position(x: space.x(0.12) + 20, y: space.y(0) + 30)
                }
            }
            .foregroundStyle(TypeScale.primaryText)
        }
        .animation(TemplateMotion.morph, value: step)
        .task(id: step) {
            // Step 2: re-check access every second; tick and move on when granted.
            guard step == 1 else { return }
            while !Task.isCancelled {
                hasAccess = Self.hasFullDiskAccess()
                if hasAccess {
                    try? await Task.sleep(for: .seconds(1.2))
                    if !Task.isCancelled, step == 1 { withAnimation(TemplateMotion.morph) { step = 2 } }
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func hero(_ space: CardSpace) -> some View {
        let size = space.heroDiameter
        switch step {
        case 1:
            ZStack {
                HeroDisc(palette: .checkup, symbol: "", diameter: size).opacity(0.6)
                if hasAccess { DrawnCheck(size: size * 0.42) } else { AccessSwitchDrawing(width: size * 0.62) }
            }
        case 2:
            HeroDisc(palette: .checkup, symbol: "lock.shield", diameter: size)
        case 3:
            ZStack {
                HeroDisc(palette: .checkup, symbol: "", diameter: size).opacity(0.6)
                MenuBarPreview(width: size * 0.78, on: showMenuBar)
            }
        default:
            // Brand kit: the approved app icon, never a sparkle stand-in.
            if let icon = BrandAssets.image("AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 0.95, height: size * 0.95)
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                    .accessibilityLabel(MCConstants.appName)
            } else {
                TemplateHero(palette: .checkup, symbol: "sparkles", illustration: "Checkup", motion: .floating, diameter: size)
            }
        }
    }

    @ViewBuilder
    private var text: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch step {
            case 1:
                Text("Let \(MCConstants.appName) look everywhere").font(TypeScale.introTitle)
                Text("Caches, mail and the Trash sit in folders macOS protects. Turn on Full Disk Access for \(MCConstants.appName) in System Settings. This page notices on its own when it's on.")
                    .font(TypeScale.introSubtitle).foregroundStyle(TypeScale.secondaryText)
                Label(hasAccess ? "Full Disk Access is on" : "Waiting for Full Disk Access…",
                      systemImage: hasAccess ? "checkmark.circle.fill" : "hourglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasAccess ? Color(hex: 0x5EE6A0) : TypeScale.tertiaryText)
                if !hasAccess {
                    Button("Skip for now") { withAnimation(TemplateMotion.morph) { step = 2 } }
                        .buttonStyle(.ghostPill)
                }
            case 2:
                Text("Admin tasks").font(TypeScale.introTitle)
                Text("A few maintenance tasks, like freeing purgeable space, need administrator rights. \(MCConstants.appName) asks for your password when you run one, never in the background.")
                    .font(TypeScale.introSubtitle).foregroundStyle(TypeScale.secondaryText)
            case 3:
                Text("Keep an eye from the menu bar").font(TypeScale.introTitle)
                Text("A small panel with storage, memory, battery and tips. It's always one click away.")
                    .font(TypeScale.introSubtitle).foregroundStyle(TypeScale.secondaryText)
                Toggle("Show in the menu bar", isOn: $showMenuBar)
                    .toggleStyle(.switch)
                    .onChange(of: showMenuBar) { _, on in Task { await MenuBarLauncher.shared.setEnabled(on) } }
            default:
                Text("Welcome to \(MCConstants.appName)").font(TypeScale.introTitle)
                Text("A calm way to keep your Mac tidy, safe and quick. Nothing is removed without you seeing it first, and most things can be put back.")
                    .font(TypeScale.introSubtitle).foregroundStyle(TypeScale.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(index == step ? 0.95 : 0.3))
                    .frame(width: index == step ? 18 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
        .accessibilityLabel("Step \(step + 1) of 4")
    }

    private var buttonLabel: String {
        switch step {
        case 1: hasAccess ? "Continue" : "Open Settings"
        case 3: "Start"
        default: "Continue"
        }
    }

    private func primary() {
        switch step {
        case 1 where !hasAccess:
            PermissionManager.shared.openFullDiskAccessSettings()
        case 3:
            onFinish(true)
        default:
            withAnimation(TemplateMotion.morph) { step += 1 }
        }
    }

    /// Full Disk Access can't be queried directly; reading a protected folder
    /// is the standard check.
    static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        for folder in ["Library/Safari", "Library/Mail", "Library/Messages"] {
            let path = (home as NSString).appendingPathComponent(folder)
            if FileManager.default.fileExists(atPath: path) {
                return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
            }
        }
        return FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }
}

/// Our own mini drawing of a settings row with a switch: not a screenshot.
private struct AccessSwitchDrawing: View {
    let width: CGFloat
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: width * 0.06) {
            RoundedRectangle(cornerRadius: width * 0.05).fill(Color.white.opacity(0.9))
                .frame(width: width * 0.16, height: width * 0.16)
                .overlay(Image(systemName: "sparkles").font(.system(size: width * 0.09)).foregroundStyle(Color(hex: 0x6E5A9E)))
            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.85)).frame(width: width * 0.4, height: width * 0.05)
            Capsule().fill(on ? Color(hex: 0x5EE6A0) : Color.white.opacity(0.35))
                .frame(width: width * 0.22, height: width * 0.13)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(.white).padding(width * 0.012)
                }
        }
        .padding(width * 0.06)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: width * 0.06))
        .onAppear {
            guard !reduceMotion else { on = true; return }
            withAnimation(.easeInOut(duration: 0.6).delay(0.6).repeatForever(autoreverses: true)) { on = true }
        }
        .accessibilityHidden(true)
    }
}

/// A small sketch of the menu bar panel.
private struct MenuBarPreview: View {
    let width: CGFloat
    let on: Bool

    var body: some View {
        VStack(spacing: width * 0.05) {
            HStack {
                Spacer()
                Image(systemName: "sparkles").font(.system(size: width * 0.07))
            }
            HStack(spacing: width * 0.05) {
                Circle().trim(from: 0, to: 0.72)
                    .stroke(Color(hex: 0xFF6F7D), lineWidth: width * 0.04)
                    .background(Circle().stroke(Color(hex: 0x3DE0C8), lineWidth: width * 0.04))
                    .rotationEffect(.degrees(-90))
                    .frame(width: width * 0.32, height: width * 0.32)
                VStack(spacing: width * 0.03) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.25)).frame(height: width * 0.07)
                    }
                }
            }
        }
        .padding(width * 0.07)
        .frame(width: width)
        .background(LinearGradient(colors: [Color(hex: 0x4A3A7A), Color(hex: 0x2B2552)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: width * 0.06))
        .opacity(on ? 1 : 0.35)
        .animation(.easeInOut(duration: 0.25), value: on)
        .accessibilityHidden(true)
    }
}
