import AppKit
import SwiftUI
import MacCleanKit

/// Similar Photos (UI_SPEC §5.17) on the shared templates. Files go to the
/// Trash (with Undo); Photos library items are only added to an album.
struct SimilarPhotosView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("clean1.similarPhotos.includeLibrary") private var includeLibrary = true
    @State private var clusters: [PhotoCluster] = []
    @State private var results: [ScanResult] = []
    @State private var selectedItems: Set<URL> = []
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var scanPhase = "Finding photos…"
    @State private var scanComplete = false
    @State private var completion: CleanSummary?
    @State private var cleaning: CleaningEngine.Progress?
    @State private var cleanTask: Task<Void, Never>?

    static func caption(_ photo: SimilarPhoto) -> String {
        let dims = "\(photo.pixelWidth) × \(photo.pixelHeight)"
        return photo.isLibrary ? dims + " · Photos" : dims + " · " + FileSizeFormatter.format(photo.size)
    }

    var body: some View {
        ModuleContainerView(
            title: SidebarItem.similarPhotos.title,
            subtitle: "",
            theme: .files,
            emptyMessage: "No similar photos found",
            results: results,
            selectedItems: $selectedItems,
            isScanning: isScanning,
            scanProgress: scanProgress,
            scanPhase: scanPhase,
            scanComplete: scanComplete,
            completion: completion,
            cleaning: cleaning,
            onScan: scan,
            onClean: clean,
            onCancelClean: { cleanTask?.cancel() },
            onReset: reset,
            resultsContent: {
                AnyView(SimilarPhotosReview(clusters: $clusters, selectedItems: $selectedItems))
            },
            actionLabel: L10n.tr("移除", "Remove", "Удалить"),
            introControl: AnyView(libraryToggle),
            resultsFullWidth: true)
    }

    @ViewBuilder private var libraryToggle: some View {
        if SimilarPhotosScanner.libraryAvailable {
            Toggle("Include my Photos library", isOn: $includeLibrary)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
                .foregroundStyle(TypeScale.secondaryText)
                .help("Similar shots from Photos are added to an album for you to review there. Nothing is deleted from your library.")
        }
    }

    private func scan() {
        isScanning = true
        scanComplete = false
        scanProgress = 0.02
        scanPhase = "Finding photos…"
        results = []
        clusters = []
        selectedItems = []
        let scanner = SimilarPhotosScanner(includeLibrary: includeLibrary)
        let throttle = ProgressThrottle()
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                await scanner.scan { progress in
                    guard throttle.ready() else { return }
                    Task { @MainActor in
                        scanProgress = max(scanProgress, progress.fraction)
                        scanPhase = progress.phase
                    }
                }
            }.value
            clusters = found
            let items = found.flatMap(\.photos).map { photo in
                FileItem(url: photo.id, name: photo.name, size: photo.size, allocatedSize: photo.size,
                         isDirectory: false, modificationDate: photo.date)
            }
            results = items.isEmpty ? [] : [ScanResult(category: .similarPhotos, items: items, autoSelect: false)]
            // Everything but the Best of each group starts ticked; Best can't be ticked.
            selectedItems = Set(found.flatMap { $0.others.map(\.id) })
            scanProgress = 1
            isScanning = false
            scanComplete = true
        }
    }

    private func clean() {
        let chosen = selectedItems
        let all = clusters.flatMap(\.photos)
        let bests = Set(clusters.map(\.best))
        // Never remove a group's Best, whatever the selection says.
        let picked = all.filter { chosen.contains($0.id) && !bests.contains($0.id) }
        let files = picked.filter { !$0.isLibrary }.map {
            FileItem(url: $0.id, name: $0.name, size: $0.size, allocatedSize: $0.size, isDirectory: false)
        }
        let assetIDs = picked.compactMap(\.assetID)
        cleaning = CleaningEngine.Progress(totalItems: picked.count, processedItems: 0, removedSoFar: 0, freedBytesSoFar: 0)
        cleanTask = Task {
            var removed = 0
            var freed: UInt64 = 0
            var errors: [String] = []
            if !files.isEmpty {
                let result = await CleanActions.executeUserClean(
                    items: files, selectedItems: Set(files.map(\.url)), engine: appState.cleaningEngine,
                    onProgress: { progress in Task { @MainActor in cleaning = progress } })
                removed += result.removedCount
                freed += result.freedBytes
                errors += result.errors.map(\.error)
            }
            if !assetIDs.isEmpty {
                do {
                    removed += try await SimilarPhotosScanner.addToReviewAlbum(assetIDs)
                } catch {
                    errors.append("Couldn't add photos to the \"\(SimilarPhotosScanner.albumTitle)\" album: \(error.localizedDescription)")
                }
            }
            cleaning = nil
            completion = CleanSummary(selectedCount: picked.count, removedCount: removed,
                                      freedBytes: freed, errorMessages: errors)
        }
    }

    private func reset() {
        results = []; clusters = []; selectedItems = []; completion = nil; cleaning = nil; cleanTask = nil; scanComplete = false
    }
}

/// Left: groups as a thumbnail mosaic + count. Right: the group's photos as
/// a 120 pt grid with checkboxes and a Best star. Double-click to compare.
struct SimilarPhotosReview: View {
    @Binding var clusters: [PhotoCluster]
    @Binding var selectedItems: Set<URL>
    @State private var focused: UUID?
    @State private var comparing: [SimilarPhoto] = []

    private var current: PhotoCluster? { clusters.first { $0.id == focused } ?? clusters.first }

    private var hasLibrary: Bool { clusters.contains { $0.photos.contains(where: \.isLibrary) } }

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(TypeScale.tertiaryText)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(clusters) { cluster in clusterRow(cluster) }
                        }
                    }
                }
                .frame(width: 270)

                if let current {
                    grid(current)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .opacity(comparing.isEmpty ? 1 : 0)

            if !comparing.isEmpty, let current {
                PhotoCompareView(photos: comparing, best: current.best,
                                 onKeep: { keep($0, in: current) },
                                 onClose: { comparing = [] })
                    .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: comparing.map(\.id))
        .foregroundStyle(TypeScale.primaryText)
    }

    private var summary: String {
        let extra = clusters.reduce(UInt64(0)) { $0 + $1.extraBytes }
        let photos = clusters.reduce(0) { $0 + $1.photos.count }
        return "\(clusters.count) groups · \(photos) photos · \(FileSizeFormatter.format(extra)) in extra shots"
    }

    private func clusterRow(_ cluster: PhotoCluster) -> some View {
        let others = cluster.others.map(\.id)
        let selected = others.filter(selectedItems.contains).count
        let state: CheckState = selected == 0 ? .off : (selected == others.count ? .on : .mixed)
        return HStack(spacing: 10) {
            TriStateCheckbox(state: state) {
                if state == .on { selectedItems.subtract(others) } else { selectedItems.formUnion(others) }
            }
            mosaic(cluster)
            VStack(alignment: .leading, spacing: 1) {
                Text(cluster.date.formatted(date: .abbreviated, time: .shortened))
                    .font(TypeScale.row).lineLimit(1)
                Text("\(cluster.photos.count) photos" + (cluster.photos.contains(where: \.isLibrary) ? " · Photos" : ""))
                    .font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
            }
            Spacer(minLength: 4)
            if cluster.extraBytes > 0 {
                Text(FileSizeFormatter.format(cluster.extraBytes))
                    .font(TypeScale.rowSize)
                    .foregroundStyle(.white.opacity(state == .off ? 0.45 : 0.8))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: Surface.rowRadius, style: .continuous)
            .fill(cluster.id == current?.id ? Surface.rowSelection : .clear))
        .contentShape(Rectangle())
        .onTapGesture { focused = cluster.id }
    }

    /// Up to four thumbnails in a 2 × 2 tile.
    private func mosaic(_ cluster: PhotoCluster) -> some View {
        let tiles = Array(cluster.photos.prefix(4))
        return Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                tile(tiles[safe: 0])
                tile(tiles[safe: 1])
            }
            GridRow {
                tile(tiles[safe: 2])
                tile(tiles[safe: 3])
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder private func tile(_ photo: SimilarPhoto?) -> some View {
        if let photo {
            PhotoThumb(url: photo.id, assetID: photo.assetID, side: 18).frame(width: 18.5, height: 18.5)
        } else {
            Color.white.opacity(0.06).frame(width: 18.5, height: 18.5)
        }
    }

    private func grid(_ cluster: PhotoCluster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(cluster.date.formatted(date: .long, time: .shortened)).font(TypeScale.reviewTitle)
                Spacer()
                Menu {
                    Button("Select All but Best") { selectedItems.formUnion(cluster.others.map(\.id)) }
                    Button("Deselect This Group") { selectedItems.subtract(cluster.photos.map(\.id)) }
                    Divider()
                    Button("Select All but Best, Every Group") {
                        selectedItems = Set(clusters.flatMap { $0.others.map(\.id) })
                    }
                    Button("Deselect Everything") { selectedItems = [] }
                } label: {
                    HStack(spacing: 3) {
                        Text("Auto-select")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(TypeScale.secondaryText)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            Text(cluster.photos.contains(where: \.isLibrary)
                 ? "Double-click to compare. Photos from your library go to the \"\(SimilarPhotosScanner.albumTitle)\" album, not the Trash."
                 : "Double-click to compare. Right-click a photo to keep it instead.")
                .font(TypeScale.reviewDescription)
                .foregroundStyle(.white.opacity(0.7))
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 120), spacing: 12, alignment: .top)],
                          alignment: .leading, spacing: 14) {
                    ForEach(cluster.photos) { photo in cell(photo, in: cluster) }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func cell(_ photo: SimilarPhoto, in cluster: PhotoCluster) -> some View {
        let isBest = photo.id == cluster.best
        let isSelected = selectedItems.contains(photo.id)
        return PhotoCell(
            url: photo.id, assetID: photo.assetID, caption: SimilarPhotosView.caption(photo),
            isBest: isBest, bestLabel: cluster.best == cluster.suggested ? "Best" : "Keep",
            isSelected: isSelected,
            onToggle: { if isSelected { selectedItems.remove(photo.id) } else { selectedItems.insert(photo.id) } },
            onOpen: { openCompare(photo, in: cluster) })
            .contextMenu {
                if !isBest { Button("Keep This Instead") { keep(photo, in: cluster) } }
                Button("Compare") { openCompare(photo, in: cluster) }
                if !photo.isLibrary {
                    Button(L10n.tr("在 Finder 中显示", "Reveal in Finder", "Показать в Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([photo.id])
                    }
                }
            }
    }

    /// The double-clicked photo, the Best, and one more from the group.
    private func openCompare(_ photo: SimilarPhoto, in cluster: PhotoCluster) {
        var picks = [photo]
        if let best = cluster.photos.first(where: { $0.id == cluster.best }), best.id != photo.id { picks.append(best) }
        if let extra = cluster.photos.first(where: { candidate in !picks.contains { $0.id == candidate.id } }) {
            picks.append(extra)
        }
        focused = cluster.id
        comparing = Array(picks.prefix(3))
    }

    /// Make `photo` the one kept; the old Best becomes a normal, unticked photo.
    private func keep(_ photo: SimilarPhoto, in cluster: PhotoCluster) {
        guard let index = clusters.firstIndex(where: { $0.id == cluster.id }) else { return }
        clusters[index].best = photo.id
        selectedItems.remove(photo.id)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
