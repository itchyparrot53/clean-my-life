import Foundation
import MacCleanKit

/// AI Clutter (UI_SPEC §5.3, PLAN §3.3): caches and logs left by AI apps, and
/// local models downloaded by Ollama, LM Studio and Hugging Face.
struct AIClutterScanner: Sendable {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// Cache folders for AI desktop apps. They rebuild on next launch.
    private var appCacheFolders: [URL] {
        let caches = home.appending(path: "Library/Caches")
        let support = home.appending(path: "Library/Application Support")
        return [
            caches.appending(path: "com.anthropic.claudefordesktop"),
            caches.appending(path: "com.anthropic.claudefordesktop.ShipIt"),
            caches.appending(path: "com.openai.chat"),
            caches.appending(path: "com.openai.atlas"),
            caches.appending(path: "ai.perplexity.mac"),
            caches.appending(path: "com.lmstudio.app"),
            support.appending(path: "Claude/Cache"),
            support.appending(path: "Claude/Code Cache"),
            support.appending(path: "Claude/GPUCache"),
            support.appending(path: "Claude/DawnCache"),
            support.appending(path: "LM Studio/Cache"),
            support.appending(path: "LM Studio/GPUCache"),
        ] + AIToolCachesCategory().targets.map(\.path)
    }

    private var logFolders: [URL] {
        let logs = home.appending(path: "Library/Logs")
        return [logs.appending(path: "Claude"), logs.appending(path: "ChatGPT"),
                logs.appending(path: "LM Studio"), home.appending(path: ".ollama/logs")]
    }

    func scan() async -> [ScanResult] {
        let scanner = TargetedScanner()
        let cacheItems = await scanner.scan(targets: appCacheFolders.map { ScanTarget(path: $0, recursive: true) })
        let logItems = await scanner.scan(targets: logFolders.map { ScanTarget(path: $0, recursive: true) })
        let models = localModels()
        var results: [ScanResult] = []
        if !cacheItems.isEmpty { results.append(ScanResult(category: .aiToolCaches, items: cacheItems, autoSelect: true)) }
        if !logItems.isEmpty { results.append(ScanResult(category: .userLogs, items: logItems, autoSelect: true)) }
        if !models.isEmpty { results.append(ScanResult(category: .localAIModels, items: models, autoSelect: false)) }
        return results.filteringUncleanable()
    }

    // MARK: Local models

    func localModels() -> [FileItem] {
        lmStudioModels() + huggingFaceModels() + ollamaModels()
    }

    /// LM Studio keeps one .gguf / .mlx file per model variant.
    private func lmStudioModels() -> [FileItem] {
        let roots = [home.appending(path: ".lmstudio/models"), home.appending(path: ".cache/lm-studio/models")]
        var items: [FileItem] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let url as URL in walker where ["gguf", "safetensors", "bin"].contains(url.pathExtension.lowercased()) {
                let size = Self.allocated(url)
                guard size > 50_000_000 else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                items.append(Self.item(url, title: "\(name)\(Self.quant(name).map { " · \($0)" } ?? "")", size: size, isDirectory: false))
            }
        }
        return items
    }

    /// Hugging Face hub: one folder per repo, `models--org--name`.
    private func huggingFaceModels() -> [FileItem] {
        let hub = home.appending(path: ".cache/huggingface/hub")
        guard let entries = try? FileManager.default.contentsOfDirectory(at: hub, includingPropertiesForKeys: nil) else { return [] }
        return entries.compactMap { url in
            let folder = url.lastPathComponent
            guard folder.hasPrefix("models--") else { return nil }
            let name = folder.dropFirst("models--".count).replacingOccurrences(of: "--", with: "/")
            let size = Self.folderSize(url)
            guard size > 10_000_000 else { return nil }
            return Self.item(url, title: "\(name)\(Self.quant(name).map { " · \($0)" } ?? "") (Hugging Face)", size: size, isDirectory: true)
        }
    }

    /// Ollama: each manifest names the blobs a model uses. The row points at
    /// the manifest; `orphanedOllamaBlobs` removes weights nothing else needs.
    private func ollamaModels() -> [FileItem] {
        let models = home.appending(path: ".ollama/models")
        let manifests = models.appending(path: "manifests")
        guard let walker = FileManager.default.enumerator(at: manifests, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var entries: [(url: URL, name: String, digests: [String])] = []
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let parts = url.path(percentEncoded: false).replacingOccurrences(of: manifests.path(percentEncoded: false) + "/", with: "").split(separator: "/")
            let name = parts.count >= 2 ? "\(parts[parts.count - 2]):\(parts[parts.count - 1])" : url.lastPathComponent
            entries.append((url, name, Self.ollamaDigests(url)))
        }
        // Count how many models share each blob, so a row's size is what removing it frees.
        var users: [String: Int] = [:]
        for entry in entries { for digest in Set(entry.digests) { users[digest, default: 0] += 1 } }
        return entries.map { entry in
            let unique = Set(entry.digests).filter { users[$0] == 1 }
            let size = unique.reduce(UInt64(0)) { $0 + Self.allocated(Self.ollamaBlob($1, in: models)) }
            return Self.item(entry.url, title: "\(entry.name) (Ollama)", size: size, isDirectory: false,
                             lastUsed: entry.digests.map { Self.ollamaBlob($0, in: models) }.compactMap(Self.accessDate).max())
        }
    }

    /// Blobs no remaining manifest references: removed after their models go.
    static func orphanedOllamaBlobs() -> [URL] {
        let models = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ollama/models")
        let manifests = models.appending(path: "manifests")
        var used = Set<String>()
        if let walker = FileManager.default.enumerator(at: manifests, includingPropertiesForKeys: nil) {
            for case let url as URL in walker { used.formUnion(ollamaDigests(url)) }
        }
        let blobs = models.appending(path: "blobs")
        let all = (try? FileManager.default.contentsOfDirectory(at: blobs, includingPropertiesForKeys: nil)) ?? []
        return all.filter { !used.contains($0.lastPathComponent.replacingOccurrences(of: "-", with: ":")) }
    }

    private static func ollamaDigests(_ manifest: URL) -> [String] {
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let layers = (json["layers"] as? [[String: Any]]) ?? []
        let config = (json["config"] as? [String: Any]).map { [$0] } ?? []
        return (layers + config).compactMap { $0["digest"] as? String }
    }

    private static func ollamaBlob(_ digest: String, in models: URL) -> URL {
        models.appending(path: "blobs/" + digest.replacingOccurrences(of: ":", with: "-"))
    }

    // MARK: Helpers

    /// "Q4_K_M", "Q8_0", "4bit" and similar, from a model file or repo name.
    static func quant(_ name: String) -> String? {
        let patterns = [#"(?i)\b(I?Q\d(_[A-Z0-9]+)*)\b"#, #"(?i)\b(\d+bit)\b"#, #"(?i)\b(f16|fp16|bf16|f32)\b"#]
        for pattern in patterns {
            if let range = name.range(of: pattern, options: .regularExpression) {
                return name[range].uppercased()
            }
        }
        return nil
    }

    private static func item(_ url: URL, title: String, size: UInt64, isDirectory: Bool, lastUsed: Date? = nil) -> FileItem {
        let used = lastUsed ?? accessDate(url)
        let suffix = used.map { " · last used " + $0.formatted(.relative(presentation: .named)) } ?? ""
        return FileItem(url: url, name: title + suffix, size: size, allocatedSize: size, isDirectory: isDirectory,
                        lastAccessDate: used)
    }

    private static func accessDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate
    }

    static func allocated(_ url: URL) -> UInt64 {
        UInt64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
    }

    static func folderSize(_ url: URL) -> UInt64 {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in walker { total += allocated(file) }
        return total
    }
}
