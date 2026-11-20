import AppKit

/// Clean My Life brand images (brand kit v1.0), loaded from the SwiftPM
/// resource bundle without SwiftPM's generated accessor, which crashes when
/// the bundle is missing. Looks next to the executable (swift build) and in
/// the app's Resources folder (packaged .app). Returns nil if not found.
enum BrandAssets {
    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        for folder in folders {
            // A macOS resource bundle keeps its files under Contents/Resources.
            for sub in ["Contents/Resources/BrandAssets", "BrandAssets"] {
                let url = folder.appending(path: "\(sub)/\(name).png")
                if let image = NSImage(contentsOf: url) {
                    cache[name] = image
                    return image
                }
            }
        }
        return nil
    }

    private static var folders: [URL] {
        let bundleName = "MacClean_MacCleanMenu.bundle"
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appending(path: bundleName)) }
        candidates.append(Bundle.main.bundleURL.appending(path: bundleName))
        if let executable = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executable.appending(path: bundleName))
        }
        return candidates
    }
}
