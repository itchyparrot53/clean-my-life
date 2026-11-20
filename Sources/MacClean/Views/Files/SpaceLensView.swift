import AppKit
import SwiftUI
import Combine
import MacCleanKit

/// Live item counter for the scan, so the UI shows real movement. A MainActor
/// reference type (Sendable) so the scanner's `@Sendable` callback can update it.
@MainActor
private final class SpaceLensScanProgress: ObservableObject {
    @Published var itemsScanned = 0
}

/// Clean1 Space Map (UI_SPEC §5.14): intro with the disk picker, then a
/// folder list beside our sunburst. Sizes come from Mac Sai's flat-memory
/// top-level scanner; the second ring fills in for the biggest folders.
struct SpaceLensView: View {
    @Environment(AppState.self) private var appState
    @State private var location = ScanLocation.volumes().first ?? .home
    @State private var started = false
    @State private var rootNode: FileNode?
    @State private var children: [FileNode] = []
    @State private var grandchildren: [URL: [FileNode]] = [:]
    @State private var isScanning = false
    @State private var scanTask: Task<Void, Never>?
    @State private var ringTask: Task<Void, Never>?
    @State private var nav = SpaceLensNavigation(root: MCConstants.home)
    @State private var forward: [URL] = []
    @State private var hovered: URL?
    @State private var selected: Set<URL> = []
    @State private var showSelected = false
    @State private var confirmRemove = false
    @State private var removing = false
    @State private var removeError: String?
    @StateObject private var scanProgress = SpaceLensScanProgress()
    @Environment(\.toasts) private var toasts
    @Namespace private var morph

    private let scanner = FileTreeScanner()

    private var stateKey: String { !started ? "intro" : (isScanning && rootNode == nil) ? "scanning" : "results" }

    private var selectedBytes: UInt64 {
        children.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.totalSize }
    }

    var body: some View {
        ZStack {
            content
                .id(stateKey)
                .transition(TemplateMotion.stateTransition)
        }
        .animation(TemplateMotion.morph, value: stateKey)
        .environment(\.templateNamespace, morph)
        .moduleStage(isScanning || removing ? .working : (rootNode == nil ? .idle : .results))
        .sidebarBadge(rootNode.map { .size($0.totalSize) })
        .respondsToModuleShortcuts(onScan: begin, canScan: !isScanning)
        .alert(L10n.tr("移到废纸篓？", "Move \(selected.count) item\(selected.count == 1 ? "" : "s") to the Trash?", "Переместить в Корзину?"),
               isPresented: $confirmRemove) {
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) {}
            Button(L10n.tr("移到废纸篓", "Move to Trash", "В Корзину"), role: .destructive) { remove() }
        } message: {
            Text("\(FileSizeFormatter.format(selectedBytes)). You can put them back from the Trash.")
        }
        .alert(L10n.tr("空间透视", "Space Map", "Карта диска"),
               isPresented: Binding(get: { removeError != nil }, set: { if !$0 { removeError = nil } })) {
            Button("OK", role: .cancel) { removeError = nil }
        } message: { Text(removeError ?? "") }
    }

    @ViewBuilder
    private var content: some View {
        if !started {
            IntroTemplate(title: L10n.tr("空间透视", "Space Map", "Карта диска"),
                          intro: SidebarItem.spaceLens.intro, palette: .spaceMap,
                          control: { DiskPicker(selection: $location) },
                          onPrimary: begin)
        } else if isScanning && rootNode == nil {
            ScanningTemplate(
                intro: SidebarItem.spaceLens.intro, palette: .spaceMap,
                path: nav.current.path(percentEncoded: false),
                found: scanProgress.itemsScanned > 0 ? "\(scanProgress.itemsScanned.formatted()) items" : nil,
                progress: min(0.95, Double(scanProgress.itemsScanned) / Double(scanProgress.itemsScanned + 40_000)),
                onStop: cancel)
        } else {
            results
        }
    }

    // MARK: Results

    private var results: some View {
        CardSpaceReader { space in
            let listWidth = space.geometry.content.width * 0.42
            return ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 16) {
                    folderList
                        .frame(width: listWidth)
                        .staggerIn(0)
                    GeometryReader { proxy in
                        let diameter = min(0.42 * space.W, proxy.size.height * 0.92, proxy.size.width * 0.95)
                        Sunburst(
                            rootName: rootNode?.name ?? "",
                            rootSize: rootNode?.totalSize ?? 0,
                            children: children,
                            grandchildren: grandchildren,
                            palette: .spaceMap,
                            hovered: $hovered,
                            onOpen: drill(into:),
                            onUp: nav.canGoUp ? { up() } : nil)
                            .frame(width: diameter, height: diameter)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                            .id(nav.current)
                    }
                    .staggerIn(1)
                }
                .padding(.top, 4)
                .padding(.bottom, space.buttonReserve)

                diskLabel(width: 0.18 * space.W)
                    .position(x: 0.09 * space.W + 4, y: space.buttonCenter.y)

                PrimarySlot {
                    PrimaryButton(label: L10n.tr("移除", "Remove", "Удалить"),
                                  meta: selected.isEmpty ? nil : FileSizeFormatter.format(selectedBytes),
                                  progress: removing ? 0.5 : nil,
                                  isEnabled: !selected.isEmpty) { confirmRemove = true }
                }
                Button(L10n.tr("查看所选", "Review Selected", "Выбранное")) { showSelected.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0x5CC8F0))
                    .disabled(selected.isEmpty)
                    .popover(isPresented: $showSelected, arrowEdge: .top) { selectedPopover }
                    .position(x: space.buttonCenter.x + 190, y: space.buttonCenter.y)
            }
        }
        .topBarBack(L10n.tr("重新开始", "Start Over", "Начать заново"), action: startOver)
        .topBarTitle(L10n.tr("空间透视", "Space Map", "Карта диска"))
    }

    private var folderList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: up) { Image(systemName: "chevron.left") }
                    .disabled(!nav.canGoUp)
                    .accessibilityLabel(L10n.tr("上一级", "Back", "Назад"))
                Button(action: goForward) { Image(systemName: "chevron.right") }
                    .disabled(forward.isEmpty)
                    .accessibilityLabel(L10n.tr("前进", "Forward", "Вперёд"))
                Button { forward = []; nav.home(); scan() } label: { Image(systemName: "house") }
                    .disabled(!nav.canGoUp)
                    .accessibilityLabel(L10n.tr("返回起点", "Back to start", "В начало"))
                Menu {
                    ForEach(nav.breadcrumbs.reversed(), id: \.self) { url in
                        Button(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent) {
                            forward = []
                            nav.navigate(to: url)
                            scan()
                        }
                    }
                } label: {
                    Text(nav.current.lastPathComponent.isEmpty ? nav.current.path : nav.current.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer()
                if isScanning { ProgressView().controlSize(.small) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(TypeScale.primaryText)
            .frame(height: 28)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(children, id: \.url) { node in
                        row(node)
                    }
                }
            }
            .cardList()
        }
    }

    private func row(_ node: FileNode) -> some View {
        let isOn = selected.contains(node.url)
        return HStack(spacing: 10) {
            TriStateCheckbox(state: isOn ? .on : .off) {
                if isOn { selected.remove(node.url) } else { selected.insert(node.url) }
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).font(TypeScale.row).lineLimit(1)
                Text(node.isDirectory ? subline(for: node) : node.fileExtension.uppercased())
                    .font(.system(size: 11))
                    .foregroundStyle(TypeScale.tertiaryText)
            }
            Spacer(minLength: 6)
            Text(node.formattedTotalSize)
                .font(TypeScale.rowSize)
                .foregroundStyle(.white.opacity(0.8))
                .numericRoll(node.totalSize)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TypeScale.tertiaryText)
                .opacity(node.isDirectory ? 1 : 0)
        }
        .foregroundStyle(TypeScale.primaryText)
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: Surface.rowRadius, style: .continuous)
                .fill(hovered == node.url ? Surface.rowSelection : .clear))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = node.url } else if hovered == node.url { hovered = nil }
        }
        .onTapGesture(count: 2) { if node.isDirectory { drill(into: node.url) } }
        .contextMenu {
            Button(L10n.tr("在 Finder 中显示", "Reveal in Finder", "Показать в Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            if node.isDirectory {
                Button(L10n.tr("打开", "Open", "Открыть")) { drill(into: node.url) }
            }
        }
    }

    private func subline(for node: FileNode) -> String {
        if let kids = grandchildren[node.url] { return "\(kids.count) items" }
        return L10n.tr("文件夹", "Folder", "Папка")
    }

    private func diskLabel(width: CGFloat) -> some View {
        let volume = ScanLocation.volume(nav.current.path == "/" ? nav.current
            : (try? nav.current.resourceValues(forKeys: [.volumeURLKey]).volume) ?? URL(filePath: "/"))
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(volume?.name ?? location.name): \(volume?.available.map { FileSizeFormatter.format(UInt64($0)) + " free" } ?? "")")
                .font(.system(size: 11))
                .foregroundStyle(TypeScale.secondaryText)
                .lineLimit(1)
            if let volume, let total = volume.total, let used = volume.used, total > 0 {
                Capsule().fill(Color.white.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color(hex: 0x5EE6A0))
                            .frame(width: width * CGFloat(used) / CGFloat(total))
                    }
                    .frame(width: width, height: 4)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var selectedPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(children.filter { selected.contains($0.url) }, id: \.url) { node in
                HStack(spacing: 8) {
                    TriStateCheckbox(state: .on, size: 14) { selected.remove(node.url) }
                    Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                        .resizable().frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(node.name).font(.system(size: 12)).lineLimit(1)
                        Text(node.url.path(percentEncoded: false))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Text(node.formattedTotalSize).font(.system(size: 12).monospacedDigit())
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .clean1PopoverSurface()
    }

    // MARK: Navigation and scanning

    private func begin() {
        let url = location.url.path == "/" ? MCConstants.home : location.url
        nav = SpaceLensNavigation(root: url)
        forward = []
        selected = []
        rootNode = nil
        started = true
        scan()
    }

    private func startOver() {
        cancel()
        started = false
        rootNode = nil
        children = []
        grandchildren = [:]
        selected = []
    }

    private func cancel() {
        scanTask?.cancel()
        ringTask?.cancel()
        nav.cancelPendingNavigation()
        isScanning = false
        if rootNode == nil { started = false }
    }

    private func drill(into url: URL) {
        forward = []
        nav.drillInto(url)
        scan()
    }

    private func up() {
        guard nav.canGoUp else { return }
        forward.append(nav.current)
        nav.up()
        scan()
    }

    private func goForward() {
        guard let next = forward.popLast() else { return }
        nav.drillInto(next)
        scan()
    }

    private func scan() {
        scanTask?.cancel()
        ringTask?.cancel()
        isScanning = true
        selected = []
        scanProgress.itemsScanned = 0
        let root = nav.current
        let progress = scanProgress
        scanTask = Task {
            // Size only the immediate children, each aggregated into one
            // running total: flat memory even for a whole home folder.
            let found = await scanner.topLevelSizes(root: root) { count in
                Task { @MainActor in progress.itemsScanned = count }
            }
            guard !Task.isCancelled else { return }
            let sorted = found.sorted { $0.totalSize > $1.totalSize }
            let total = sorted.reduce(UInt64(0)) { $0 + $1.totalSize }
            rootNode = FileNode(url: root, name: root.lastPathComponent, size: total, isDirectory: true)
            children = sorted
            grandchildren = [:]
            nav.commitPendingNavigation()
            isScanning = false
            fillSecondRing(for: sorted)
        }
    }

    /// Ring 2: size the children of the six biggest folders, one at a time,
    /// so the chart grows in as each arrives (A22).
    private func fillSecondRing(for nodes: [FileNode]) {
        let folders = nodes.filter(\.isDirectory).prefix(6).map(\.url)
        ringTask = Task {
            for folder in folders {
                let kids = await scanner.topLevelSizes(root: folder)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    grandchildren[folder] = kids.sorted { $0.totalSize > $1.totalSize }
                }
            }
        }
    }

    private func remove() {
        let items = children.filter { selected.contains($0.url) }.map {
            FileItem(url: $0.url, name: $0.name, size: $0.totalSize, allocatedSize: $0.totalSize,
                     isDirectory: $0.isDirectory)
        }
        let selection = selected
        removing = true
        Task {
            let result = await CleanActions.executeUserClean(items: items, selectedItems: selection,
                                                             engine: appState.cleaningEngine)
            removing = false
            if result.removedCount > 0 { toasts?.movedToTrash(FileSizeFormatter.format(result.freedBytes)) }
            if let first = result.errors.first {
                removeError = "\(result.removedCount) moved to the Trash. \(result.errors.count) couldn't be: \(first.error)"
            }
            scan()
        }
    }
}

// MARK: - Sunburst (§5.14, A20–A22)

/// Centre disc for the current folder, ring 1 for its children, ring 2 for
/// theirs. Hover highlights a segment and its list row; clicking a folder
/// zooms into it; clicking the centre goes up.
private struct Sunburst: View {
    struct Segment: Identifiable {
        let id: URL
        let name: String
        let size: UInt64
        let start: Double
        let end: Double
        let depth: Int
        let isDirectory: Bool
    }

    let rootName: String
    let rootSize: UInt64
    let children: [FileNode]
    let grandchildren: [URL: [FileNode]]
    let palette: ModulePalette
    @Binding var hovered: URL?
    let onOpen: (URL) -> Void
    let onUp: (() -> Void)?

    @State private var grow: Double = 0
    @State private var zoomed: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let centre = 0.30
    private static let ring1 = (0.32, 0.64)
    private static let ring2 = (0.66, 0.96)

    private var segments: [Segment] {
        let total = Double(max(1, children.reduce(UInt64(0)) { $0 + $1.totalSize }))
        var result: [Segment] = []
        var cursor = 0.0
        var other: UInt64 = 0
        for node in children {
            let span = Double(node.totalSize) / total
            if span < 0.006 { other += node.totalSize; continue }
            result.append(Segment(id: node.url, name: node.name, size: node.totalSize,
                                  start: cursor, end: cursor + span, depth: 1, isDirectory: node.isDirectory))
            if let kids = grandchildren[node.url] {
                let kidTotal = Double(max(1, kids.reduce(UInt64(0)) { $0 + $1.totalSize }))
                var inner = cursor
                for kid in kids {
                    let kidSpan = span * Double(kid.totalSize) / kidTotal
                    if kidSpan < 0.004 { continue }
                    result.append(Segment(id: kid.url, name: kid.name, size: kid.totalSize,
                                          start: inner, end: inner + kidSpan, depth: 2, isDirectory: kid.isDirectory))
                    inner += kidSpan
                }
            }
            cursor += span
        }
        if other > 0 {
            result.append(Segment(id: URL(filePath: "/.clean1-other"), name: "Other", size: other,
                                  start: cursor, end: 1, depth: 1, isDirectory: false))
        }
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                ForEach(segments) { segment in
                    segmentView(segment, radius: radius)
                }
                Circle()
                    .fill(palette.top.lightened(0.6).opacity(0.85))
                    .frame(width: radius * 2 * Self.centre, height: radius * 2 * Self.centre)
                    .overlay {
                        VStack(spacing: 2) {
                            Text(hoveredSegment?.name ?? rootName)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(FileSizeFormatter.format(hoveredSegment?.size ?? rootSize))
                                .font(.system(size: 11).monospacedDigit())
                                .opacity(0.8)
                        }
                        .foregroundStyle(Color.black.opacity(0.7))
                        .padding(.horizontal, 8)
                    }
                    .onTapGesture { onUp?() }
                    .help(onUp == nil ? "" : "Up one level")
            }
            .contentShape(Circle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = hit(point, centre: centre, radius: radius)?.id
                case .ended: hovered = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                guard let segment = hit(value.location, centre: centre, radius: radius), segment.isDirectory else { return }
                zoom(into: segment.id)
            })
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { grow = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rootName), \(FileSizeFormatter.format(rootSize))")
    }

    private var hoveredSegment: Segment? { segments.first { $0.id == hovered } }

    private func segmentView(_ segment: Segment, radius: CGFloat) -> some View {
        let isHovered = hovered == segment.id
        let isZoomed = zoomed == segment.id
        let ring = segment.depth == 1 ? Self.ring1 : Self.ring2
        let start = isZoomed ? 0 : segment.start * grow
        let end = isZoomed ? 1 : (segment.start + (segment.end - segment.start)) * grow
        let mid = (segment.start + segment.end) / 2 * 2 * .pi - .pi / 2
        // Neighbours alternate slightly so adjacent segments read apart.
        let index = segments.firstIndex { $0.id == segment.id } ?? 0
        let shade = segment.depth == 1 ? (index.isMultiple(of: 2) ? 0.4 : 0.28) : (index.isMultiple(of: 2) ? 0.25 : 0.12)
        let lift: CGFloat = isHovered ? 5 : 0
        return ArcShape(start: start, end: end, inner: ring.0, outer: ring.1)
            .fill(palette.top.lightened(shade))
            .overlay(ArcShape(start: start, end: end, inner: ring.0, outer: ring.1)
                .stroke(palette.bottom.opacity(0.6), lineWidth: 1))
            .brightness(isHovered ? 0.12 : 0)
            .opacity(zoomed != nil && !isZoomed ? 0 : (hovered == nil || isHovered ? 1 : 0.8))
            .offset(x: cos(mid) * lift, y: sin(mid) * lift)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .frame(width: radius * 2, height: radius * 2)
    }

    /// Which segment is under `point`.
    private func hit(_ point: CGPoint, centre: CGPoint, radius: CGFloat) -> Segment? {
        let dx = point.x - centre.x, dy = point.y - centre.y
        let distance = sqrt(dx * dx + dy * dy) / radius
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        let fraction = angle / (2 * .pi)
        let depth: Int
        if distance >= Self.ring1.0 && distance <= Self.ring1.1 { depth = 1 }
        else if distance >= Self.ring2.0 && distance <= Self.ring2.1 { depth = 2 }
        else { return nil }
        return segments.first { $0.depth == depth && fraction >= $0.start && fraction < $0.end }
    }

    /// A21: the clicked segment sweeps to the full ring while the others
    /// fade, then the folder opens.
    private func zoom(into url: URL) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.88)) { zoomed = url }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 380))
            onOpen(url)
        }
    }
}

/// An annular sector; angles are fractions of a full turn from 12 o'clock,
/// radii are fractions of the view's radius. Animatable for A21/A22.
private struct ArcShape: Shape {
    var start: Double
    var end: Double
    let inner: Double
    let outer: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, end) }
        set { start = newValue.first; end = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let a0 = Angle(radians: start * 2 * .pi - .pi / 2)
        let a1 = Angle(radians: max(start, end - 0.002) * 2 * .pi - .pi / 2)
        var path = Path()
        path.addArc(center: centre, radius: radius * outer, startAngle: a0, endAngle: a1, clockwise: false)
        path.addArc(center: centre, radius: radius * inner, startAngle: a1, endAngle: a0, clockwise: true)
        path.closeSubpath()
        return path
    }
}
