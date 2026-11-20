import AppKit
import SwiftUI
import MacCleanKit

/// Activity (UI_SPEC §5.23), built on Mac Sai's Clean History: four big
/// metrics, a timeline of cleans with Undo where items are still in the
/// Trash, and a Mac health card.
struct ActivityView: View {
    @State private var sessions: [CleanHistorySession] = []
    @State private var pendingRestore: CleanHistorySession?
    @State private var restoring: UUID?
    @State private var lastSummary: CleanHistoryRestoreSummary?
    @State private var confirmClear = false
    @State private var health = MacHealth.measure()

    private var allTime: UInt64 { sessions.reduce(0) { $0 + $1.totalBytes } }
    private var thisMonth: UInt64 {
        let start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? .distantPast
        return sessions.filter { $0.date >= start }.reduce(0) { $0 + $1.totalBytes }
    }
    private var itemsRemoved: Int { sessions.reduce(0) { $0 + $1.items.count + ($1.omittedCount ?? 0) } }

    var body: some View {
        CardSpaceReader { space in
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.tr("活动", "Activity", "Активность")).font(TypeScale.reviewTitle)
                    Spacer()
                    Button(L10n.tr("清除历史", "Clear History", "Очистить историю")) { confirmClear = true }
                        .buttonStyle(.ghostPill)
                        .disabled(sessions.isEmpty)
                }
                HStack(spacing: 0) {
                    metric(FileSizeFormatter.format(allTime), "freed all time")
                    metric(FileSizeFormatter.format(thisMonth), "this month")
                    metric("\(itemsRemoved.formatted())", "items removed")
                    metric("\(sessions.count)", "cleans")
                }
                .staggerIn(0)

                HStack(alignment: .top, spacing: 18) {
                    timeline
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .staggerIn(1)
                    healthCard
                        .frame(width: 230)
                        .staggerIn(2)
                }
            }
            .foregroundStyle(TypeScale.primaryText)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .topBarTitle(L10n.tr("活动", "Activity", "Активность"))
        .task { await reload() }
        .alert(L10n.tr("放回这些项目？", "Put these items back?", "Вернуть эти объекты?"),
               isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
               presenting: pendingRestore) { session in
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) { pendingRestore = nil }
            Button(L10n.tr("放回", "Put Back", "Вернуть")) { restore(session) }
        } message: { session in
            Text(CleanHistoryView.restoreMessage(for: session))
        }
        .alert(L10n.tr("清除历史？", "Clear history?", "Очистить историю?"), isPresented: $confirmClear) {
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) {}
            Button(L10n.tr("清除", "Clear", "Очистить"), role: .destructive) {
                CleanHistoryRecorder.clear()
                sessions = []
            }
        } message: {
            Text("Items stay in the Trash, but you won't be able to put them back from here.")
        }
        .alert(L10n.tr("恢复完成", "Restore finished", "Восстановление завершено"),
               isPresented: Binding(get: { lastSummary != nil }, set: { if !$0 { lastSummary = nil } }),
               presenting: lastSummary) { _ in
            Button("OK", role: .cancel) { lastSummary = nil }
        } message: { summary in
            Text("Put back \(summary.restored). " + (summary.failed > 0 ? "\(summary.failed) couldn't be moved." : ""))
        }
    }

    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(TypeScale.bigMetric).numericRoll(value).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent cleans").font(.system(size: 12, weight: .semibold)).foregroundStyle(TypeScale.secondaryText)
            if sessions.isEmpty {
                Text("Nothing cleaned yet.")
                    .font(.system(size: 13)).foregroundStyle(TypeScale.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .cardList()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sessions.sorted { $0.date > $1.date }) { session in row(session) }
                    }
                }
                .cardList()
            }
        }
    }

    private func row(_ session: CleanHistorySession) -> some View {
        let restorable = session.items.contains { FileManager.default.fileExists(atPath: $0.trashPath) }
        return HStack(spacing: 10) {
            Circle().fill(restorable ? Color(hex: 0x5CC8F0) : Color.white.opacity(0.3)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(TypeScale.row)
                Text("\(session.items.count + (session.omittedCount ?? 0)) items · \(FileSizeFormatter.format(session.totalBytes))")
                    .font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
            }
            Spacer()
            if restoring == session.id {
                ProgressView().controlSize(.small)
            } else if restorable {
                Button(L10n.tr("撤销", "Undo", "Отменить")) { pendingRestore = session }
                    .buttonStyle(.ghostPill)
                    .disabled(restoring != nil)
            } else {
                Text("Emptied").font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    /// Score ring plus the factors behind it.
    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mac health").font(.system(size: 12, weight: .semibold)).foregroundStyle(TypeScale.secondaryText)
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 6)
                    Circle().trim(from: 0, to: Double(health.score) / 100)
                        .stroke(health.score >= 75 ? Color(hex: 0x5EE6A0) : Color(hex: 0xF8C04E),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(health.score)").font(.system(size: 22, weight: .light).monospacedDigit())
                }
                .frame(width: 70, height: 70)
                Text(health.score >= 90 ? "Looking good" : health.score >= 75 ? "Mostly fine" : "Worth a look")
                    .font(.system(size: 14, weight: .semibold))
            }
            ForEach(health.factors, id: \.name) { factor in
                HStack(spacing: 6) {
                    Image(systemName: factor.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(factor.ok ? Color(hex: 0x5EE6A0) : Color(hex: 0xF8C04E))
                        .font(.system(size: 11))
                    Text(factor.name).font(.system(size: 11))
                    Spacer()
                    Text(factor.detail).font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func reload() async {
        sessions = await Task.detached { CleanHistoryRecorder.load() }.value
        health = MacHealth.measure()
    }

    private func restore(_ session: CleanHistorySession) {
        pendingRestore = nil
        restoring = session.id
        Task { @MainActor in
            defer { restoring = nil }
            guard let activity = try? await AppOperationActivity.shared.begin() else { return }
            defer { AppOperationActivity.shared.end(activity) }
            lastSummary = await Task.detached { CleanHistoryRecorder.restore(session) }.value
            await reload()
        }
    }
}

/// A simple, explainable health score from things the main app can see.
struct MacHealth {
    struct Factor { let name: String; let ok: Bool; let detail: String }
    let score: Int
    let factors: [Factor]

    static func measure() -> MacHealth {
        var factors: [Factor] = []
        var score = 100
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let values = try? URL(filePath: "/").resourceValues(forKeys: keys),
           let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacityForImportantUsage, total > 0 {
            let fraction = Double(free) / Double(total)
            let ok = fraction > 0.15
            if !ok { score -= fraction < 0.05 ? 35 : 20 }
            factors.append(Factor(name: "Free space", ok: ok, detail: "\(Int((fraction * 100).rounded())) %"))
        }
        if let protection = SharedAppState.protectionStatus {
            let ok = protection.threatsFound == 0
            if !ok { score -= 30 }
            factors.append(Factor(name: "Threats", ok: ok, detail: ok ? "None" : "\(protection.threatsFound)"))
            let stale = Date().timeIntervalSince(protection.lastScanDate) > 30 * 24 * 3600
            if stale { score -= 5 }
            factors.append(Factor(name: "Last malware scan", ok: !stale,
                                  detail: protection.lastScanDate.formatted(.relative(presentation: .named))))
        } else {
            score -= 5
            factors.append(Factor(name: "Malware scan", ok: false, detail: "Never"))
        }
        let pressure = ProcessInfo.processInfo.thermalState
        let cool = pressure == .nominal || pressure == .fair
        if !cool { score -= 10 }
        factors.append(Factor(name: "Temperature", ok: cool, detail: cool ? "Normal" : "High"))
        return MacHealth(score: max(0, score), factors: factors)
    }
}
