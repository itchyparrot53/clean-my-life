import SwiftUI
import MacCleanKit

/// Browser Tabs (UI_SPEC §5.22). V1 reads tabs through AppleScript; the
/// Chrome/Safari extensions replace the bridge later.
struct BrowserTabsView: View {
    @State private var tabs: [BrowserTabsScanner.Tab] = []
    @State private var selected: Set<String> = []
    @State private var filter = Filter.all
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var error: String?
    @State private var status: String?

    private enum Filter: String, CaseIterable, Identifiable {
        case all, duplicates, safari, chromium
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "All"
            case .duplicates: "Duplicates"
            case .safari: "Safari"
            case .chromium: "Chrome, Brave, Edge"
            }
        }
    }

    private var visible: [BrowserTabsScanner.Tab] {
        switch filter {
        case .all: tabs
        case .duplicates: tabs.filter(\.isDuplicate)
        case .safari: tabs.filter { $0.browser == "Safari" }
        case .chromium: tabs.filter { $0.browser != "Safari" }
        }
    }

    private var domains: Int { Set(tabs.map(\.domain)).count }
    private var duplicates: Int { tabs.filter(\.isDuplicate).count }

    var body: some View {
        CardSpaceReader { _ in
            VStack(alignment: .leading, spacing: 12) {
                header
                if let error {
                    banner(error, symbol: "exclamationmark.triangle.fill", tint: Color(hex: 0xF8C04E))
                }
                if let status {
                    banner(status, symbol: "checkmark.circle.fill", tint: Color(hex: 0x5EE6C8))
                }
                filterRow
                if visible.isEmpty {
                    empty
                } else {
                    list
                }
                footer
            }
            .padding(.horizontal, 26)
            .padding(.top, 10)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(TypeScale.primaryText)
        }
        .topBarTitle(L10n.tr("浏览器标签", "Browser Tabs", "Вкладки браузера"))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("浏览器标签", "Browser Tabs", "Вкладки браузера"))
                    .font(TypeScale.reviewTitle)
                Text(hasScanned
                     ? "\(tabs.count) tabs across \(domains) sites · \(duplicates) duplicate\(duplicates == 1 ? "" : "s")"
                     : "See every open tab, group the duplicates and close what you no longer need.")
                    .font(TypeScale.reviewDescription)
                    .foregroundStyle(TypeScale.secondaryText)
            }
            Spacer()
            Button {
                scan()
            } label: {
                Label(hasScanned ? "Refresh" : "Read tabs", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.secondaryPill)
            .disabled(isScanning)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases) { option in
                Button(option.label) { filter = option }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(
                        Capsule().fill(filter == option ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                    )
                    .overlay(Capsule().strokeBorder(Color.white.opacity(filter == option ? 0.28 : 0.10), lineWidth: 1))
                    .buttonStyle(.plain)
            }
            Spacer()
            if !visible.isEmpty {
                Button(selected.count == visible.count ? "Deselect all" : "Select all") {
                    if selected.count == visible.count {
                        selected.removeAll()
                    } else {
                        selected.formUnion(visible.map(\.id))
                    }
                }
                .font(.system(size: 11.5))
                .buttonStyle(.plain)
                .foregroundStyle(TypeScale.secondaryText)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(visible) { tab in
                    row(tab)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
    }

    private func row(_ tab: BrowserTabsScanner.Tab) -> some View {
        let isSelected = selected.contains(tab.id)
        return HStack(spacing: 10) {
            Button {
                if isSelected { selected.remove(tab.id) } else { selected.insert(tab.id) }
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Color(hex: 0xF3A3C7) : Color.white.opacity(0.35))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(tab.title.isEmpty ? tab.domain : tab.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    if tab.isDuplicate {
                        Text("duplicate")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: 0xF8C04E).opacity(0.16)))
                            .foregroundStyle(Color(hex: 0xF8C04E))
                    }
                }
                Text(tab.domain)
                    .font(.system(size: 11))
                    .foregroundStyle(TypeScale.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(tab.browser) · window \(tab.window)")
                .font(.system(size: 10.5))
                .foregroundStyle(TypeScale.tertiaryText)
                .lineLimit(1)
            Button("Close") { close([tab]) }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: 0xF3A3C7))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.white.opacity(0.10) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { selected.remove(tab.id) } else { selected.insert(tab.id) }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: isScanning ? "hourglass" : "square.on.square")
                .font(.system(size: 30))
                .foregroundStyle(TypeScale.tertiaryText)
            Text(isScanning ? "Reading tabs…" : (hasScanned ? "No tabs match this filter." : "No browser tabs read yet."))
                .font(.system(size: 13, weight: .medium))
            if !hasScanned {
                Text("macOS asks for Automation permission the first time. Safari, Chrome, Brave and Edge are supported.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(TypeScale.tertiaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(selected.count) selected")
                .font(.system(size: 12))
                .foregroundStyle(TypeScale.secondaryText)
            Spacer()
            Button {
                close(tabs.filter { selected.contains($0.id) })
            } label: {
                Text("Close Tabs").font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Capsule().fill(Color(hex: 0x5CC8F0).opacity(selected.isEmpty ? 0.18 : 0.9)))
                    .foregroundStyle(selected.isEmpty ? Color.white.opacity(0.4) : Color(hex: 0x10212A))
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty)
        }
    }

    private func banner(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.system(size: 11.5)).foregroundStyle(TypeScale.secondaryText)
            Spacer()
            Button {
                error = nil; status = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(TypeScale.tertiaryText)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(tint.opacity(0.26)))
    }

    private func scan() {
        isScanning = true
        error = nil
        status = nil
        Task { @MainActor in
            let result = BrowserTabsScanner().scan()
            tabs = result.tabs
            selected = selected.filter { id in result.tabs.contains { $0.id == id } }
            error = result.errors.isEmpty ? nil : result.errors.joined(separator: " ")
            hasScanned = true
            isScanning = false
            if result.errors.isEmpty, result.tabs.isEmpty {
                status = "No tabs were found. Open a browser with tabs and try again."
            }
        }
    }

    private func close(_ targets: [BrowserTabsScanner.Tab]) {
        guard !targets.isEmpty else { return }
        Task { @MainActor in
            let errors = BrowserTabsScanner().close(targets)
            let closed = Set(targets.map(\.id))
            tabs.removeAll { closed.contains($0.id) }
            selected.subtract(closed)
            if errors.isEmpty {
                status = "Closed \(targets.count) tab\(targets.count == 1 ? "" : "s")."
            } else {
                error = errors.joined(separator: " ")
            }
        }
    }
}
