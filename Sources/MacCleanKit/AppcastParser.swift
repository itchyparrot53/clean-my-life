import Foundation

/// Minimal Sparkle appcast XML parser. Extracts the latest marketing version's
/// `sparkle:shortVersionString`, falling back to `sparkle:version` only when
/// the feed has no marketing versions.
///
/// Sparkle accepts both versions either as `<enclosure>` attributes (Sparkle 1
/// style) or as child elements of `<item>` (what Sparkle 2's `generate_appcast`
/// writes). Like Sparkle itself, the item element wins when both are present.
public final class AppcastParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private static let shortVersionKey = "sparkle:shortVersionString"
    private static let buildVersionKey = "sparkle:version"

    /// Keep marketing and build versions in separate domains. A build such as
    /// 4012 must never outrank a marketing version such as 2.1.0.
    private var bestShortVersion: String?
    private var bestShortDownloadURL: URL?
    private var bestBuildVersion: String?
    private var bestBuildDownloadURL: URL?
    private var inItem = false
    private var inDeltas = false
    private var currentDownloadURL: URL?
    private var currentAttributeShortVersion: String?
    private var currentAttributeBuildVersion: String?
    private var currentElementShortVersion: String?
    private var currentElementBuildVersion: String?
    /// Name of the item-level version element whose text is being collected.
    private var capturingElement: String?
    private var capturedText = ""
    // Clean1: release notes for the newest item (UI_SPEC §5.12).
    private var currentNotes: String?
    private var currentNotesURL: URL?
    private var bestShortNotes: String?
    private var bestShortNotesURL: URL?
    private var bestBuildNotes: String?
    private var bestBuildNotesURL: URL?
    /// Plain-text release notes of the item `parseLatestItem` picked, if any.
    public private(set) var latestReleaseNotes: String?
    /// Link to the release notes of that item, if the feed gives one.
    public private(set) var latestReleaseNotesURL: URL?

    public override init() { super.init() }

    public func parseLatestVersion(from data: Data) -> String? {
        parseLatestItem(from: data).version
    }

    public func parseLatestItem(from data: Data) -> (version: String?, downloadURL: URL?) {
        bestShortVersion = nil
        bestShortDownloadURL = nil
        bestBuildVersion = nil
        bestBuildDownloadURL = nil
        bestShortNotes = nil
        bestShortNotesURL = nil
        bestBuildNotes = nil
        bestBuildNotesURL = nil
        latestReleaseNotes = nil
        latestReleaseNotesURL = nil
        inItem = false
        resetCurrentItem()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        let version = UpdateChecker.preferredAppcastVersion(
            shortVersion: bestShortVersion,
            buildVersion: bestBuildVersion
        )
        let downloadURL = bestShortVersion == nil
            ? bestBuildDownloadURL
            : bestShortDownloadURL
        latestReleaseNotes = bestShortVersion == nil ? bestBuildNotes : bestShortNotes
        latestReleaseNotesURL = bestShortVersion == nil ? bestBuildNotesURL : bestShortNotesURL
        return (version, downloadURL)
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String,
                       namespaceURI: String?, qualifiedName: String?,
                       attributes: [String: String] = [:]) {
        switch elementName {
        case "item":
            inItem = true
            resetCurrentItem()
        case "sparkle:deltas" where inItem:
            inDeltas = true
        case "enclosure" where inItem && !inDeltas:
            // Delta enclosures patch one specific older build, so only the
            // item's full enclosure is a usable download.
            if currentDownloadURL == nil {
                currentDownloadURL = attributes["url"].flatMap(URL.init(string:))
            }
            if currentAttributeShortVersion == nil {
                currentAttributeShortVersion = attributes[Self.shortVersionKey]
            }
            if currentAttributeBuildVersion == nil {
                currentAttributeBuildVersion = attributes[Self.buildVersionKey]
            }
        case Self.shortVersionKey where inItem && !inDeltas,
             Self.buildVersionKey where inItem && !inDeltas,
             "description" where inItem && !inDeltas,
             "sparkle:releaseNotesLink" where inItem && !inDeltas:
            capturingElement = elementName
            capturedText = ""
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingElement != nil { capturedText += string }
    }

    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if capturingElement != nil, let text = String(data: CDATABlock, encoding: .utf8) { capturedText += text }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String,
                       namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "sparkle:deltas":
            inDeltas = false
        case Self.shortVersionKey where capturingElement == elementName:
            currentElementShortVersion = trimmedCapture()
        case Self.buildVersionKey where capturingElement == elementName:
            currentElementBuildVersion = trimmedCapture()
        case "description" where capturingElement == elementName:
            currentNotes = trimmedCapture().map(Self.plainText)
        case "sparkle:releaseNotesLink" where capturingElement == elementName:
            currentNotesURL = trimmedCapture().flatMap(URL.init(string:))
        case "item":
            finishItem()
        default:
            break
        }
    }

    private func trimmedCapture() -> String? {
        let text = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)
        capturingElement = nil
        capturedText = ""
        return text.isEmpty ? nil : text
    }

    private func finishItem() {
        inItem = false
        // Keep the highest version across all items. Sparkle appcasts are NOT
        // guaranteed to list the newest release first (issue #105: taking the
        // first item offered downgrades), so compare every item's version.
        if let version = currentElementShortVersion ?? currentAttributeShortVersion,
           shouldReplace(bestShortVersion, with: version) {
            bestShortVersion = version
            bestShortDownloadURL = currentDownloadURL
            bestShortNotes = currentNotes
            bestShortNotesURL = currentNotesURL
        }
        if let version = currentElementBuildVersion ?? currentAttributeBuildVersion,
           shouldReplace(bestBuildVersion, with: version) {
            bestBuildVersion = version
            bestBuildDownloadURL = currentDownloadURL
            bestBuildNotes = currentNotes
            bestBuildNotesURL = currentNotesURL
        }
        resetCurrentItem()
    }

    private func shouldReplace(_ bestVersion: String?, with candidate: String) -> Bool {
        guard let bestVersion else { return true }
        return UpdateChecker.isNewer(candidate, than: bestVersion)
    }

    /// Release notes are usually HTML; keep readable text only.
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<li[^>]*>", with: "• ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<(br|/p|/li|/h[1-6])[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        text = text.replacingOccurrences(of: "\n[ \t]+", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetCurrentItem() {
        currentNotes = nil
        currentNotesURL = nil
        inDeltas = false
        currentDownloadURL = nil
        currentAttributeShortVersion = nil
        currentAttributeBuildVersion = nil
        currentElementShortVersion = nil
        currentElementBuildVersion = nil
        capturingElement = nil
        capturedText = ""
    }
}
