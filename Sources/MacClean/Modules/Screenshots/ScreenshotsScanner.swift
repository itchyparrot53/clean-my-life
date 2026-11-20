import CoreServices
import Foundation
import MacCleanKit

/// Screenshots: every screenshot and screen recording in your home folder,
/// found through Spotlight's screen-capture flag plus the usual file names in
/// the folder macOS saves screenshots to.
struct ScreenshotsScanner: Sendable {
    struct Group: Sendable, Identifiable {
        let id: String
        let title: String
        let symbol: String
        let items: [FileItem]
    }

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]
    static let nameMarkers = ["Screenshot", "Screen Shot", "Screen Recording", "CleanShot", "Bildschirmfoto",
                              "Capture d’écran", "Captura de pantalla", "截屏", "屏幕快照"]

    /// Where new screenshots are saved (`defaults write com.apple.screencapture location`).
    static var saveFolder: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !path.isEmpty {
            return URL(filePath: (path as NSString).expandingTildeInPath)
        }
        return home.appending(path: "Desktop")
    }

    /// The tidy-up destination.
    static var archiveFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Pictures/Screenshots")
    }

    func scan() -> (result: ScanResult?, groups: [Group]) {
        var paths = Set(Self.spotlightPaths())
        for folder in Set([Self.saveFolder, FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop")]) {
            paths.formUnion(Self.namedCaptures(in: folder))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey,
                                         .creationDateKey, .contentModificationDateKey]
        var items: [FileItem] = []
        for path in paths {
            guard path.hasPrefix(home), !path.contains("/.Trash/"), !path.contains("/Library/") else { continue }
            let url = URL(filePath: path)
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            let size = UInt64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            items.append(FileItem(url: url, name: url.lastPathComponent, size: size, allocatedSize: size,
                                  isDirectory: false, creationDate: values.creationDate,
                                  modificationDate: values.contentModificationDate))
        }
        items.sort { Self.date($0) > Self.date($1) }

        let now = Date()
        func age(_ item: FileItem) -> TimeInterval { now.timeIntervalSince(Self.date(item)) }
        let day: TimeInterval = 24 * 3600
        let stills = items.filter { !Self.videoExtensions.contains($0.fileExtension) }
        let recordings = items.filter { Self.videoExtensions.contains($0.fileExtension) }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop").path(percentEncoded: false)

        var groups: [Group] = [Group(id: "all", title: "All", symbol: "square.grid.2x2", items: items)]
        let buckets: [(String, String, String, (TimeInterval) -> Bool)] = [
            ("week", "This week", "calendar", { $0 < 7 * day }),
            ("month", "This month", "calendar", { $0 >= 7 * day && $0 < 30 * day }),
            ("older", "Older than a month", "clock", { $0 >= 30 * day && $0 < 365 * day }),
            ("year", "Older than a year", "clock.badge.exclamationmark", { $0 >= 365 * day }),
        ]
        for (id, title, symbol, test) in buckets {
            let list = stills.filter { test(age($0)) }
            if !list.isEmpty { groups.append(Group(id: id, title: title, symbol: symbol, items: list)) }
        }
        if !recordings.isEmpty {
            groups.append(Group(id: "recordings", title: "Screen recordings", symbol: "record.circle", items: recordings))
        }
        let onDesktop = items.filter { $0.url.path(percentEncoded: false).hasPrefix(desktop + "/") }
        if !onDesktop.isEmpty {
            groups.append(Group(id: "desktop", title: "On your Desktop", symbol: "menubar.dock.rectangle", items: onDesktop))
        }
        let result = items.isEmpty ? nil : ScanResult(category: .screenshots, items: items, autoSelect: false)
        return (result, groups)
    }

    static func date(_ item: FileItem) -> Date { item.creationDate ?? item.modificationDate ?? .distantPast }

    /// Spotlight's own screenshot flag. Synchronous; runs off the main thread.
    static func spotlightPaths() -> [String] {
        guard let query = MDQueryCreate(kCFAllocatorDefault, "kMDItemIsScreenCapture == 1" as CFString, nil, nil) else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        MDQuerySetSearchScope(query, [home] as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }
        var paths: [String] = []
        for index in 0..<MDQueryGetResultCount(query) {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            if let path = MDItemCopyAttribute(item, kMDItemPath) as? String { paths.append(path) }
        }
        return paths
    }

    /// Files named like screenshots, at the top of `folder`.
    static func namedCaptures(in folder: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        let extensions = Set(["png", "jpg", "jpeg", "heic", "tiff", "gif", "pdf"]).union(videoExtensions)
        return entries.filter { url in
            extensions.contains(url.pathExtension.lowercased())
                && nameMarkers.contains { url.lastPathComponent.hasPrefix($0) }
        }.map { $0.path(percentEncoded: false) }
    }

    /// Moves files into ~/Pictures/Screenshots/<year-month>, never overwriting.
    /// Returns the URLs that moved.
    static func archive(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        var moved: [URL] = []
        for url in urls {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let folder = archiveFolder.appending(path: formatter.string(from: created))
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var target = folder.appending(path: url.lastPathComponent)
            var counter = 2
            while fm.fileExists(atPath: target.path(percentEncoded: false)) {
                let stem = url.deletingPathExtension().lastPathComponent
                target = folder.appending(path: "\(stem) \(counter).\(url.pathExtension)")
                counter += 1
            }
            if (try? fm.moveItem(at: url, to: target)) != nil { moved.append(url) }
        }
        return moved
    }
}
