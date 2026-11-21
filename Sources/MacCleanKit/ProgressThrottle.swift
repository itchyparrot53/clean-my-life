import Foundation

/// A thread-safe 10 Hz gate for scan progress updates (UI_SPEC §10).
/// Scan engines can produce thousands of updates a second; the UI only needs
/// ten. Phase changes should bypass the gate and always be delivered.
public final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let interval: TimeInterval
    private var last = Date.distantPast

    public init(interval: TimeInterval = 0.1) {
        self.interval = interval
    }

    /// True at most once per interval.
    public func ready() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(last) >= interval else { return false }
        last = now
        return true
    }
}
