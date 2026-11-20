import XCTest
@testable import MacClean

final class KeyboardShortcutRoutingTests: XCTestCase {

    func testShortcutDigitsMapFirstNineModulesExcludingSettings() {
        // Clean1: ⌘1–⌘9 follow the first nine rows of the sidebar as shown.
        let items = SidebarItem.keyboardShortcutItems
        XCTAssertEqual(items, Array(SidebarSection.allCases.flatMap(\.items).prefix(9)))
        XCTAssertEqual(items.count, 9)
        XCTAssertFalse(items.contains(.settings))
        XCTAssertEqual(items.first, .smartScan)
        XCTAssertEqual(SidebarItem.item(forShortcutDigit: 1), .smartScan)
        XCTAssertEqual(SidebarItem.item(forShortcutDigit: 2), .systemJunk)
        XCTAssertEqual(SidebarItem.item(forShortcutDigit: 3), .aiClutter)
        XCTAssertEqual(SidebarItem.item(forShortcutDigit: 8), .appPermissions)
        XCTAssertEqual(SidebarItem.item(forShortcutDigit: 9), .optimization)
        XCTAssertEqual(SidebarItem.item(forShortcutDigit: 9), items[8])
        XCTAssertFalse(items.contains(.uninstaller))
        XCTAssertFalse(items.contains(.extensions))
        // Tools and footer modules never take a digit.
        for item in SidebarItem.toolItems + [SidebarItem.activityItem] {
            XCTAssertFalse(items.contains(item))
        }
    }

    func testEveryModuleIsReachableFromTheSidebar() {
        let reachable = Set(SidebarSection.allCases.flatMap(\.items) + SidebarItem.toolItems
            + [SidebarItem.activityItem, .tools, .settings])
        XCTAssertEqual(reachable, Set(SidebarItem.allCases))
    }

    func testShortcutDigitsRejectOutOfRange() {
        XCTAssertNil(SidebarItem.item(forShortcutDigit: 0))
        XCTAssertNil(SidebarItem.item(forShortcutDigit: -1))
        XCTAssertNil(SidebarItem.item(forShortcutDigit: 10))
        XCTAssertNil(SidebarItem.item(forShortcutDigit: 99))
    }

    func testAppStateShortcutNoncesIncrement() {
        let state = AppState()
        XCTAssertEqual(state.scanShortcutNonce, 0)
        XCTAssertEqual(state.cleanShortcutNonce, 0)
        state.requestScanShortcut()
        state.requestScanShortcut()
        state.requestCleanShortcut()
        XCTAssertEqual(state.scanShortcutNonce, 2)
        XCTAssertEqual(state.cleanShortcutNonce, 1)
    }

    /// Review on #125: when Duplicates shows results it mounts BOTH an outer
    /// `respondsToModuleShortcuts` and ModuleContainerView's own modifier.
    /// Only one listener may accept ⌘K, or `clean()` runs twice.
    func testDuplicatesResultsCleanHasSingleOwner() {
        // Idle / no container: outer may scan, but clean is never outer-owned.
        XCTAssertEqual(
            DuplicatesShortcutOwnership.cleanOwner(showingContainerResults: false),
            .none
        )
        // Results on screen: container owns ⌘K exclusively.
        XCTAssertEqual(
            DuplicatesShortcutOwnership.cleanOwner(showingContainerResults: true),
            .container
        )

        // Simulate one nonce bump with both listeners evaluating their gates
        // the way the bug did (outerCanClean && innerCanClean both true).
        let outerCanClean = DuplicatesShortcutOwnership.outerCanClean
        let innerCanClean = true // container with selection
        var cleanInvocations = 0
        if outerCanClean { cleanInvocations += 1 }
        if innerCanClean { cleanInvocations += 1 }
        XCTAssertEqual(cleanInvocations, 1, "⌘K must invoke clean() exactly once")
        XCTAssertFalse(outerCanClean)
    }

    /// Source guard so a future edit doesn't re-enable outer ⌘K on Duplicates.
    func testDuplicatesViewOuterModifierDisablesCanClean() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/MacClean/Views/Files/DuplicatesView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        // The outer respondsToModuleShortcuts must hard-disable clean.
        let pattern = #"respondsToModuleShortcuts\([\s\S]*?canClean:\s*false"#
        XCTAssertNotNil(
            src.range(of: pattern, options: .regularExpression),
            "DuplicatesView outer shortcut modifier must set canClean: false so ModuleContainerView alone handles ⌘K"
        )
    }
}
