import SwiftUI
import MacCleanKit

public struct ScanButton: View {
    let title: String
    let subtitle: String?
    let theme: ModuleTheme
    let isScanning: Bool
    let progress: Double
    let action: () -> Void

    public init(
        title: String = L10n.tr("扫描", "Scan", "Сканировать"),
        subtitle: String? = nil,
        theme: ModuleTheme = .smartScan,
        isScanning: Bool = false,
        progress: Double = 0,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.isScanning = isScanning
        self.progress = progress
        self.action = action
    }

    /// Optional: while scanning, hovering the ring reads "Stop" and clicking
    /// it calls this (UI_SPEC §2.6).
    var onStop: (() -> Void)? = nil

    // Clean1 primary button (UI_SPEC §2.6); see PrimaryButton.
    public var body: some View {
        PrimaryButton(
            label: title,
            meta: isScanning ? nil : subtitle,
            progress: isScanning ? progress : nil,
            onStop: onStop,
            action: action)
    }
}

/// The circle itself, shared by the idle and working states.
struct PrimaryCircle: View {
    static let diameter: CGFloat = 72
    static let ringColor = Color(hex: 0xA8E6FF)

    let label: String
    /// nil = idle (full ring with breathing glow); a value = progress ring.
    let progress: Double?
    let isEnabled: Bool
    var ringColor: Color = PrimaryCircle.ringColor

    @State private var glowUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Glass body.
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.30), .white.opacity(0.12)],
                    center: .center, startRadius: 0, endRadius: Self.diameter / 2))

            if let progress {
                // Track + progress ring with a bright head (A8).
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringColor.opacity(0.7), radius: 6)
                    .animation(Motion.progress, value: progress)
            } else {
                // Idle ring with breathing glow (A6).
                Circle()
                    .stroke(ringColor.opacity(0.9), lineWidth: 3)
                    .shadow(color: ringColor.opacity(glowUp ? 0.6 : 0.35), radius: glowUp ? 16 : 12)
            }

            Text(label)
                .font(.system(size: progress == nil ? 14 : 15, weight: .semibold, design: progress == nil ? .default : .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .contentTransition(.numericText())
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .opacity(isEnabled || progress != nil ? 1 : 0.45)
        .onAppear {
            guard progress == nil, !reduceMotion else { return }
            withAnimation(Motion.breathing) { glowUp = true }
        }
    }
}

/// Hover 1.04, press 0.95 (A5).
struct PrimaryCircleButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovering ? 1.04 : 1))
            .animation(Motion.buttonPress, value: configuration.isPressed)
            .animation(Motion.buttonPress, value: isHovering)
            .onHover { isHovering = $0 }
            .contentShape(Circle())
    }
}

public struct ScanProgressRing: View {
    let progress: Double
    let phase: String
    let detail: String?
    let theme: ModuleTheme
    @State private var announcedStep = 0

    public init(progress: Double, phase: String, detail: String? = nil, theme: ModuleTheme = .smartScan) {
        self.progress = progress
        self.phase = phase
        self.detail = detail
        self.theme = theme
    }

    public var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.12), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: progress)

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(width: 110, height: 110)

            VStack(spacing: 6) {
                Text(phase)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: 0.2), value: phase)

                if let detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.6))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("扫描中", "Scanning", "Сканирование"))
        .accessibilityValue("\(Int(progress * 100))%, \(phase)")
        .onChange(of: Int(progress * 100)) { _, percent in
            // Announce at 25 % steps, not on every tick.
            let step = (percent / 25) * 25
            guard step > announcedStep, step > 0 else { return }
            announcedStep = step
            AccessibilityNotification.Announcement("\(step) percent").post()
        }
    }
}
