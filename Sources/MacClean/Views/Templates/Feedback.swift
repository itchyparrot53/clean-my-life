import AppKit
import SwiftUI
import MacCleanKit

// Clean1 dialogs and feedback (UI_SPEC §8).

// MARK: - Undo toast (A26)

/// One toast at a time, shown at the bottom centre of the card above the
/// primary button. After a clean it offers Undo, which puts the last
/// cleaning session back from the Trash via Mac Sai's Clean History.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        var action: String?
    }

    private(set) var current: Toast?
    private var undoSession: UUID?
    private var dismissTask: Task<Void, Never>?

    /// Call after something was moved to the Trash.
    func movedToTrash(_ what: String) {
        // The newest session recorded in the last minute is the one just made.
        let session = CleanHistoryRecorder.load()
            .filter { Date().timeIntervalSince($0.date) < 60 }
            .max { $0.date < $1.date }
        undoSession = session?.id
        show(Toast(message: "Moved \(what) to the Trash", action: session == nil ? nil : L10n.tr("撤销", "Undo", "Отменить")))
    }

    func show(_ toast: Toast, for seconds: Double = 8) {
        current = toast
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { current = nil }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }

    func performAction() {
        guard let id = undoSession,
              let session = CleanHistoryRecorder.load().first(where: { $0.id == id }) else { return }
        undoSession = nil
        show(Toast(message: L10n.tr("正在放回…", "Putting things back…", "Возвращаем…")), for: 30)
        Task { @MainActor in
            guard let activity = try? await AppOperationActivity.shared.begin() else { return }
            defer { AppOperationActivity.shared.end(activity) }
            let summary = await Task.detached { CleanHistoryRecorder.restore(session) }.value
            let message = summary.failed == 0
                ? "Put back \(summary.restored) item\(summary.restored == 1 ? "" : "s")"
                : "Put back \(summary.restored); \(summary.failed) couldn't be moved"
            show(Toast(message: message))
        }
    }
}

extension EnvironmentValues {
    @Entry var toasts: ToastCenter?
}

/// A26: slides up 20 pt and fades in; fades out after 8 s.
struct ToastView: View {
    let center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = center.current {
                HStack(spacing: 10) {
                    Text(toast.message)
                        .font(.system(size: 12, weight: .medium))
                    if let action = toast.action {
                        Text("·").foregroundStyle(TypeScale.tertiaryText)
                        Button(action, action: center.performAction)
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x5CC8F0))
                    }
                    Button(action: center.dismiss) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TypeScale.tertiaryText)
                    .accessibilityLabel(L10n.tr("关闭", "Dismiss", "Закрыть"))
                }
                .foregroundStyle(TypeScale.primaryText)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Color.black.opacity(0.45))
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .id(toast.id)
                .transition(reduceMotion ? .opacity : .offset(y: 20).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: center.current)
    }
}

// MARK: - In-card dialog

extension View {
    /// A centred panel over the module area, which dims behind it. Used for
    /// confirmations instead of system sheets, which sit awkwardly on our
    /// transparent window.
    func cardDialog<Dialog: View>(isPresented: Binding<Bool>, @ViewBuilder dialog: @escaping () -> Dialog) -> some View {
        self
            .opacity(isPresented.wrappedValue ? Surface.dimmed : 1)
            .allowsHitTesting(!isPresented.wrappedValue)
            .overlay {
                if isPresented.wrappedValue {
                    dialog()
                        .padding(22)
                        .frame(width: 440)
                        .background {
                            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                            ZStack {
                                shape.fill(.ultraThinMaterial)
                                shape.fill(Color.black.opacity(0.32))
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
                        .foregroundStyle(TypeScale.primaryText)
                        .environment(\.colorScheme, .dark)
                        .onExitCommand { isPresented.wrappedValue = false }
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isPresented.wrappedValue)
    }
}

// MARK: - Confirm clean (§8)

enum CleanConfirmation {
    static let skipSafeKey = "clean1.confirm.skipSafe"

    /// Ask unless the user turned that off and everything selected is in a
    /// category that regenerates or is safe to remove.
    static func isNeeded(results: [ScanResult], selection: Set<URL>) -> Bool {
        guard UserDefaults.standard.bool(forKey: skipSafeKey) else { return true }
        if selection.count > MCConstants.cleanConfirmationThreshold { return true }
        return results.contains { result in
            result.category.cleanupSafety == .reviewFirst && result.items.contains { selection.contains($0.url) }
        }
    }

    /// Open apps that own selected items, found off the main thread.
    static func runningOwners(results: [ScanResult], selection: Set<URL>) async -> [NSRunningApplication] {
        let running = NSWorkspace.shared.runningApplications
        let ids = Set(running.compactMap(\.bundleIdentifier))
        let selected = results.map { result in
            ScanResult(category: result.category, items: result.items.filter { selection.contains($0.url) },
                       autoSelect: result.autoSelect)
        }
        let owners: Set<String> = await Task.detached(priority: .userInitiated) {
            let urls = AppCacheOwnership.runningOwnedURLs(in: selected, runningBundleIDs: ids)
            return Set(urls.compactMap(AppCacheOwnership.owningBundleID(for:)))
        }.value
        return running.filter { $0.bundleIdentifier.map(owners.contains) ?? false }
    }
}

/// Totals per category, the open apps that own some of it, and the buttons.
struct ConfirmCleanDialog: View {
    let results: [ScanResult]
    let selection: Set<URL>
    let runningApps: [NSRunningApplication]
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @AppStorage(CleanConfirmation.skipSafeKey) private var skipSafe = false
    @State private var quitting = false

    private var rows: [(ScanCategory, Int, UInt64)] {
        results.compactMap { result in
            let chosen = result.items.filter { selection.contains($0.url) }
            guard !chosen.isEmpty else { return nil }
            return (result.category, chosen.count, chosen.reduce(0) { $0 + $1.size })
        }
        .sorted { $0.2 > $1.2 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("移到废纸篓？", "Move to the Trash?", "Переместить в Корзину?"))
                .font(.system(size: 17, weight: .semibold))
            VStack(spacing: 6) {
                ForEach(rows.prefix(8), id: \.0) { category, count, bytes in
                    HStack(spacing: 8) {
                        CategoryTile(symbol: category.tileSymbol, tint: ModulePalette.cleanup.top, size: 20)
                        Text(category.displayName).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Text("\(count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(TypeScale.tertiaryText)
                        Text(FileSizeFormatter.format(bytes)).font(.system(size: 12).monospacedDigit())
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                }
                if rows.count > 8 {
                    Text("and \(rows.count - 8) more").font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider().overlay(Surface.hairline)
                HStack {
                    Text(L10n.tr("合计", "Total", "Итого")).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(FileSizeFormatter.format(rows.reduce(0) { $0 + $1.2 }))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                }
            }

            if !runningApps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("These apps are open and may rewrite their files:", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0xF8C04E))
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        HStack(spacing: 8) {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                            Text(app.localizedName ?? "").font(.system(size: 12))
                            Spacer()
                            Button(L10n.tr("退出", "Quit", "Завершить")) { app.terminate() }.buttonStyle(.ghostPill)
                        }
                    }
                }
            }

            Toggle(L10n.tr("安全项目不再询问", "Don't ask again for safe items", "Не спрашивать для безопасных"), isOn: $skipSafe)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            HStack {
                Spacer()
                Button(L10n.tr("取消", "Cancel", "Отмена"), action: onCancel)
                    .buttonStyle(.ghostPill)
                    .keyboardShortcut(.cancelAction)
                if !runningApps.isEmpty {
                    Button(L10n.tr("全部退出并继续", "Quit All & Continue", "Завершить все и продолжить")) {
                        quitAllThenConfirm()
                    }
                    .buttonStyle(.secondaryPill)
                    .disabled(quitting)
                }
                Button(L10n.tr("移到废纸篓", "Move to Trash", "В Корзину"), action: onConfirm)
                    .buttonStyle(.secondaryPill)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Ask each open app to quit, give them a moment, then clean.
    private func quitAllThenConfirm() {
        quitting = true
        runningApps.forEach { $0.terminate() }
        Task { @MainActor in
            for _ in 0..<30 where runningApps.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            quitting = false
            onConfirm()
        }
    }
}
