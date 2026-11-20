import AppKit
import SwiftUI
import MacCleanKit

/// Screen Cleaning Mode (UI_SPEC §6.1): every display goes black for two
/// minutes so you can wipe the screen and keyboard without clicking or typing
/// into anything. Hold Esc for 2 s to leave early. (The spec's ⌘⌥Esc is the
/// system Force Quit shortcut, so holding it would open that window instead.)
@MainActor
final class ScreenCleaning {
    static let shared = ScreenCleaning()

    private var windows: [NSWindow] = []
    private var monitor: Any?
    private var escDown: Date?
    private var endTask: Task<Void, Never>?
    static let duration: TimeInterval = 120

    var isActive: Bool { !windows.isEmpty }

    func start() {
        guard !isActive else { return }
        let started = Date()
        for screen in NSScreen.screens {
            let window = KeyableWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = NSHostingView(rootView: ScreenCleaningView(started: started, isMain: screen == NSScreen.main))
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.hide()
        // Swallow every key so wiping the keyboard types nothing; watch Esc.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return nil
        }
        endTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.duration))
            self?.stop()
        }
    }

    func stop() {
        endTask?.cancel()
        endTask = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.unhide()
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == 53 else { return } // Esc
        if event.type == .keyDown {
            if escDown == nil { escDown = Date() }
            if let down = escDown, Date().timeIntervalSince(down) >= 2 { stop() }
        } else if event.type == .keyUp {
            escDown = nil
        }
    }
}

/// Message and the 2:00 countdown ring (A25: trim 1 → 0, linear).
private struct ScreenCleaningView: View {
    let started: Date
    let isMain: Bool

    var body: some View {
        ZStack {
            Color.black
            if isMain {
                TimelineView(.periodic(from: started, by: 0.25)) { context in
                    let elapsed = context.date.timeIntervalSince(started)
                    let remaining = max(0, ScreenCleaning.duration - elapsed)
                    VStack(spacing: 22) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: remaining / ScreenCleaning.duration)
                                .stroke(Color(hex: 0xA8E6FF).opacity(0.8), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.25), value: remaining)
                            Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60))
                                .font(.system(size: 28, weight: .light).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(width: 140, height: 140)
                        Text("Wipe away. The screen and keyboard are switched off for two minutes.")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Hold Esc for 2 seconds to finish early.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Borderless windows can't take key status by default; this one must, so
/// keystrokes land here instead of in another app.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
