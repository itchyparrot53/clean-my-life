import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MacCleanKit

/// Tools page (UI_SPEC §5.23): a grid of 140 × 110 pt tiles. Right-click to
/// pin; pinned tiles come first; drag a tile to reorder.
struct ToolsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("clean1.tools.order") private var orderRaw = ""
    @AppStorage("clean1.tools.pinned") private var pinnedRaw = ""
    @State private var dragging: String?

    struct Tool: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let blurb: String
        let open: @MainActor () -> Void
    }

    private var allTools: [Tool] {
        SidebarItem.toolItems.map { item in
            Tool(id: item.deepLinkID, title: item.title, symbol: item.icon, blurb: item.intro.subtitle) {
                appState.selectedSidebarItem = item
            }
        } + [
            Tool(id: "screen-cleaning", title: "Screen Cleaning", symbol: "sparkles.tv",
                 blurb: "Black out every screen and lock the keyboard for two minutes while you wipe.") {
                ScreenCleaning.shared.start()
            },
            Tool(id: SidebarItem.activityItem.deepLinkID, title: SidebarItem.activityItem.title,
                 symbol: SidebarItem.activityItem.icon, blurb: "What's been cleaned, and what can be put back.") {
                appState.selectedSidebarItem = SidebarItem.activityItem
            },
        ]
    }

    private var pinned: Set<String> { Set(pinnedRaw.split(separator: ",").map(String.init)) }

    /// Saved order first (with any new tools appended), pinned tiles on top.
    private var ordered: [Tool] {
        let saved = orderRaw.split(separator: ",").map(String.init)
        let byID = Dictionary(uniqueKeysWithValues: allTools.map { ($0.id, $0) })
        var list = saved.compactMap { byID[$0] }
        list += allTools.filter { !saved.contains($0.id) }
        return list.filter { pinned.contains($0.id) } + list.filter { !pinned.contains($0.id) }
    }

    var body: some View {
        CardSpaceReader { space in
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("工具", "Tools", "Инструменты")).font(TypeScale.reviewTitle)
                Text("Right-click a tile to pin it. Drag to reorder.")
                    .font(TypeScale.reviewDescription).foregroundStyle(.white.opacity(0.7))
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 14)], spacing: 14) {
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, tool in
                            tile(tool).staggerIn(index)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .foregroundStyle(TypeScale.primaryText)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .topBarTitle(L10n.tr("工具", "Tools", "Инструменты"))
    }

    private func tile(_ tool: Tool) -> some View {
        let isPinned = pinned.contains(tool.id)
        return Button { tool.open() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: tool.symbol).font(.system(size: 22))
                    Spacer()
                    if isPinned {
                        Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(TypeScale.secondaryText)
                    }
                }
                Text(tool.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(tool.blurb).font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText).lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.white.opacity(0.10))
                }
            }
            .opacity(dragging == tool.id ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(isPinned ? "Unpin" : "Pin") { togglePin(tool.id) }
        }
        .onDrag {
            dragging = tool.id
            return NSItemProvider(object: tool.id as NSString)
        }
        .onDrop(of: [.text], delegate: TileDrop(target: tool.id, current: $dragging, move: move))
    }

    private func togglePin(_ id: String) {
        var set = pinned
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        pinnedRaw = set.sorted().joined(separator: ",")
    }

    private func move(_ id: String, before target: String) {
        var ids = ordered.map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target), from != to else { return }
        ids.remove(at: from)
        ids.insert(id, at: to)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { orderRaw = ids.joined(separator: ",") }
    }
}

private struct TileDrop: DropDelegate {
    let target: String
    @Binding var current: String?
    let move: (String, String) -> Void

    func dropEntered(info: DropInfo) {
        guard let current, current != target else { return }
        move(current, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        current = nil
        return true
    }
}
