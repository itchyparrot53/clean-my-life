import AppKit
import SwiftUI
import MacCleanKit

// Clean1 screen templates (UI_SPEC §4). Positions are fractions of the card
// (W × H), converted into the module area's own coordinates.

// MARK: - Card geometry

/// The card's size and where the module area sits on it, so templates can
/// place things relative to the whole card (hero at 0.76 W, button centred
/// on the card, not the content area).
struct CardGeometry: Equatable {
    var card: CGSize = CardLayout.defaultCard
    var content = CGRect(x: 195, y: CardLayout.topBarHeight, width: 753, height: 596)
}

extension EnvironmentValues {
    @Entry var cardGeometry = CardGeometry()
    /// Shared by templates so the hero and title morph between states (A11).
    @Entry var templateNamespace: Namespace.ID?
    /// The module this view belongs to, set by the shell.
    @Entry var currentModule: SidebarItem?
}

struct CardSpace {
    let geometry: CardGeometry
    var W: CGFloat { geometry.card.width }
    var H: CGFloat { geometry.card.height }
    /// Card x fraction → module-area x.
    func x(_ fraction: CGFloat) -> CGFloat { fraction * W - geometry.content.minX }
    /// Card y fraction → module-area y.
    func y(_ fraction: CGFloat) -> CGFloat { fraction * H - geometry.content.minY }
    var heroDiameter: CGFloat { min(CardLayout.heroDiameter * W / CardLayout.defaultCard.width, H * 0.42) }
    var heroCenter: CGPoint { CGPoint(x: x(CardLayout.heroCenter.x), y: y(CardLayout.heroCenter.y)) }
    var textLeading: CGFloat { x(CardLayout.introTextLeading) }
    var textWidth: CGFloat { CardLayout.introTextMaxWidth * W }
    /// Primary button centre: middle of the card, 36 pt clear of its bottom.
    var buttonCenter: CGPoint {
        CGPoint(x: W / 2 - geometry.content.minX,
                y: H - CardLayout.primaryButtonBottomInset - CardLayout.primaryButtonDiameter / 2 - geometry.content.minY)
    }
    /// Space kept free at the bottom of the module area for the button.
    var buttonReserve: CGFloat { H - geometry.content.minY - (buttonCenter.y - CardLayout.primaryButtonDiameter / 2) + 12 }
}

struct CardSpaceReader<Content: View>: View {
    @Environment(\.cardGeometry) private var geometry
    let content: (CardSpace) -> Content

    var body: some View {
        content(CardSpace(geometry: geometry))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Motion helpers (A11, A13)

enum TemplateMotion {
    /// A11: state morph.
    static let morph = Animation.spring(response: 0.5, dampingFraction: 0.86)
    /// Others: offset 12 + fade.
    static var stateTransition: AnyTransition { .offset(y: 12).combined(with: .opacity) }
}

/// A13: children rise 14 pt and fade in, 35 ms apart (max 10 steps).
struct StaggerIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.035 * Double(min(index, 10)))) {
                    shown = true
                }
            }
    }
}

extension View {
    func staggerIn(_ index: Int) -> some View { modifier(StaggerIn(index: index)) }

    @ViewBuilder
    func matchedTemplate(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace { matchedGeometryEffect(id: id, in: namespace) } else { self }
    }
}

// MARK: - Hero

/// Hero disc at its intro spot, with the scanning sweep (A9) or the empty
/// float (A30) when asked.
struct TemplateHero: View {
    enum Motion { case still, scanning, radar, floating }

    let palette: ModulePalette
    let symbol: String
    var illustration: String? = nil
    var motion: Motion = .still
    var diameter: CGFloat
    @Environment(\.templateNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        HeroDisc(palette: palette, symbol: symbol, illustration: illustration, diameter: diameter)
            .overlay {
                if motion == .scanning && !reduceMotion {
                    ScanSweep(diameter: diameter)
                }
            }
            .background {
                if motion == .radar && !reduceMotion {
                    RadarRings(diameter: diameter, tint: palette.top)
                }
            }
            .offset(y: bob)
            .matchedTemplate("hero", in: namespace)
            .onAppear { startMotion() }
            .onChange(of: motion) { _, _ in startMotion() }
    }

    private var bob: CGFloat {
        guard !reduceMotion, motion != .still else { return 0 }
        return phase ? -4 : 4
    }

    private func startMotion() {
        guard !reduceMotion, motion != .still else { phase = false; return }
        // A9 bobs over 3 s; A30 floats over 4 s.
        withAnimation(.easeInOut(duration: motion == .floating ? 2 : 1.5).repeatForever(autoreverses: true)) {
            phase.toggle()
        }
    }
}

/// A9: a soft light band sweeping diagonally across the disc every 1.8 s,
/// with a few particles drifting up from the rim.
private struct ScanSweep: View {
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    private var paused: Bool { reduceMotion || activeState != .key }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let sweep = (t.truncatingRemainder(dividingBy: 1.8)) / 1.8
            ZStack {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.28), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: diameter * 0.5, height: diameter * 1.6)
                    .rotationEffect(.degrees(35))
                    .offset(x: (sweep * 2 - 1) * diameter)
                    .blendMode(.plusLighter)
                    .mask(Circle().frame(width: diameter, height: diameter))
                ForEach(0..<6, id: \.self) { index in
                    let life = ((t / 2.4) + Double(index) / 6).truncatingRemainder(dividingBy: 1)
                    let angle = Double(index) * 1.1 + 0.4
                    Circle()
                        .fill(.white.opacity(0.7 * (1 - life)))
                        .frame(width: 4, height: 4)
                        .offset(x: cos(angle) * diameter * 0.46,
                                y: sin(angle) * diameter * 0.2 + diameter * 0.28 - life * diameter * 0.5)
                }
            }
            .frame(width: diameter, height: diameter)
        }
        .allowsHitTesting(false)
    }
}

/// A16: three rings scale 0.7 → 1.7 and fade 0.45 → 0 over 2.4 s, 0.8 s apart.
private struct RadarRings: View {
    let diameter: CGFloat
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    private var paused: Bool { reduceMotion || activeState != .key }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let life = ((t + Double(index) * 0.8) / 2.4).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                        .background(Circle().fill(tint.opacity(0.12)))
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(0.7 + life)
                        .opacity(0.45 * (1 - life))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Text block pieces

struct TemplateTitle: View {
    let text: String
    @Environment(\.templateNamespace) private var namespace

    var body: some View {
        Text(text)
            .font(TypeScale.introTitle)
            .foregroundStyle(TypeScale.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .matchedTemplate("title", in: namespace)
    }
}

struct BulletRow: View {
    let bullet: ModuleIntro.Bullet

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: bullet.symbol)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(bullet.title)
                    .font(TypeScale.bulletTitle)
                    .foregroundStyle(TypeScale.primaryText)
                Text(bullet.body)
                    .font(TypeScale.bulletBody)
                    .foregroundStyle(TypeScale.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The primary button at its card position (UI_SPEC §1.2).
struct PrimarySlot<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.templateNamespace) private var namespace

    var body: some View {
        CardSpaceReader { space in
            content
                .matchedTemplate("primary", in: namespace)
                .position(space.buttonCenter)
        }
    }
}

// MARK: - Intro (§4.1)

struct IntroTemplate<Control: View>: View {
    let title: String
    let intro: ModuleIntro
    let palette: ModulePalette
    var lastScan: String?
    var primaryMeta: String?
    @ViewBuilder var control: Control
    let onPrimary: () -> Void

    var body: some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                TemplateHero(palette: palette, symbol: intro.heroSymbol, illustration: intro.artName, diameter: space.heroDiameter)
                    .position(space.heroCenter)

                VStack(alignment: .leading, spacing: 0) {
                    TemplateTitle(text: title)
                    Text(intro.subtitle)
                        .font(TypeScale.introSubtitle)
                        .foregroundStyle(TypeScale.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    if let lastScan {
                        Text(lastScan)
                            .font(.system(size: 11))
                            .foregroundStyle(TypeScale.tertiaryText)
                            .padding(.top, 4)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(intro.bullets.enumerated()), id: \.element) { index, bullet in
                            BulletRow(bullet: bullet).staggerIn(index + 1)
                        }
                    }
                    .padding(.top, 28)

                    if Control.self != EmptyView.self {
                        Rectangle()
                            .fill(Surface.hairline)
                            .frame(width: 0.25 * space.W, height: 1)
                            .padding(.top, 24)
                        control
                            .padding(.top, 16)
                            .staggerIn(intro.bullets.count + 1)
                    }
                }
                .frame(width: space.textWidth, alignment: .leading)
                .offset(x: space.textLeading, y: space.y(0.25))

                PrimarySlot {
                    PrimaryButton(label: intro.action, meta: primaryMeta, action: onPrimary)
                }
            }
        }
    }
}

extension IntroTemplate where Control == EmptyView {
    init(title: String, intro: ModuleIntro, palette: ModulePalette, lastScan: String? = nil,
         primaryMeta: String? = nil, onPrimary: @escaping () -> Void) {
        self.init(title: title, intro: intro, palette: palette, lastScan: lastScan,
                  primaryMeta: primaryMeta, control: { EmptyView() }, onPrimary: onPrimary)
    }
}

// MARK: - Scanning (§4.2)

struct ScanningTemplate: View {
    var title = L10n.tr("正在扫描…", "Scanning…", "Сканирование…")
    let intro: ModuleIntro
    let palette: ModulePalette
    /// Current item, ticked at most 8×/s (A29).
    var path: String?
    /// Found so far, e.g. "1.2 GB found" (A4).
    var found: String?
    let progress: Double
    var onStop: (() -> Void)?
    var heroMotion: TemplateHero.Motion = .scanning
    @State private var started = Date()

    var body: some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                TemplateHero(palette: palette, symbol: intro.heroSymbol, illustration: intro.artName, motion: heroMotion,
                             diameter: space.heroDiameter)
                    .position(space.heroCenter)

                VStack(alignment: .leading, spacing: 8) {
                    TemplateTitle(text: title)
                    if let path {
                        PathTicker(text: path)
                    }
                    if let found {
                        Text(found)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(TypeScale.primaryText)
                            .numericRoll(found)
                            .padding(.top, 6)
                    }
                }
                .frame(width: space.textWidth, alignment: .leading)
                .offset(x: space.textLeading, y: space.y(0.36))

                PrimarySlot {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        PrimaryButton(label: "", meta: Self.elapsed(since: started, now: context.date),
                                      progress: progress, onStop: onStop) {}
                    }
                }
            }
        }
    }

    static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// A29: one line, middle-truncated, crossfading at most 8 times a second.
struct PathTicker: View {
    let text: String
    @State private var shown = ""
    @State private var lastTick = Date.distantPast
    @State private var pending: Task<Void, Never>?

    var body: some View {
        Text(shown)
            .font(.system(size: 12))
            .foregroundStyle(TypeScale.tertiaryText)
            .lineLimit(1)
            .truncationMode(.middle)
            .id(shown)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.1), value: shown)
            .onAppear { shown = text }
            .onChange(of: text) { _, newValue in tick(newValue) }
    }

    private func tick(_ value: String) {
        let wait = 0.125 - Date().timeIntervalSince(lastTick)
        pending?.cancel()
        if wait <= 0 {
            shown = value
            lastTick = Date()
        } else {
            pending = Task { @MainActor in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                shown = value
                lastTick = Date()
            }
        }
    }
}

// MARK: - Results A, cleanup type (§4.3)

struct ResultsTemplate: View {
    var title = L10n.tr("扫描完成", "Scan complete", "Сканирование завершено")
    let intro: ModuleIntro
    let palette: ModulePalette
    /// Selected size, counted up on arrival (A10).
    let selectedBytes: UInt64
    var subline = L10n.tr("已选择待清理", "selected to clean", "выбрано для очистки")
    var actionLabel = L10n.tr("清理", "Clean", "Очистить")
    var canAct = true
    let onReview: () -> Void
    let onAct: () -> Void

    var body: some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                TemplateHero(palette: palette, symbol: intro.heroSymbol, illustration: intro.artName, diameter: space.heroDiameter)
                    .position(space.heroCenter)

                VStack(alignment: .leading, spacing: 0) {
                    TemplateTitle(text: title)
                    CountUpBytes(bytes: selectedBytes)
                        .padding(.top, 10)
                        .staggerIn(1)
                    Text(subline)
                        .font(.system(size: 13))
                        .foregroundStyle(TypeScale.secondaryText)
                        .staggerIn(2)
                    Button(L10n.tr("查看详情…", "Review Details…", "Подробнее…"), action: onReview)
                        .buttonStyle(.ghostPill)
                        .padding(.top, 18)
                        .staggerIn(3)
                }
                .frame(width: space.textWidth, alignment: .leading)
                .offset(x: space.textLeading, y: space.y(0.30))

                PrimarySlot {
                    PrimaryButton(label: actionLabel, meta: FileSizeFormatter.format(selectedBytes),
                                  isEnabled: canAct, action: onAct)
                }
            }
        }
    }
}

/// A10: 0 → value over 0.9 s, easing out; then follows changes with A4.
struct CountUpBytes: View {
    let bytes: UInt64
    @State private var start = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if finished || reduceMotion {
                label(for: bytes)
            } else {
                TimelineView(.animation) { context in
                    // Clamped: the timeline can tick before onAppear resets `start`.
                    let t = max(0, min(1, context.date.timeIntervalSince(start) / 0.9))
                    let eased = max(0, min(1, 1 - pow(1 - t, 3)))
                    label(for: UInt64((Double(bytes) * eased).rounded(.down)))
                        .onChange(of: t >= 1) { _, done in if done { finished = true } }
                }
            }
        }
        .onAppear { start = Date() }
        .accessibilityLabel(FileSizeFormatter.format(bytes))
    }

    private func label(for value: UInt64) -> some View {
        let parts = Self.split(FileSizeFormatter.format(value))
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(parts.number)
                .font(TypeScale.bigMetric)
                .numericRoll(parts.number)
            Text(parts.unit)
                .font(TypeScale.bigMetricUnit)
                .foregroundStyle(TypeScale.secondaryText)
        }
        .foregroundStyle(TypeScale.primaryText)
    }

    static func split(_ formatted: String) -> (number: String, unit: String) {
        guard let space = formatted.lastIndex(where: { $0 == " " || $0 == "\u{00a0}" }) else { return (formatted, "") }
        return (String(formatted[..<space]), String(formatted[formatted.index(after: space)...]))
    }
}

// MARK: - Results B, verdict type (§4.3 B)

struct VerdictTemplate: View {
    struct Metric: Identifiable {
        let status: MetricRow.Status
        let metric: String
        let detail: String
        var id: String { metric }
    }

    var title = L10n.tr("扫描完成", "Scan complete", "Сканирование завершено")
    let intro: ModuleIntro
    let palette: ModulePalette
    let metrics: [Metric]
    var reviewCaption: String?
    var actionLabel = L10n.tr("移除", "Remove", "Удалить")
    var primaryMeta: String?
    var canAct = true
    let onReview: (() -> Void)?
    let onAct: () -> Void
    @State private var shifted = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                // A32: the hero slides left and grows, tucking behind the sidebar.
                TemplateHero(palette: palette, symbol: intro.heroSymbol, illustration: intro.artName, diameter: space.heroDiameter)
                    .scaleEffect((shifted ? 1.25 : 1) * (pulse ? 1.04 : 1))
                    .position(shifted ? CGPoint(x: space.x(0.30), y: space.heroCenter.y) : space.heroCenter)

                VStack(alignment: .leading, spacing: 16) {
                    TemplateTitle(text: title)
                    ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                        MetricRow(status: metric.status, metric: metric.metric, detail: metric.detail)
                            .staggerIn(index + 1)
                    }
                    if let onReview {
                        HStack(spacing: 10) {
                            Button(L10n.tr("查看详情", "Review Details", "Подробнее"), action: onReview)
                                .buttonStyle(.ghostPill)
                            if let reviewCaption {
                                Text(reviewCaption)
                                    .font(.system(size: 12))
                                    .foregroundStyle(TypeScale.tertiaryText)
                            }
                        }
                        .staggerIn(metrics.count + 1)
                    }
                }
                .frame(width: 0.34 * space.W, alignment: .leading)
                .offset(x: space.x(0.58), y: space.y(0.28))

                PrimarySlot {
                    PrimaryButton(label: actionLabel, meta: primaryMeta, isEnabled: canAct, action: onAct)
                }
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.9)) { shifted = true }
            // A17: two gentle pulses when something needs attention.
            guard !reduceMotion, metrics.contains(where: { $0.status == .warning }) else { return }
            withAnimation(.easeInOut(duration: 0.35).repeatCount(4, autoreverses: true).delay(0.6)) { pulse = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.1))
                pulse = false
            }
        }
    }
}

// MARK: - Done (A14), empty (A30), permission card, error banner (§4, §8)

struct DoneTemplate<Extra: View>: View {
    let title: String
    var subtitle: String?
    let palette: ModulePalette
    var symbol = "checkmark"
    var isWarning = false
    @ViewBuilder var extra: Extra
    var actionLabel = L10n.tr("完成", "Done", "Готово")
    let onDone: () -> Void

    var body: some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                ZStack {
                    HeroDisc(palette: palette, symbol: "", diameter: space.heroDiameter)
                        .opacity(0.55)
                    if isWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: space.heroDiameter * 0.34))
                            .foregroundStyle(Color(hex: 0xF8C04E))
                    } else {
                        DrawnCheck(size: space.heroDiameter * 0.46)
                    }
                }
                .matchedTemplate("hero", in: nil)
                .position(space.heroCenter)

                VStack(alignment: .leading, spacing: 8) {
                    TemplateTitle(text: title)
                    if let subtitle {
                        Text(subtitle)
                            .font(TypeScale.introSubtitle)
                            .foregroundStyle(TypeScale.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .staggerIn(1)
                    }
                    extra.staggerIn(2)
                }
                .frame(width: max(space.textWidth, 0.36 * space.W), alignment: .leading)
                .offset(x: space.textLeading, y: space.y(0.30))

                PrimarySlot {
                    PrimaryButton(label: actionLabel, action: onDone)
                }
            }
        }
    }
}

extension DoneTemplate where Extra == EmptyView {
    init(title: String, subtitle: String? = nil, palette: ModulePalette, isWarning: Bool = false,
         onDone: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, palette: palette, isWarning: isWarning,
                  extra: { EmptyView() }, onDone: onDone)
    }
}

/// A14: the circle draws in 0.35 s, then the tick in 0.25 s, with a small
/// spring from 0.9 to 1.
struct DrawnCheck: View {
    let size: CGFloat
    @State private var circle: CGFloat = 0
    @State private var tick: CGFloat = 0
    @State private var scale: CGFloat = 0.9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: circle)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CheckShape()
                .trim(from: 0, to: tick)
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round, lineJoin: .round))
                .padding(size * 0.26)
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .shadow(color: .white.opacity(0.35), radius: 10)
        .onAppear {
            if reduceMotion { circle = 1; tick = 1; scale = 1; return }
            withAnimation(.easeOut(duration: 0.35)) { circle = 1 }
            withAnimation(.easeOut(duration: 0.25).delay(0.35)) { tick = 1 }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.3)) { scale = 1 }
        }
        .accessibilityHidden(true)
    }

    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.12))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
            return path
        }
    }
}

struct EmptyTemplate: View {
    let title: String
    var subtitle = L10n.tr("扫描完成——没有需要清理的内容", "Scan complete — nothing to clean up", "Сканирование завершено — очищать нечего")
    let intro: ModuleIntro
    let palette: ModulePalette
    let onDone: () -> Void

    var body: some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                TemplateHero(palette: palette, symbol: intro.heroSymbol, illustration: intro.artName, motion: .floating,
                             diameter: space.heroDiameter)
                    .position(space.heroCenter)
                VStack(alignment: .leading, spacing: 8) {
                    TemplateTitle(text: title)
                    Text(subtitle)
                        .font(TypeScale.introSubtitle)
                        .foregroundStyle(TypeScale.secondaryText)
                        .staggerIn(1)
                }
                .frame(width: space.textWidth, alignment: .leading)
                .offset(x: space.textLeading, y: space.y(0.36))
                PrimarySlot {
                    PrimaryButton(label: L10n.tr("完成", "Done", "Готово"), action: onDone)
                }
            }
        }
    }
}

/// Access is missing (UI_SPEC §8): what's blocked, why, and the fix.
struct PermissionCard: View {
    var title = L10n.tr("需要完全磁盘访问权限", "Full Disk Access needed", "Требуется полный доступ к диску")
    var message = L10n.tr(
        "macOS 正在阻止访问此位置。请为 \(MCConstants.appName) 授予完全磁盘访问权限，然后重新扫描。",
        "macOS is blocking access to this location. Grant \(MCConstants.appName) Full Disk Access, then scan again.",
        "macOS блокирует доступ к этому расположению. Предоставьте \(MCConstants.appName) полный доступ к диску и повторите сканирование.")
    let palette: ModulePalette
    let onOpenSettings: (() -> Void)?
    let onRescan: () -> Void
    let onDone: () -> Void

    var body: some View {
        CardSpaceReader { space in
            ZStack(alignment: .topLeading) {
                HeroDisc(palette: palette, symbol: "lock", diameter: space.heroDiameter)
                    .position(space.heroCenter)
                VStack(alignment: .leading, spacing: 10) {
                    TemplateTitle(text: title)
                    Text(message)
                        .font(TypeScale.introSubtitle)
                        .foregroundStyle(TypeScale.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        if let onOpenSettings {
                            Button(L10n.tr("打开设置", "Open Settings", "Открыть настройки"), action: onOpenSettings)
                                .buttonStyle(.secondaryPill)
                        }
                        Button(L10n.tr("完成", "Done", "Готово"), action: onDone)
                            .buttonStyle(.ghostPill)
                    }
                    .padding(.top, 8)
                }
                .frame(width: space.textWidth, alignment: .leading)
                .offset(x: space.textLeading, y: space.y(0.32))
                PrimarySlot {
                    PrimaryButton(label: L10n.tr("重新扫描", "Rescan", "Сканировать снова"), action: onRescan)
                }
            }
        }
    }
}

/// Slim amber banner at the top of the module area (UI_SPEC §8).
struct ErrorBanner: View {
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: 0xF8C04E))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(TypeScale.primaryText)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let actionLabel, let action {
                Button(actionLabel, action: action).buttonStyle(.ghostPill)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(TypeScale.secondaryText)
                .accessibilityLabel(L10n.tr("关闭", "Dismiss", "Закрыть"))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(hex: 0xF8C04E).opacity(0.5), lineWidth: 1))
    }
}
