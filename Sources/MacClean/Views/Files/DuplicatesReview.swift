import AppKit
import SwiftUI
import MacCleanKit

/// Duplicates review (UI_SPEC §5.16): sets on the left, the copies of the
/// chosen set on the right with a Keep radio per row. Picking a different
/// copy to keep rebuilds that set with it as the original, so Remove and
/// Consolidate keep protecting whichever copy you chose.
struct DuplicatesReview: View {
    @Binding var groups: [DuplicateDisplayGroup]
    @Binding var selectedItems: Set<URL>
    /// The copy each set keeps by default.
    let suggested: [UUID: URL]

    enum AutoKeep: String, CaseIterable { case suggested, newest, oldest }

    @State private var focused: UUID?
    @State private var clones: [URL: Bool] = [:]

    private var current: DuplicateDisplayGroup? {
        groups.first { $0.id == focused } ?? groups.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(groups.count) sets · \(FileSizeFormatter.format(groups.reduce(0) { $0 + $1.wastedSpace })) in extra copies")
                    .font(.system(size: 11))
                    .foregroundStyle(TypeScale.tertiaryText)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in setRow(group) }
                    }
                }
            }
            .frame(width: 270)

            if let current {
                copies(current)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .foregroundStyle(TypeScale.primaryText)
    }

    private func setRow(_ group: DuplicateDisplayGroup) -> some View {
        let extras = group.duplicates.map(\.url)
        let selected = extras.filter(selectedItems.contains).count
        let state: CheckState = selected == 0 ? .off : (selected == extras.count ? .on : .mixed)
        return HStack(spacing: 10) {
            TriStateCheckbox(state: state) {
                if state == .on { selectedItems.subtract(extras) } else { selectedItems.formUnion(extras) }
            }
            FileThumbnail(url: group.original.url, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.original.name).font(TypeScale.row).lineLimit(1).truncationMode(.middle)
                Text("\(group.copyCount) copies · \(group.original.formattedSize)")
                    .font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
            }
            Spacer(minLength: 4)
            Text(group.formattedWastedSpace)
                .font(TypeScale.rowSize)
                .foregroundStyle(.white.opacity(state == .off ? 0.45 : 0.8))
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: Surface.rowRadius, style: .continuous)
            .fill(group.id == current?.id ? Surface.rowSelection : .clear))
        .contentShape(Rectangle())
        .onTapGesture { focused = group.id }
    }

    private func copies(_ group: DuplicateDisplayGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.original.name).font(TypeScale.reviewTitle).lineLimit(1).truncationMode(.middle)
                Spacer()
                Menu {
                    Button("Keep Suggested") { autoKeep(.suggested) }
                    Button("Keep Newest") { autoKeep(.newest) }
                    Button("Keep Oldest") { autoKeep(.oldest) }
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
            // Preview strip.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.allFiles, id: \.url) { file in
                        FileThumbnail(url: file.url, size: 56)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    }
                }
            }
            .frame(height: 66)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(group.allFiles, id: \.url) { file in copyRow(file, in: group) }
                }
            }
            .cardList()
        }
    }

    private func copyRow(_ file: FileItem, in group: DuplicateDisplayGroup) -> some View {
        let isKept = file.url == group.original.url
        let isSelected = selectedItems.contains(file.url)
        return HStack(spacing: 10) {
            Button { keep(file, in: group) } label: {
                Image(systemName: isKept ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isKept ? Color(hex: 0x5CC8F0) : .white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Keep this copy")
            .accessibilityLabel("Keep \(file.name)")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(file.url.deletingLastPathComponent().lastPathComponent + "/" + file.name)
                        .font(TypeScale.row).lineLimit(1).truncationMode(.middle)
                    if isKept {
                        Text(suggested[group.id] == file.url ? "Kept · Suggested" : "Kept")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x5CC8F0))
                    }
                    if clones[file.url] == true {
                        Text("Shares space")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                            .help("An APFS clone: removing it frees little or no space.")
                    }
                }
                Text(file.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if let date = file.modificationDate {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
            }
            if !isKept {
                TriStateCheckbox(state: isSelected ? .on : .off) {
                    if isSelected { selectedItems.remove(file.url) } else { selectedItems.insert(file.url) }
                }
                .help("Remove this copy")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .task(id: file.url) {
            let path = file.url.path(percentEncoded: false)
            let shares = await Task.detached { CloneInfo.read(path: path)?.mayShareBlocks ?? false }.value
            clones[file.url] = shares
        }
        .contextMenu {
            Button(L10n.tr("在 Finder 中显示", "Reveal in Finder", "Показать в Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
        }
    }

    /// Make `file` the kept copy of its set: it becomes the original and is
    /// never selected; the previous original becomes a selectable copy.
    private func keep(_ file: FileItem, in group: DuplicateDisplayGroup) {
        guard file.url != group.original.url,
              let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let wasSelected = selectedItems.contains(file.url)
        let others = group.allFiles.filter { $0.url != file.url }
        groups[index] = DuplicateDisplayGroup(id: group.id, original: file, duplicates: others)
        selectedItems.remove(file.url)
        if wasSelected { selectedItems.insert(group.original.url) }
    }

    private func autoKeep(_ rule: AutoKeep) {
        for group in groups {
            let files = group.allFiles
            let choice: FileItem?
            switch rule {
            case .suggested: choice = files.first { $0.url == suggested[group.id] }
            case .newest: choice = files.max { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
            case .oldest: choice = files.min { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
            }
            if let choice { keep(choice, in: groups.first { $0.id == group.id } ?? group) }
        }
    }
}
