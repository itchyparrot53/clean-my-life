import AppKit
import Photos
import Quartz
import SwiftUI
import MacCleanKit

/// A square, cropped thumbnail for a file or a Photos library asset.
struct PhotoThumb: View {
    let url: URL
    var assetID: String?
    let side: CGFloat
    /// Fit instead of fill (compare view).
    var fit = false
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.06))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "photo").font(.system(size: side * 0.2)).foregroundStyle(.white.opacity(0.25))
            }
        }
        .clipped()
        .task(id: url) {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let pixels = side * scale
            let url = url, assetID = assetID
            let loaded = await Task.detached(priority: .userInitiated) { () -> ThumbImage? in
                let cg: CGImage?
                if let assetID {
                    cg = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject
                        .flatMap { SimilarPhotosScanner.libraryImage($0, side: pixels) }
                } else {
                    cg = SimilarPhotosScanner.thumbnail(url, side: pixels)
                }
                return cg.map(ThumbImage.init)
            }.value
            guard !Task.isCancelled, let loaded else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                image = NSImage(cgImage: loaded.image, size: NSSize(width: loaded.image.width, height: loaded.image.height))
            }
        }
    }
}

private struct ThumbImage: @unchecked Sendable { let image: CGImage }

/// One grid cell: thumbnail, checkbox or Best star, and a caption.
struct PhotoCell: View {
    let url: URL
    var assetID: String?
    let caption: String
    var isBest = false
    var bestLabel = "Best"
    let isSelected: Bool
    var side: CGFloat = 120
    let onToggle: () -> Void
    var onOpen: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                PhotoThumb(url: url, assetID: assetID, side: side)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color(hex: 0x5CC8F0) : Color.white.opacity(0.12),
                                          lineWidth: isSelected ? 2 : 1)
                    }
                    .opacity(isSelected ? 0.75 : 1)
                if isBest {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                        Text(bestLabel)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(Color(hex: 0xF8D44E)))
                    .padding(6)
                    .help("The one we suggest keeping. It's never removed.")
                } else {
                    TriStateCheckbox(state: isSelected ? .on : .off, size: 18, toggle: onToggle)
                        .background(Circle().fill(.black.opacity(0.25)))
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onOpen?() }
            .onTapGesture { if !isBest { onToggle() } }
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(TypeScale.tertiaryText)
                .lineLimit(1)
                .frame(width: side, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isBest ? "\(caption), \(bestLabel)" : caption)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 2–3 photos side by side with one zoom and one pan for all (UI_SPEC §5.17).
struct PhotoCompareView: View {
    let photos: [SimilarPhoto]
    let best: URL
    let onKeep: (SimilarPhoto) -> Void
    let onClose: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Compare").font(TypeScale.reviewTitle)
                Spacer()
                Image(systemName: "minus.magnifyingglass").foregroundStyle(TypeScale.tertiaryText)
                Slider(value: $zoom, in: 1...6) { editing in if !editing { baseZoom = zoom } }
                    .frame(width: 140)
                Image(systemName: "plus.magnifyingglass").foregroundStyle(TypeScale.tertiaryText)
                Button("Done", action: onClose).buttonStyle(.ghostPill).keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 10) {
                ForEach(photos) { photo in pane(photo) }
            }
            .gesture(MagnifyGesture()
                .onChanged { zoom = min(6, max(1, baseZoom * $0.magnification)) }
                .onEnded { _ in baseZoom = zoom })
            .simultaneousGesture(DragGesture()
                .onChanged { offset = CGSize(width: baseOffset.width + $0.translation.width,
                                             height: baseOffset.height + $0.translation.height) }
                .onEnded { _ in baseOffset = offset })
        }
        .padding(16)
        .foregroundStyle(TypeScale.primaryText)
        .onChange(of: zoom) { _, value in
            if value <= 1.01 { offset = .zero; baseOffset = .zero }
        }
    }

    private func pane(_ photo: SimilarPhoto) -> some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                PhotoThumb(url: photo.id, assetID: photo.assetID, side: max(proxy.size.width, proxy.size.height) * 2, fit: true)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(zoom)
                    .offset(offset)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(photo.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(SimilarPhotosView.caption(photo)).font(.system(size: 10)).foregroundStyle(TypeScale.tertiaryText)
                }
                Spacer(minLength: 4)
                if photo.id == best {
                    Label("Best", systemImage: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xF8D44E))
                } else {
                    Button("Keep This") { onKeep(photo) }.buttonStyle(.ghostPill)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Quick Look for a list of files, from anywhere in SwiftUI.
@MainActor
final class QuickLookPreview: NSObject, @preconcurrency QLPreviewPanelDataSource {
    private static let shared = QuickLookPreview()
    private var urls: [URL] = []

    static func show(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        shared.urls = urls
        panel.dataSource = shared
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}
