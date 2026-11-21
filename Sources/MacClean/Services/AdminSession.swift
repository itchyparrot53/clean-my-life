import Foundation
import MacCleanKit

/// One administrator approval shared by the app's privileged actions.
///
/// macOS caches `do shell script … with administrator privileges` for about
/// five minutes per process. Running the approval in-process and routing
/// Maintenance and Wi-Fi through the same runner means the user approves once
/// and those tasks reuse the cached right instead of each spawning a fresh
/// `osascript` prompt.
///
/// This is not a replacement for a signed privileged helper: a helper can ask
/// once per install, while this asks again after the system cache expires.
@MainActor
final class AdminSession {
    static let shared = AdminSession()

    private let runner = AppleScriptPrivilegedRunner()
    private(set) var approvedUntil: Date?

    var isApproved: Bool {
        guard let approvedUntil else { return false }
        return approvedUntil > Date()
    }

    /// Warm the system cache with a harmless root command.
    func approve() async -> Bool {
        let result = await runner.run(commandLine: "/usr/bin/true")
        if result.success {
            approvedUntil = Date().addingTimeInterval(300)
            return true
        }
        approvedUntil = nil
        return false
    }

    func run(_ commandLine: String) async -> PrivilegedShellResult {
        let result = await runner.run(commandLine: commandLine)
        if result.success { approvedUntil = Date().addingTimeInterval(300) }
        return result
    }
}
