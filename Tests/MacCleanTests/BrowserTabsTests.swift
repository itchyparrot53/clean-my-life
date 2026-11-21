import XCTest
@testable import MacClean

final class BrowserTabsTests: XCTestCase {
    func testParsesTheAppleScriptDump() {
        let output = """
        1\t1\tDocs - Apple\thttps://developer.apple.com/documentation
        1\t2\tGmail\thttps://mail.google.com/mail/u/0
        2\t1\tDuplicate\thttps://mail.google.com/mail/u/0
        malformed
        """
        let tabs = BrowserTabsScanner.parse(output, browser: "Safari")
        XCTAssertEqual(tabs.count, 3)
        XCTAssertEqual(tabs[1].window, 1)
        XCTAssertEqual(tabs[1].index, 2)
        XCTAssertEqual(tabs[1].title, "Gmail")
        XCTAssertEqual(tabs[1].url, "https://mail.google.com/mail/u/0")
        XCTAssertEqual(tabs[1].domain, "mail.google.com")
        XCTAssertEqual(tabs[1].id, "Safari|1|2")
    }

    func testMarksLaterDuplicateURLs() {
        var tabs = [
            BrowserTabsScanner.Tab(browser: "Safari", window: 1, index: 1, title: "A", url: "https://example.com/a"),
            BrowserTabsScanner.Tab(browser: "Chrome", window: 1, index: 1, title: "A again", url: "https://example.com/a"),
            BrowserTabsScanner.Tab(browser: "Safari", window: 1, index: 2, title: "B", url: "https://example.com/b"),
        ]
        BrowserTabsScanner.markDuplicates(&tabs)
        XCTAssertFalse(tabs[0].isDuplicate)
        XCTAssertTrue(tabs[1].isDuplicate)
        XCTAssertFalse(tabs[2].isDuplicate)
    }

    func testStripsWwwFromTheDomain() {
        let tab = BrowserTabsScanner.Tab(browser: "Safari", window: 1, index: 1,
                                         title: "Example", url: "https://www.example.com/path")
        XCTAssertEqual(tab.domain, "example.com")
    }
}
