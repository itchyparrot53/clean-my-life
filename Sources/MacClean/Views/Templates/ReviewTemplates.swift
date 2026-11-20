import AppKit
import SwiftUI
import MacCleanKit

// MARK: - Review, in-module (§4.4)

/// Category column on the left, the chosen category's items on the right.
/// The item list is Mac Sai's FileListView, which copes with hundreds of
/// thousands of rows; the columns around it are ours.
struct ReviewTemplate: View {
    let results: [ScanResult]
    @Binding var selectedItems: Set<URL>
    let palette: ModulePalette
    /// Replaces the item list (Duplicates groups, Malware reasons).
    var customContent: (() -> AnyView)?
    /// Off inside the Checkup sheet, where the card's own button stays.
    var showsPrimary = true
    var actionLabel = L10n.tr("清理", "Clean", "Очистить")
    let onBack: () -> Void
    let onAct: () -> Void

    enum CategorySort: String, CaseIterable { case size, name }

    @State private var focused: ScanCategory?
    @State private var categorySort: CategorySort = .size
    @State private var query = ""
    @State private var filtered: [ScanCategory: ScanResult]?

    private var ordered: [ScanResult] {
        switch categorySort {
        case .size: results.sorted { $0.totalSize > $1.totalSize }
        case .name: results.sorted { $0.category.displayName.localizedStandardCompare($1.category.displayName) == .orderedAscending }
        }
    }

    private var current: ScanResult? {
        let category = focused ?? ordered.first?.category
        return results.first { $0.category == category }
    }

    private var allSelected: Bool {
        results.allSatisfy { result in result.items.allSatisfy { selectedItems.contains($0.url) } }
    }

    var body: some View {
        CardSpaceReader { space in
            HStack(alignment: .top, spacing: 18) {
                categoryColumn
                    .frame(width: space.geometry.content.width * 0.33)
                    .staggerIn(0)
                itemColumn
                    .staggerIn(1)
            }
            .padding(.top, 8)
            .padding(.bottom, showsPrimary ? space.buttonReserve : 0)
            .overlay {
                if showsPrimary { PrimarySlot {
                    PrimaryButton(label: actionLabel, meta: FileSizeFormatter.format(results.selectedSize(selectedItems)),
                                  isEnabled: !selectedItems.isEmpty, action: onAct)
                } }
            }
        }
        .modifier(ReviewTopBar(enabled: showsPrimary, query: $query, onBack: onBack))
        .onExitCommand(perform: onBack)
        .task(id: query) { await refilter() }
    }

    // Left column

    private var categoryColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Button(allSelected ? L10n.tr("全部取消", "Deselect All", "Снять все")
                                   : L10n.tr("全选", "Select All", "Выбрать все")) {
                    toggleAll()
                }
                .buttonStyle(.ghostPill)
                Spacer()
                sortMenu
            }
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(ordered, id: \.category) { result in
                        categoryRow(result)
                    }
                }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Button(L10n.tr("按大小", "Size", "Размер")) { categorySort = .size }
            Button(L10n.tr("按名称", "Name", "Имя")) { categorySort = .name }
        } label: {
            HStack(spacing: 3) {
                Text(categorySort == .size ? L10n.tr("按大小排序", "Sort by Size", "По размеру")
                                           : L10n.tr("按名称排序", "Sort by Name", "По имени"))
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

    private func categoryRow(_ result: ScanResult) -> some View {
        let isFocused = result.category == current?.category
        let state = checkState(result)
        let matches = filtered?[result.category]?.items.count
        return HStack(spacing: 10) {
            TriStateCheckbox(state: state) { toggle(result) }
            if result.category.isThreat {
                CategoryTile.threat(result.category.tileSymbol)
            } else {
                CategoryTile(symbol: result.category.tileSymbol, tint: palette.top)
            }
            Text(result.category.displayName)
                .font(TypeScale.row)
                .lineLimit(1)
            Spacer(minLength: 6)
            Group {
                if let matches {
                    Text("\(matches)")
                } else {
                    Text(result.formattedSize)
                }
            }
            .font(TypeScale.rowSize)
            .foregroundStyle(.white.opacity(state == .off ? 0.45 : 0.8))
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: Surface.rowRadius, style: .continuous)
                .fill(isFocused ? Surface.rowSelection : .clear))
        .contentShape(Rectangle())
        .onTapGesture { focused = result.category }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    // Right column

    private var itemColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let current {
                Text(current.category.displayName)
                    .font(TypeScale.reviewTitle)
                    .foregroundStyle(TypeScale.primaryText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: current.category.cleanupSafety.systemImage)
                    Text(current.category.subtitle + " " + current.category.cleanupSafety.label + ".")
                }
                .font(TypeScale.reviewDescription)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)

                Group {
                    if let customContent {
                        customContent()
                    } else {
                        FileListView(results: [filtered?[current.category] ?? current],
                                     selectedItems: $selectedItems)
                            .id(current.category)
                    }
                }
                .background(Color.black.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Selection

    private func checkState(_ result: ScanResult) -> CheckState {
        let urls = result.items.map(\.url)
        let selected = urls.filter(selectedItems.contains).count
        return selected == 0 ? .off : (selected == urls.count ? .on : .mixed)
    }

    private func toggle(_ result: ScanResult) {
        let urls = result.items.map(\.url)
        if checkState(result) == .on { selectedItems.subtract(urls) } else { selectedItems.formUnion(urls) }
    }

    private func toggleAll() {
        if allSelected { selectedItems.removeAll() }
        else { selectedItems = Set(results.flatMap { $0.items.map(\.url) }) }
    }

    /// Search filters the item list across every category; the left column
    /// shows match counts (§4.4). Runs off the main thread for big scans.
    private func refilter() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { filtered = nil; return }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        let snapshot = results
        let result = await Task.detached(priority: .userInitiated) {
            var map: [ScanCategory: ScanResult] = [:]
            for item in snapshot {
                let matches = item.items.filter { $0.name.localizedCaseInsensitiveContains(text) }
                map[item.category] = ScanResult(category: item.category, items: matches, autoSelect: item.autoSelect)
            }
            return map
        }.value
        guard !Task.isCancelled else { return }
        filtered = result
    }
}

/// In-module review owns the top bar (Back + search); inside the Checkup
/// sheet the sheet's own "‹ Back to Summary" does that job instead.
private struct ReviewTopBar: ViewModifier {
    let enabled: Bool
    @Binding var query: String
    let onBack: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .topBarBack(L10n.tr("返回", "Back", "Назад"), action: onBack)
                .topBarSearch(text: $query, prompt: L10n.tr("搜索", "Search", "Поиск"))
        } else {
            content
        }
    }
}

// MARK: - Review sheet (§4.5)

extension View {
    /// The Checkup-style review: the module dims to 35 %, the sidebar dims,
    /// and a sheet rises inside the module area (A12). Esc or
    /// "‹ Back to Summary" closes it.
    func reviewSheet<Sheet: View>(isPresented: Binding<Bool>, header: String,
                                  @ViewBuilder sheet: @escaping () -> Sheet) -> some View {
        modifier(ReviewSheetModifier(isPresented: isPresented, header: header, sheet: sheet))
    }
}

private struct ReviewSheetModifier<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let header: String
    let sheet: () -> Sheet
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? Surface.dimmed : 1)
            .allowsHitTesting(!isPresented)
            .overlay {
                if isPresented {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                isPresented = false
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                                    Text(L10n.tr("返回摘要", "Back to Summary", "К сводке"))
                                }
                                .font(TypeScale.topBarBack)
                                .foregroundStyle(TypeScale.secondaryText)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        Text(header)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TypeScale.tertiaryText)
                        sheet()
                    }
                    .padding(16)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                        ZStack {
                            shape.fill(.ultraThinMaterial)
                            shape.fill(Color.black.opacity(0.22))
                        }
                    }
                    .padding(16)
                    // The card's button stays visible under the sheet (§4.5).
                    .padding(.bottom, CardLayout.primaryButtonDiameter + CardLayout.primaryButtonBottomInset - 8)
                    .transition(reduceMotion ? .opacity : .offset(y: 24).combined(with: .opacity))
                    .onExitCommand { isPresented = false }
                    .sidebarMode(.dimmed)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.88), value: isPresented)
    }
}

// MARK: - List-first (§4.6)

struct FilterItem: Identifiable, Hashable {
    let id: String
    let title: String
    var count: Int?
    /// "Selected" shows its count in a white badge.
    var isBadge = false
    var indent = false
}

struct FilterGroup: Identifiable {
    let id: String
    var header: String?
    let items: [FilterItem]
}

/// Filter column (0.24 of the module area) + a list. The sidebar goes into
/// focused mode while this is showing (A31).
struct ListFirstTemplate<List: View, Trailing: View>: View {
    let groups: [FilterGroup]
    @Binding var selectedFilter: String
    let title: String
    var description: String?
    /// "‹ Intro" in the top bar; focused mode always needs a way out.
    var onBack: (() -> Void)?
    @ViewBuilder var trailingHeader: Trailing
    @ViewBuilder var list: List

    var body: some View {
        CardSpaceReader { space in
            HStack(alignment: .top, spacing: 18) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            if let header = group.header {
                                Text(header)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .padding(.top, 12)
                                    .padding(.bottom, 2)
                                    .padding(.leading, 8)
                            }
                            ForEach(group.items) { item in filterRow(item) }
                        }
                    }
                }
                .frame(width: space.geometry.content.width * 0.24)
                .staggerIn(0)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(TypeScale.reviewTitle)
                        .foregroundStyle(TypeScale.primaryText)
                    if let description {
                        Text(description)
                            .font(TypeScale.reviewDescription)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(3)
                    }
                    HStack { Spacer(); trailingHeader }
                    list
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .staggerIn(1)
            }
            .padding(.top, 8)
            .padding(.bottom, space.buttonReserve)
        }
        .sidebarMode(.focused)
        .modifier(OptionalBack(onBack: onBack))
    }

    private func filterRow(_ item: FilterItem) -> some View {
        let isSelected = item.id == selectedFilter
        return HStack {
            Text(item.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 6)
            if let count = item.count {
                if item.isBadge {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.black.opacity(0.75))
                        .padding(.horizontal, 6)
                        .frame(minHeight: 16)
                        .background(Capsule().fill(.white))
                } else {
                    Text("\(count)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                        .numericRoll(count)
                }
            }
        }
        .foregroundStyle(TypeScale.primaryText)
        .padding(.leading, item.indent ? 20 : 8)
        .padding(.trailing, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: Surface.rowRadius, style: .continuous)
                .fill(isSelected ? Surface.rowSelection : .clear))
        .contentShape(Rectangle())
        .onTapGesture { selectedFilter = item.id }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OptionalBack: ViewModifier {
    let onBack: (() -> Void)?

    func body(content: Content) -> some View {
        if let onBack {
            content
                .topBarBack(L10n.tr("简介", "Intro", "Введение"), action: onBack)
                .onExitCommand(perform: onBack)
        } else {
            content
        }
    }
}

// MARK: - Intro gate

/// Intro first, then the module's own list (UI_SPEC §4.6): the list gets
/// "‹ Intro" in the top bar, Esc goes back, and the sidebar focuses (A31).
struct IntroGate<Control: View, Content: View>: View {
    let item: SidebarItem
    var title: String { item.title }
    var primaryMeta: String?
    var focusSidebar = true
    @Binding var showContent: Bool
    @ViewBuilder var control: Control
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            if showContent {
                content
                    .topBarBack(L10n.tr("简介", "Intro", "Введение")) { showContent = false }
                    .topBarTitle(title)
                    .onExitCommand { showContent = false }
                    .modifier(FocusIf(on: focusSidebar))
                    .transition(TemplateMotion.stateTransition)
            } else {
                IntroTemplate(title: title, intro: item.intro, palette: item.palette,
                              primaryMeta: primaryMeta, control: { control },
                              onPrimary: { showContent = true })
                    .transition(TemplateMotion.stateTransition)
            }
        }
        .animation(TemplateMotion.morph, value: showContent)
    }
}

extension IntroGate where Control == EmptyView {
    init(item: SidebarItem, primaryMeta: String? = nil, focusSidebar: Bool = true,
         showContent: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.init(item: item, primaryMeta: primaryMeta, focusSidebar: focusSidebar,
                  showContent: showContent, control: { EmptyView() }, content: content)
    }
}

private struct FocusIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.sidebarMode(.focused) } else { content }
    }
}

/// Mac Sai's own List-based content, blended onto the card.
extension View {
    func cardList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
