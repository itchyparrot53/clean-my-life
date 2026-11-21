import AppKit
import Foundation

/// Browser Tabs v1 (UI_SPEC §5.22): reads open tabs from Safari and the
/// Chromium browsers through AppleScript, and closes the ones you select.
///
/// This is the pragmatic bridge until the Chrome/Safari extensions and native
/// messaging land (PLAN §3.13). macOS asks for Automation permission the first
/// time a browser is read. Per-tab memory is not exposed by the browsers, so
/// the UI shows the window and position instead of inventing a number.
struct BrowserTabsScanner: Sendable {
    struct Tab: Identifiable, Hashable, Sendable {
        let browser: String
        let window: Int
        let index: Int
        let title: String
        let url: String
        var isDuplicate = false

        var id: String { "\(browser)|\(window)|\(index)" }
        var domain: String {
            guard let host = URL(string: url)?.host, !host.isEmpty else { return url }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    struct Result: Sendable {
        var tabs: [Tab] = []
        var errors: [String] = []
    }

    private struct Browser {
        let app: String
        let bundle: String
        /// Safari calls it `name`; Chromium calls it `title`.
        let titleKey: String
    }

    private static let browsers: [Browser] = [
        Browser(app: "Safari", bundle: "com.apple.Safari", titleKey: "name"),
        Browser(app: "Google Chrome", bundle: "com.google.Chrome", titleKey: "title"),
        Browser(app: "Brave Browser", bundle: "com.brave.Browser", titleKey: "title"),
        Browser(app: "Microsoft Edge", bundle: "com.microsoft.edgemac", titleKey: "title"),
    ]

    @MainActor
    func scan() -> Result {
        var result = Result()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for browser in Self.browsers where running.contains(browser.bundle) {
            let script = Self.readScript(browser)
            let outcome = Self.run(script)
            switch outcome {
            case .success(let text):
                result.tabs += Self.parse(text, browser: browser.app)
            case .failure(let message):
                result.errors.append("\(browser.app): \(message)")
            }
        }
        Self.markDuplicates(&result.tabs)
        return result
    }

    /// Closes the selected tabs. Indices shift after a close, so each window
    /// closes from the highest index down.
    @MainActor
    func close(_ tabs: [Tab]) -> [String] {
        var errors: [String] = []
        let groups = Dictionary(grouping: tabs) { "\($0.browser)|\($0.window)" }
        for (_, group) in groups {
            guard let first = group.first, let browser = Self.browsers.first(where: { $0.app == first.browser }) else { continue }
            let indices = group.map(\.index).sorted(by: >)
            let script = """
            tell application "\(browser.app)"
              repeat with i in {\(indices.map(String.init).joined(separator: ", "))}
                try
                  close tab i of window \(first.window)
                end try
              end repeat
            end tell
            """
            if case .failure(let message) = Self.run(script) {
                errors.append("\(browser.app): \(message)")
            }
        }
        return errors
    }

    // MARK: AppleScript

    private static func readScript(_ browser: Browser) -> String {
        """
        set sep to ASCII character 9
        set eol to ASCII character 10
        tell application "\(browser.app)"
          set output to ""
          set wi to 0
          repeat with w in windows
            set wi to wi + 1
            set ti to 0
            repeat with t in tabs of w
              set ti to ti + 1
              set output to output & wi & sep & ti & sep & (\(browser.titleKey) of t as text) & sep & (URL of t as text) & eol
            end repeat
          end repeat
          return output
        end tell
        """
    }

    private enum RunOutcome {
        case success(String)
        case failure(String)
    }

    @MainActor
    private static func run(_ source: String) -> RunOutcome {
        guard let script = NSAppleScript(source: source) else {
            return .failure("could not build the AppleScript")
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            if number == -1743 {
                return .failure("Automation access was denied. Enable it in System Settings, Privacy & Security, Automation.")
            }
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(number)"
            return .failure(message)
        }
        return .success(descriptor.stringValue ?? "")
    }

    // MARK: Parsing

    static func parse(_ text: String, browser: String) -> [Tab] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 4,
                  let window = Int(fields[0]), let index = Int(fields[1]) else { return nil }
            return Tab(browser: browser, window: window, index: index,
                       title: String(fields[2]), url: String(fields[3]))
        }
    }

    static func markDuplicates(_ tabs: inout [Tab]) {
        var seen = Set<String>()
        for index in tabs.indices {
            let key = tabs[index].url
            if seen.contains(key) { tabs[index].isDuplicate = true } else { seen.insert(key) }
        }
    }
}
