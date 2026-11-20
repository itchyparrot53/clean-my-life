import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers
import Vision
import MacCleanKit

/// One photo in a similar group: a file on disk, or an asset in the Photos
/// library. Library assets get a `photos-library://` id so the shared
/// selection (a `Set<URL>`) can hold both.
struct SimilarPhoto: Identifiable, Sendable, Hashable {
    let id: URL
    /// Photos library local identifier, or nil for a file.
    let assetID: String?
    let name: String
    let size: UInt64
    let date: Date
    let pixelWidth: Int
    let pixelHeight: Int
    /// Higher is the better keeper.
    var score: Float = 0

    var isLibrary: Bool { assetID != nil }
    var pixels: Int { pixelWidth * pixelHeight }

    static func libraryURL(_ localIdentifier: String) -> URL {
        URL(string: "photos-library://asset/" + (localIdentifier.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? localIdentifier))!
    }
}

/// A set of near-identical photos. `best` is never selectable, so every group
/// always keeps at least one photo (engine rule, UI_SPEC §5.17).
struct PhotoCluster: Identifiable, Sendable {
    let id: UUID
    var photos: [SimilarPhoto]
    var best: URL
    /// The scanner's pick, shown as "Suggested" once you choose another.
    let suggested: URL

    var others: [SimilarPhoto] { photos.filter { $0.id != best } }
    var extraBytes: UInt64 { others.reduce(0) { $0 + $1.size } }
    var date: Date { photos.map(\.date).min() ?? .distantPast }
}

/// Similar Photos (UI_SPEC §5.17). Builds a Vision feature print for every
/// photo, then groups photos taken close together whose prints are close.
/// Exact copies are Duplicates' job; this catches bursts, retakes and edits.
struct SimilarPhotosScanner: Sendable {
    /// Feature-print distance under which two photos count as "the same shot".
    /// Calibrated on revision 2 prints: crops, small shifts and exposure
    /// changes measure 0.15–0.45; different scenes 0.8 and up.
    static let distanceThreshold: Float = 0.5
    /// Only photos taken this close together are compared.
    static let timeWindow: TimeInterval = 10 * 60
    /// Small images (icons, stickers, thumbnails) are skipped.
    static let minimumPixels = 300 * 300
    static let maxFiles = 25_000
    static let albumTitle = "\(MCConstants.appName) – To Review"

    /// Folders scanned for image files. The Photos library package is skipped
    /// here and read through PhotoKit instead.
    static var folders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Pictures", "Desktop", "Documents", "Downloads"].map { home.appending(path: $0) }
    }

    /// PhotoKit needs a usage string in the app's Info.plist; asking without
    /// one ends the process. The unbundled debug build has none.
    static var libraryAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryUsageDescription") != nil
    }

    var includeLibrary: Bool

    struct Progress: Sendable {
        var phase: String
        var fraction: Double
    }

    func scan(progress: @escaping @Sendable (Progress) -> Void) async -> [PhotoCluster] {
        progress(.init(phase: "Finding photos…", fraction: 0.02))
        let candidates = Self.imageFiles { found in
            progress(.init(phase: "Finding photos… \(found.formatted()) so far", fraction: 0.02 + 0.03 * min(1, Double(found) / Double(Self.maxFiles))))
        }
        let fileCount = candidates.count
        progress(.init(phase: "Found \(fileCount.formatted()) photos in your folders", fraction: 0.05))

        var libraryAssets: [PHAsset] = []
        if includeLibrary, Self.libraryAvailable, await Self.authorize() {
            libraryAssets = Self.libraryAssets()
        }
        let libraryCount = libraryAssets.count
        let total = Double(fileCount + libraryCount)
        let fileShare = total > 0 ? Double(fileCount) / total : 1

        let fileDenominator = Double(max(1, fileCount))
        var printed = Self.featurePrints(for: candidates) { done in
            let share: Double = fileShare * Double(done) / fileDenominator
            progress(.init(phase: "Looking at photo \(done.formatted()) of \(fileCount.formatted())…",
                           fraction: 0.05 + 0.85 * share))
        }
        if libraryCount > 0 {
            printed += Self.libraryPrints(for: libraryAssets) { done in
                let share: Double = fileShare + (1 - fileShare) * Double(done) / Double(libraryCount)
                progress(.init(phase: "Looking at Photos library item \(done.formatted()) of \(libraryCount.formatted())…",
                               fraction: 0.05 + 0.85 * share))
            }
        }

        progress(.init(phase: "Grouping similar shots…", fraction: 0.92))
        var clusters = Self.cluster(printed)
        progress(.init(phase: "Picking the best of each group…", fraction: 0.95))
        clusters = clusters.map(Self.rank)
        return clusters.sorted { $0.date > $1.date }
    }

    // MARK: Files

    struct Candidate: Sendable {
        let url: URL
        let size: UInt64
        let modified: Date
    }

    static func imageFiles(onFound: (@Sendable (Int) -> Void)? = nil) -> [Candidate] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey, .totalFileAllocatedSizeKey,
                                      .fileSizeKey, .contentModificationDateKey]
        let skipNames: Set<String> = ["node_modules", "Library", ".Trash", "Photo Booth Library"]
        var seen = Set<String>()
        var found: [Candidate] = []
        for folder in folders {
            guard let walker = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walker {
                if skipNames.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let type = values.contentType, type.conforms(to: .image),
                      !type.conforms(to: .svg), !type.conforms(to: .ico), !type.conforms(to: .icns) else { continue }
                let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
                guard seen.insert(path).inserted else { continue }
                let size = UInt64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                guard size >= 20_000 else { continue }
                found.append(Candidate(url: url, size: size, modified: values.contentModificationDate ?? .distantPast))
                if found.count % 250 == 0 { onFound?(found.count) }
                if found.count >= maxFiles { return found }
            }
        }
        return found
    }

    struct Printed: @unchecked Sendable {
        var photo: SimilarPhoto
        let print: VNFeaturePrintObservation
    }

    static func featurePrints(for candidates: [Candidate], onProgress: @escaping @Sendable (Int) -> Void) -> [Printed] {
        let box = Collector(count: candidates.count)
        DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
            autoreleasepool {
                let candidate = candidates[index]
                if let entry = filePrint(candidate) { box.set(index, entry) }
                let done = box.tick()
                if done % 25 == 0 || done == candidates.count { onProgress(done) }
            }
        }
        return box.values
    }

    private static func filePrint(_ candidate: Candidate) -> Printed? {
        guard let source = CGImageSourceCreateWithURL(candidate.url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width * height >= minimumPixels else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let print = featurePrint(thumb) else { return nil }
        let photo = SimilarPhoto(
            id: candidate.url, assetID: nil, name: candidate.url.lastPathComponent, size: candidate.size,
            date: captureDate(props) ?? candidate.modified, pixelWidth: width, pixelHeight: height)
        return Printed(photo: photo, print: print)
    }

    private static func captureDate(_ props: [CFString: Any]) -> Date? {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        guard let text = exif?[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    static func featurePrint(_ image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.first
    }

    // MARK: Photos library

    static func authorize() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: return true
        case .notDetermined: return await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .authorized
        default: return false
        }
    }

    static func libraryAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    static func libraryPrints(for assets: [PHAsset], onProgress: @escaping @Sendable (Int) -> Void) -> [Printed] {
        let box = Collector(count: assets.count)
        let lookup = AssetList(assets)
        DispatchQueue.concurrentPerform(iterations: assets.count) { index in
            autoreleasepool {
                let asset = lookup.assets[index]
                if asset.pixelWidth * asset.pixelHeight >= minimumPixels,
                   let image = libraryImage(asset, side: 512), let print = featurePrint(image) {
                    let photo = SimilarPhoto(
                        id: SimilarPhoto.libraryURL(asset.localIdentifier), assetID: asset.localIdentifier,
                        name: PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "Photo",
                        size: 0, date: asset.creationDate ?? .distantPast,
                        pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight)
                    box.set(index, Printed(photo: photo, print: print))
                }
                let done = box.tick()
                if done % 25 == 0 || done == assets.count { onProgress(done) }
            }
        }
        return box.values
    }

    /// A local, already-downloaded rendition only: no iCloud traffic.
    static func libraryImage(_ asset: PHAsset, side: CGFloat) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        var image: CGImage?
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFit, options: options
        ) { result, _ in
            image = result?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        return image
    }

    /// Adds the assets to the review album, creating it if needed. Nothing is
    /// deleted from the library; you finish the job in Photos.
    static func addToReviewAlbum(_ localIdentifiers: [String]) async throws -> Int {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard assets.count > 0 else { return 0 }
        let albumOptions = PHFetchOptions()
        albumOptions.predicate = NSPredicate(format: "title == %@", albumTitle)
        let existing = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: albumOptions).firstObject
        let title = albumTitle
        try await PHPhotoLibrary.shared().performChanges {
            let request: PHAssetCollectionChangeRequest?
            if let existing {
                request = PHAssetCollectionChangeRequest(for: existing)
            } else {
                request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            }
            request?.addAssets(assets)
        }
        return assets.count
    }

    // MARK: Grouping

    static func cluster(_ printed: [Printed]) -> [PhotoCluster] {
        let sorted = printed.sorted { $0.photo.date < $1.photo.date }
        var parent = Array(sorted.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in sorted.indices {
            var j = i + 1
            while j < sorted.count, j - i <= 60,
                  sorted[j].photo.date.timeIntervalSince(sorted[i].photo.date) <= timeWindow {
                var distance: Float = .greatestFiniteMagnitude
                if (try? sorted[i].print.computeDistance(&distance, to: sorted[j].print)) != nil,
                   distance < distanceThreshold {
                    let a = root(i), b = root(j)
                    if a != b { parent[b] = a }
                }
                j += 1
            }
        }
        let groups = Dictionary(grouping: sorted.indices, by: root).values.filter { $0.count > 1 }
        return groups.map { indices in
            let photos = indices.map { sorted[$0].photo }
            return PhotoCluster(id: UUID(), photos: photos, best: photos[0].id, suggested: photos[0].id)
        }
    }

    /// Scores each photo and puts the suggested keeper first: Vision's
    /// aesthetics score where available, then resolution, then file size.
    static func rank(_ cluster: PhotoCluster) -> PhotoCluster {
        var photos = cluster.photos.map { photo -> SimilarPhoto in
            var photo = photo
            photo.score = aesthetics(photo) ?? 0
            return photo
        }
        photos.sort {
            if abs($0.score - $1.score) > 0.05 { return $0.score > $1.score }
            if $0.pixels != $1.pixels { return $0.pixels > $1.pixels }
            return $0.size > $1.size
        }
        return PhotoCluster(id: cluster.id, photos: photos, best: photos[0].id, suggested: photos[0].id)
    }

    private static func aesthetics(_ photo: SimilarPhoto) -> Float? {
        guard #available(macOS 15.0, *) else { return nil }
        let image: CGImage?
        if let assetID = photo.assetID {
            image = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject
                .flatMap { libraryImage($0, side: 512) }
        } else {
            image = thumbnail(photo.id, side: 512)
        }
        guard let image else { return nil }
        let request = VNCalculateImageAestheticsScoresRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.first?.overallScore
    }

    static func thumbnail(_ url: URL, side: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Thread-safe slots for `concurrentPerform`.
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [SimilarPhotosScanner.Printed?]
    private var done = 0

    init(count: Int) { slots = Array(repeating: nil, count: count) }

    func set(_ index: Int, _ value: SimilarPhotosScanner.Printed) {
        lock.lock(); slots[index] = value; lock.unlock()
    }

    func tick() -> Int {
        lock.lock(); defer { lock.unlock() }
        done += 1
        return done
    }

    var values: [SimilarPhotosScanner.Printed] {
        lock.lock(); defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}

/// PHAsset isn't Sendable; PhotoKit objects are safe to read across threads.
private struct AssetList: @unchecked Sendable {
    let assets: [PHAsset]
    init(_ assets: [PHAsset]) { self.assets = assets }
}
