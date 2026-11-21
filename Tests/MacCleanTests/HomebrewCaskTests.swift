import XCTest
import Foundation

/// Guards issue #147: Homebrew deprecated `url … verified:` (brew#23280).
/// A stale `verified:` here resurfaces as a `brew update` warning when the
/// cask is published.
final class HomebrewCaskTests: XCTestCase {

    private var caskSource: String {
        get throws {
            let url = URL(filePath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Casks/clean-my-life.rb")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testCaskHasNoDeprecatedVerifiedParameter() throws {
        let src = try caskSource
        // Match the Homebrew url kwarg form (`verified: "…"`). Single-quoted
        // values are unused in this cask; official homebrew/cask omits it.
        let deprecated = src.range(
            of: #"\bverified:\s*""#,
            options: .regularExpression
        )
        XCTAssertNil(
            deprecated,
            "Casks/clean-my-life.rb must not use the deprecated url verified: parameter (issue #147)"
        )
    }

    func testCaskUrlPointsAtGitHubReleaseDMG() throws {
        let src = try caskSource
        XCTAssertTrue(
            src.contains("url \"https://github.com/itchyparrot53/clean-my-life/releases/download/v#{version}/CleanMyLife-#{version}.dmg\""),
            "Casks/clean-my-life.rb must download the GitHub release DMG"
        )
    }

    func testCaskDeclaresRequiredStanzas() throws {
        let src = try caskSource
        for needle in ["cask \"clean-my-life\"", "version ", "sha256 ", "homepage ", "app \"Clean My Life.app\""] {
            XCTAssertTrue(src.contains(needle), "Casks/clean-my-life.rb missing \(needle)")
        }
    }
}
