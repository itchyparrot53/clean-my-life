import Foundation
import MacCleanKit

/// Downloads (UI_SPEC §5.18): everything at the top of ~/Downloads, grouped by
/// the app that downloaded it (from macOS's quarantine tag), plus installers
/// and duplicate downloads.
struct DownloadsScanner: Sendable {
    struct Group: Sendable, Identifiable {
        let id: String
        let title: String
        let symbol: String
        let items: [FileItem]
    }

    /// `progress` receives a 0...1 fraction and a short phase, so a large
    /// Downloads folder does not sit on one number while it walks.
    func scan(progress: (@Sendable (Double, String) -> Void)? = nil) -> (result: ScanResult?, groups: [Group]) {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .contentAccessDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return (nil, []) }

        var items: [FileItem] = []
        var sourceOf: [URL: String] = [:]
        progress?(0, "Reading your Downloads folder…")
        for (index, url) in entries.enumerated() {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            let size = isDirectory || (values?.isPackage ?? false) ? AIClutterScanner.folderSize(url) : AIClutterScanner.allocated(url)
            items.append(FileItem(url: url, name: url.lastPathComponent, size: size, allocatedSize: size,
                                  isDirectory: isDirectory, isPackage: values?.isPackage ?? false,
                                  modificationDate: values?.contentModificationDate,
                                  lastAccessDate: values?.contentAccessDate))
            sourceOf[url] = Self.source(of: url)
            progress?(Double(index + 1) / Double(max(entries.count, 1)),
                      "Reading \(url.lastPathComponent)…")
        }
        items.sort { $0.size > $1.size }

        let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]
        let installers = items.filter { installerExtensions.contains($0.fileExtension) }
        let duplicates = Self.duplicateDownloads(items)
        var groups: [Group] = []
        if !installers.isEmpty { groups.append(Group(id: "installers", title: "Installers", symbol: "shippingbox", items: installers)) }
        if !duplicates.isEmpty { groups.append(Group(id: "duplicates", title: "Duplicate downloads", symbol: "doc.on.doc", items: duplicates)) }
        let bySource = Dictionary(grouping: items) { sourceOf[$0.url] ?? "Other" }
        for (source, symbol) in [("Safari", "safari"), ("Chrome", "globe"), ("Firefox", "flame"), ("Arc", "globe"),
                                 ("Slack", "bubble.left.and.bubble.right"), ("AirDrop", "airplayaudio"),
                                 ("Mail", "envelope"), ("Messages", "message"), ("Other", "questionmark.folder")] {
            if let list = bySource[source], !list.isEmpty {
                groups.append(Group(id: "source-" + source, title: source, symbol: symbol, items: list))
            }
        }
        let result = items.isEmpty ? nil : ScanResult(category: .downloads, items: items, autoSelect: false)
        return (result, groups)
    }

    /// Which app downloaded the file, from `com.apple.quarantine`
    /// ("flags;timestamp;Agent Name;UUID").
    static func source(of url: URL) -> String {
        let name = "com.apple.quarantine"
        let length = getxattr(url.path(percentEncoded: false), name, nil, 0, 0, XATTR_NOFOLLOW)
        guard length > 0 else { return "Other" }
        var buffer = [UInt8](repeating: 0, count: length)
        guard getxattr(url.path(percentEncoded: false), name, &buffer, length, 0, XATTR_NOFOLLOW) > 0,
              let text = String(bytes: buffer, encoding: .utf8) else { return "Other" }
        let parts = text.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return "Other" }
        let agent = parts[2].lowercased()
        switch true {
        case agent.contains("safari"): return "Safari"
        case agent.contains("chrome"): return "Chrome"
        case agent.contains("firefox"): return "Firefox"
        case agent.contains("arc"): return "Arc"
        case agent.contains("slack"): return "Slack"
        case agent.contains("sharingd"), agent.contains("airdrop"): return "AirDrop"
        case agent.contains("mail"): return "Mail"
        case agent.contains("messages"): return "Messages"
        default: return "Other"
        }
    }

    /// "report (1).pdf" next to "report.pdf" with the same size.
    static func duplicateDownloads(_ items: [FileItem]) -> [FileItem] {
        let byName = Dictionary(items.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        return items.filter { item in
            let stem = (item.name as NSString).deletingPathExtension
            guard let range = stem.range(of: #" ?[\(-]?\d{1,2}\)?$"#, options: .regularExpression),
                  range.lowerBound != stem.startIndex else { return false }
            let base = String(stem[..<range.lowerBound])
            let ext = item.fileExtension
            let original = (ext.isEmpty ? base : base + "." + ext).lowercased()
            guard let match = byName[original], match.url != item.url else { return false }
            return match.size == item.size
        }
    }
}
