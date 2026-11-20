import AppKit
import SwiftUI
import MacCleanKit

struct ShredderView: View {
    @AppStorage("removeBackgroundColors") private var removeBackgroundColors = false
    @State private var filesToShred: [URL] = []
    @State private var eraseMode: SecureEraser.EraseMode = .standard
    @State private var isProcessing = false
    @State private var result: SecureEraser.EraseResult?

    private let eraser = SecureEraser()

    @State private var dropTargeted = false
    @State private var confirmShred = false
    @Namespace private var morph

    private var stateKey: String {
        result != nil ? "done" : isProcessing ? "working" : filesToShred.isEmpty ? "intro" : "list"
    }

    private var totalSize: UInt64 {
        filesToShred.reduce(UInt64(0)) { total, url in
            total + UInt64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
    }

    private var modeLabel: String {
        switch eraseMode {
        case .standard: L10n.tr("移到废纸篓", "Move to Trash", "В Корзину")
        case .permanent: L10n.tr("永久删除", "Permanent Delete", "Безвозвратно")
        case .secure: L10n.tr("安全擦除", "Secure Erase", "С перезаписью")
        }
    }

    var body: some View {
        ZStack {
            content
                .id(stateKey)
                .transition(TemplateMotion.stateTransition)
        }
        .animation(TemplateMotion.morph, value: stateKey)
        .environment(\.templateNamespace, morph)
        // A34: the whole module area takes dropped files.
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        result = nil
                        if !filesToShred.contains(url) { filesToShred.append(url) }
                    }
                }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(8)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: dropTargeted)
        .alert(L10n.tr("粉碎 \(filesToShred.count) 个项目？", "Shred \(filesToShred.count) item\(filesToShred.count == 1 ? "" : "s")?", "Уничтожить \(filesToShred.count)?"),
               isPresented: $confirmShred) {
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) {}
            Button(L10n.tr("粉碎", "Shred", "Уничтожить"), role: .destructive) { shred() }
        } message: {
            Text("This can't be undone. On SSDs, deleted data can't be guaranteed unrecoverable. \(MCConstants.appName) removes the file and frees its blocks.")
        }
        .moduleStage(isProcessing ? .working : (result != nil ? .results : .idle))
    }

    @ViewBuilder
    private var content: some View {
        if let result {
            DoneTemplate(
                title: L10n.tr("已擦除 \(result.erasedCount) 个文件", "\(result.erasedCount) item\(result.erasedCount == 1 ? "" : "s") shredded", "Уничтожено: \(result.erasedCount)"),
                subtitle: FileSizeFormatter.format(result.totalSize),
                palette: .shredder,
                isWarning: !result.errors.isEmpty,
                extra: {
                    if let firstError = result.errors.first?.1 {
                        Text(firstError + (result.errors.count > 1 ? " (+\(result.errors.count - 1) more)" : ""))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .textSelection(.enabled)
                    }
                },
                onDone: {
                    self.result = nil
                    filesToShred = []
                })
            .overlay {
                if result.errors.isEmpty { ShredConfetti().allowsHitTesting(false) }
            }
        } else if isProcessing {
            ScanningTemplate(title: L10n.tr("正在粉碎…", "Shredding…", "Уничтожение…"),
                             intro: SidebarItem.shredder.intro, palette: .shredder,
                             path: filesToShred.first?.lastPathComponent, progress: 0.5)
        } else if filesToShred.isEmpty {
            IntroTemplate(title: L10n.tr("文件粉碎", "Shredder", "Уничтожение файлов"),
                          intro: SidebarItem.shredder.intro, palette: .shredder,
                          primaryMeta: dropTargeted ? "Drop to add" : "or drop files here",
                          control: { modePicker },
                          onPrimary: selectFiles)
                .scaleEffect(dropTargeted ? 1.02 : 1)
                .offset(y: dropTargeted ? -8 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dropTargeted)
        } else {
            fileList
        }
    }

    private var modePicker: some View {
        Picker(L10n.tr("模式", "Mode", "Режим"), selection: $eraseMode) {
            Text(L10n.tr("移到废纸篓", "Move to Trash", "В Корзину")).tag(SecureEraser.EraseMode.standard)
            Text(L10n.tr("永久删除", "Permanent Delete", "Безвозвратно")).tag(SecureEraser.EraseMode.permanent)
            Text(L10n.tr("安全擦除", "Secure Erase", "С перезаписью")).tag(SecureEraser.EraseMode.secure)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 320)
    }

    private var fileList: some View {
        CardSpaceReader { space in
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("已选择 \(filesToShred.count) 个文件", "\(filesToShred.count) item\(filesToShred.count == 1 ? "" : "s") to shred", "Выбрано: \(filesToShred.count)"))
                    .font(TypeScale.reviewTitle)
                HStack {
                    modePicker
                    Spacer()
                    Button(L10n.tr("添加文件…", "Add Files…", "Добавить…"), action: selectFiles).buttonStyle(.ghostPill)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filesToShred.enumerated()), id: \.element) { index, url in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(url.lastPathComponent).font(TypeScale.row).lineLimit(1)
                                    Text(url.deletingLastPathComponent().path(percentEncoded: false))
                                        .font(.system(size: 11)).foregroundStyle(TypeScale.tertiaryText)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 8)
                                Button {
                                    filesToShred.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "xmark.circle").foregroundStyle(TypeScale.secondaryText)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L10n.tr("移除", "Remove from list", "Убрать"))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .staggerIn(index)
                        }
                    }
                }
                .cardList()
            }
            .foregroundStyle(TypeScale.primaryText)
            .padding(.top, 8)
            .padding(.bottom, space.buttonReserve)
            .overlay {
                PrimarySlot {
                    PrimaryButton(label: L10n.tr("粉碎", "Shred", "Уничтожить"),
                                  meta: FileSizeFormatter.format(totalSize) + " · " + modeLabel, tint: .pink) {
                        confirmShred = true
                    }
                }
            }
        }
        .topBarBack(L10n.tr("返回", "Back", "Назад")) { filesToShred = [] }
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            result = nil
            filesToShred = Array(Set(filesToShred + panel.urls)).sorted { $0.path < $1.path }
        }
    }

    private func shred() {
        isProcessing = true
        Task {
            result = await eraser.erase(urls: filesToShred, mode: eraseMode)
            isProcessing = false
        }
    }
}

/// A23: 40 small squares burst and fall away, 0.9 s.
private struct ShredConfetti: View {
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cardGeometry) private var geometry

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSince(start)
                Canvas { ctx, size in
                    guard t < 0.9 else { return }
                    let origin = CGPoint(x: 0.76 * geometry.card.width - geometry.content.minX,
                                         y: 0.45 * geometry.card.height - geometry.content.minY)
                    for i in 0..<40 {
                        let seed = Double(i) * 12.9898
                        let angle = (seed.truncatingRemainder(dividingBy: 6.283))
                        let speed = 80 + (seed * 7).truncatingRemainder(dividingBy: 120)
                        let x = origin.x + cos(angle) * speed * t
                        let y = origin.y + sin(angle) * speed * t * 0.6 + 260 * t * t
                        let alpha = max(0, 1 - t / 0.9)
                        let colors: [Color] = [.white, Color(hex: 0x5CC8F0), Color(hex: 0xF3A3C7), Color(hex: 0xF8C04E)]
                        ctx.fill(Path(CGRect(x: x, y: y, width: 6, height: 6)),
                                 with: .color(colors[i % colors.count].opacity(alpha)))
                    }
                }
            }
            .onAppear { start = Date() }
        }
    }
}
