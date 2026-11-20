import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers
import MacCleanKit

/// Large & Old Files review (UI_SPEC §5.15): a grouping switch (Kind / Size /
/// Last opened), groups on the left, file rows with thumbnails on the right.
struct GroupedFileReview: View {
    let results: [ScanResult]
    @Binding var selectedItems: Set<URL>
    /// Ready-made groups (Downloads); hides the Kind / Size / Last Opened switch.
    var fixedGroups: [Group]?

    enum Grouping: String, CaseIterable, Identifiable {
        case kind, size, access
        var id: String { rawValue }
        var title: String {
            switch self {
            case .kind: L10n.tr("类型", "Kind", "Тип")
            case .size: L10n.tr("大小", "Size", "Размер")
            case .access: L10n.tr("上次打开", "Last Opened", "Открывали")
            }
        }
    }

    struct Group: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let items: [FileItem]
        var size: UInt64 { items.reduce(0) { $0 + $1.size } }
    }

    @State private var grouping: Grouping = .kind
    @State private var focusedGroup: String?

    /// Each file once, even if it's both large and old.
    private var files: [FileItem] {
        var seen = Set<URL>()
        return results.flatMap(\.items).filter { seen.insert($0.url).inserted }
            .sorted { $0.size > $1.size }
    }

    private var groups: [Group] {
        if let fixedGroups { return fixedGroups }
        let all = files
        let buckets: [(String, String, String, (FileItem) -> Bool)]
        switch grouping {
        case .kind:
            buckets = [
                ("archives", "Archives", "archivebox", { Self.conforms($0, .archive) || Self.conforms($0, .diskImage) }),
                ("movies", "Movies", "film", { Self.conforms($0, .movie) || Self.conforms($0, .video) }),
                ("music", "Music", "music.note", { Self.conforms($0, .audio) }),
                ("pictures", "Pictures", "photo", { Self.conforms($0, .image) }),
                ("documents", "Documents", "doc.text", {
                    Self.conforms($0, .pdf) || Self.conforms($0, .text) || Self.conforms($0, .presentation)
                        || Self.conforms($0, .spreadsheet) || Self.conforms($0, .compositeContent)
                }),
                ("other", "Other", "doc", { _ in true }),
            ]
        case .size:
            buckets = [
                ("huge", "Over 1 GB", "externaldrive", { $0.size >= 1_000_000_000 }),
                ("large", "100 MB – 1 GB", "shippingbox", { $0.size >= 100_000_000 }),
                ("medium", "5 – 100 MB", "doc", { _ in true }),
            ]
        case .access:
            let now = Date()
            func age(_ item: FileItem) -> TimeInterval {
                now.timeIntervalSince(item.lastAccessDate ?? item.modificationDate ?? now)
            }
            let month = 30.0 * 24 * 3600
            buckets = [
                ("year", "Over a year ago", "calendar.badge.clock", { age($0) > 12 * month }),
                ("half", "6 – 12 months ago", "calendar", { age($0) > 6 * month }),
                ("recent", "1 – 6 months ago", "clock", { age($0) > month }),
                ("lately", "This month", "clock.badge.checkmark", { _ in true }),
            ]
        }
        var remaining = all
        var result: [Group] = []
        for (id, title, symbol, test) in buckets {
            let match = remaining.filter(test)
            remaining.removeAll(where: test)
            if !match.isEmpty { result.append(Group(id: id, title: title, symbol: symbol, items: match)) }
        }
        return result
    }

    private static func conforms(_ item: FileItem, _ type: UTType) -> Bool {
        (item.contentType ?? UTType(filenameExtension: item.fileExtension))?.conforms(to: type) ?? false
    }

    var body: some View {
        let groups = groups
        let current = groups.first { $0.id == focusedGroup } ?? groups.first
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                if fixedGroups == nil {
                    Picker(L10n.tr("分组", "Group by", "Группировать"), selection: $grouping) {
                        ForEach(Grouping.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in groupRow(group, isFocused: group.id == current?.id) }
                    }
                }
            }
            .frame(width: 260)

            VStack(alignment: .leading, spacing: 6) {
                if let current {
                    Text(current.title).font(TypeScale.reviewTitle).lineLimit(1)
                    Text("\(current.items.count) files · \(FileSizeFormatter.format(current.size))")
                        .font(TypeScale.reviewDescription)
                        .foregroundStyle(.white.opacity(0.7))
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(current.items, id: \.url) { fileRow($0) }
                        }
                    }
                    .cardList()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(TypeScale.primaryText)
        .onChange(of: grouping) { _, _ in focusedGroup = nil }
    }

    private func state(_ group: Group) -> CheckState {
        let count = group.items.filter { selectedItems.contains($0.url) }.count
        return count == 0 ? .off : (count == group.items.count ? .on : .mixed)
    }

    private func groupRow(_ group: Group, isFocused: Bool) -> some View {
        let state = state(group)
        return HStack(spacing: 10) {
            TriStateCheckbox(state: state) {
                let urls = group.items.map(\.url)
                if state == .on { selectedItems.subtract(urls) } else { selectedItems.formUnion(urls) }
            }
            CategoryTile(symbol: group.symbol, tint: ModulePalette.largeOld.top)
            Text(group.title).font(TypeScale.row).lineLimit(1)
            Spacer(minLength: 6)
            Text(FileSizeFormatter.format(group.size))
                .font(TypeScale.rowSize)
                .foregroundStyle(.white.opacity(state == .off ? 0.45 : 0.8))
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Surface.rowRadius, style: .continuous)
            .fill(isFocused ? Surface.rowSelection : .clear))
        .contentShape(Rectangle())
        .onTapGesture { focusedGroup = group.id }
    }

    private func fileRow(_ item: FileItem) -> some View {
        let isOn = selectedItems.contains(item.url)
        return HStack(spacing: 10) {
            TriStateCheckbox(state: isOn ? .on : .off) {
                if isOn { selectedItems.remove(item.url) } else { selectedItems.insert(item.url) }
            }
            FileThumbnail(url: item.url, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(TypeScale.row).lineLimit(1)
                Text(item.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if let date = item.lastAccessDate ?? item.modificationDate {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
            }
            Text(item.formattedSize)
                .font(TypeScale.rowSize)
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .contextMenu {
            Button(L10n.tr("在 Finder 中显示", "Reveal in Finder", "Показать в Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }
}

/// Quick Look thumbnail, falling back to the file's icon.
struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .task(id: url) {
                let request = QLThumbnailGenerator.Request(
                    fileAt: url, size: CGSize(width: size, height: size),
                    scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
                if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                    image = rep.nsImage
                }
            }
    }
}
