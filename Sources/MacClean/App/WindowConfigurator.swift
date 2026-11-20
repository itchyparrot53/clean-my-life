import AppKit
import SwiftUI
import MacCleanKit

/// Turns the main window into Clean1's floating card (UI_SPEC §1.1): a
/// transparent, shadowless window whose content draws the card, the
/// overhanging sidebar and their shadows. Moves the traffic lights onto the
/// card and keeps them there through resizes and key changes.
struct WindowConfigurator: NSViewRepresentable {
    /// Where the close button's top-left corner goes, measured from the
    /// window's top-left corner.
    var trafficLightOrigin: CGPoint
    /// Card and sidebar, in window coordinates from the top-left. Clicks
    /// anywhere else in the window fall through to whatever is behind it.
    var interactiveRects: [CGRect]
    var onFullScreenChange: (Bool) -> Void

    func makeCoordinator() -> WindowChrome { WindowChrome() }

    static func dismantleNSView(_ nsView: NSView, coordinator: WindowChrome) {
        coordinator.detach()
    }

    func makeNSView(context: Context) -> NSView {
        let view = HostView()
        view.chrome = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let chrome = context.coordinator
        chrome.trafficLightOrigin = trafficLightOrigin
        chrome.interactiveRects = interactiveRects
        chrome.onFullScreenChange = onFullScreenChange
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            chrome.attach(to: window)
        }
    }

    private final class HostView: NSView {
        weak var chrome: WindowChrome?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            chrome?.attach(to: window)
        }
    }
}

@MainActor
final class WindowChrome: NSObject {
    var trafficLightOrigin: CGPoint = .zero {
        didSet { if oldValue != trafficLightOrigin { positionTrafficLights() } }
    }
    var interactiveRects: [CGRect] = []
    var onFullScreenChange: (Bool) -> Void = { _ in }

    /// Width of the strip along the window's edge that stays clickable so
    /// the window can still be resized.
    private let resizeBand: CGFloat = 6

    private weak var window: NSWindow?
    private var mouseMonitors: [Any] = []
    /// The title bar container we're following. AppKit can swap it for a
    /// new one (zoom, full screen), so the observer moves with it.
    private weak var observedContainer: NSView?
    private var containerObservers: [NSObjectProtocol] = []
    private var observers: [NSObjectProtocol] = []
    private var isPositioning = false

    func attach(to window: NSWindow) {
        if self.window !== window {
            self.window = window
            observe(window)
        }
        style(window)
        positionTrafficLights()
        startClickThrough()
    }

    // MARK: Click-through (UI_SPEC §1.1)

    /// The card's shadow means the margin is never fully transparent, so the
    /// window server would deliver clicks there to us. Instead, follow the
    /// pointer and let the window ignore the mouse while it's over the margin.
    private func startClickThrough() {
        guard mouseMonitors.isEmpty else { return }
        window?.acceptsMouseMovedEvents = true
        let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseUp, .rightMouseUp]
        if let local = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateClickThrough() }
            return event
        }) {
            mouseMonitors.append(local)
        }
        // While the window ignores the mouse, moves are delivered to other
        // apps; a global monitor still sees them.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateClickThrough() }
        }) {
            mouseMonitors.append(global)
        }
    }

    private func updateClickThrough() {
        guard let window else { return }
        let ignore = shouldIgnoreMouse(in: window)
        if window.ignoresMouseEvents != ignore { window.ignoresMouseEvents = ignore }
    }

    private func shouldIgnoreMouse(in window: NSWindow) -> Bool {
        // Never change it mid-drag or mid-resize, or in full screen.
        guard window.isVisible, NSEvent.pressedMouseButtons == 0,
              !window.styleMask.contains(.fullScreen), window.attachedSheet == nil else { return false }
        let frame = window.frame
        let mouse = NSEvent.mouseLocation
        guard frame.contains(mouse) else { return false }
        let point = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        let size = frame.size
        let onEdge = point.x < resizeBand || point.y < resizeBand
            || point.x > size.width - resizeBand || point.y > size.height - resizeBand
        if onEdge { return false }
        return !interactiveRects.contains { $0.contains(point) }
    }

    func detach() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        containerObservers.forEach(NotificationCenter.default.removeObserver)
        containerObservers.removeAll()
        observedContainer = nil
        window?.ignoresMouseEvents = false
    }

    private func style(_ window: NSWindow) {
        // Real title stays set for Mission Control, the Window menu and
        // VoiceOver; it's just never drawn.
        window.title = MCConstants.appName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        // The card and sidebar draw their own shadows (UI_SPEC §1.1).
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        // SwiftUI marks this window "no full screen"; the spec wants it (§1.2).
        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.insert(.fullScreenPrimary)
    }

    private func observe(_ window: NSWindow) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        let center = NotificationCenter.default
        let relayout: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didChangeScreenNotification,
        ]
        for name in relayout {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.positionTrafficLights()
                    // AppKit lays the title bar out again after these fire
                    // (zoom and full-screen exits animate); catch up once more.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                        MainActor.assumeIsolated { self?.positionTrafficLights() }
                    }
                }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFullScreenChange(true) }
        })
        observers.append(center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFullScreenChange(false) }
        })
        if window.styleMask.contains(.fullScreen) { onFullScreenChange(true) }
    }

    /// The buttons' resting spots inside the title bar, captured before we
    /// move anything (AppKit's default: 9 pt in, 20 pt apart).
    private var buttonOrigins: [CGPoint] = []

    /// Moves the title bar container (which holds the three buttons) so the
    /// close button lands at `trafficLightOrigin`, shrunk to the buttons'
    /// width so the rest of the top band stays clickable for our own top bar.
    /// AppKit re-places the buttons itself on resize as if the title bar were
    /// still full width, so their spots inside the container are pinned too.
    fileprivate func positionTrafficLights() {
        guard !isPositioning,
              let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let titlebar = close.superview,
              let container = titlebar.superview,
              let frameView = container.superview else { return }
        isPositioning = true
        defer { isPositioning = false }
        follow(container, close)

        let buttons = [close, mini, zoom]
        let height = container.frame.height
        if buttonOrigins.isEmpty {
            let current = buttons.map(\.frame.origin)
            let sane = current.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.y + close.frame.height <= height }
            buttonOrigins = sane ? current : [CGPoint(x: 9, y: 6), CGPoint(x: 29, y: 6), CGPoint(x: 49, y: 6)]
        }
        let first = buttonOrigins[0]
        let buttonTop = titlebar.isFlipped ? first.y : height - first.y - close.frame.height
        let width = buttonOrigins[2].x + zoom.frame.width + first.x

        let topInFrame = trafficLightOrigin.y - buttonTop
        let target = NSRect(
            x: trafficLightOrigin.x - first.x,
            y: frameView.isFlipped ? topInFrame : frameView.bounds.height - topInFrame - height,
            width: width,
            height: height)
        if container.frame != target { container.frame = target }
        if titlebar.frame != container.bounds { titlebar.frame = container.bounds }
        for (button, origin) in zip(buttons, buttonOrigins) where button.frame.origin != origin {
            button.setFrameOrigin(origin)
        }
    }
}

extension WindowChrome {
    /// AppKit lays the title bar out again on its own schedule; follow it.
    /// It can also swap the container for a new one (zoom, full screen).
    fileprivate func follow(_ container: NSView, _ close: NSView) {
        guard container !== observedContainer else { return }
        containerObservers.forEach(NotificationCenter.default.removeObserver)
        containerObservers.removeAll()
        observedContainer = container
        for view in [container, close] {
            view.postsFrameChangedNotifications = true
            containerObservers.append(NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: view, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.positionTrafficLights() }
            })
        }
    }
}

/// Drags the window from empty card space; a double-click zooms like a
/// title bar would (UI_SPEC §1.1).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                // Honour System Settings › Desktop & Dock › "Double-click a window's title bar to".
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}
