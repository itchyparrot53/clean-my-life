import SwiftUI
import MacCleanKit

struct MaintenanceView: View {
    @State private var taskStates: [MaintenanceTask: TaskState] = [:]
    @State private var executor = MaintenanceExecutor()
    /// When non-nil, the confirmation alert is presented for this task.
    @State private var taskAwaitingConfirmation: MaintenanceTask?

    enum TaskState {
        case idle
        case running
        case completed(String)
        case failed(String)
    }

    @State private var showList = false

    var body: some View {
        IntroGate(item: .maintenance, primaryMeta: nil, focusSidebar: false,
                  showContent: $showList) {
            legacyContent
        }
    }

    @State private var checked: Set<MaintenanceTask> = Set(MaintenanceTask.allCases.filter { $0.severity == .safe })
    @State private var focused: MaintenanceTask = MaintenanceTask.allCases.first!
    @State private var confirmBatch = false

    private var isAnyRunning: Bool { taskStates.values.contains { if case .running = $0 { true } else { false } } }

    /// Two columns (UI_SPEC §5.10): tasks on the left, the chosen task's
    /// explanation on the right, "Run" at the bottom.
    private var legacyContent: some View {
        CardSpaceReader { space in
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button(L10n.tr("推荐", "Recommended", "Рекомендуемые")) {
                            checked = Set(MaintenanceTask.allCases.filter { $0.severity == .safe })
                        }
                        .buttonStyle(.ghostPill)
                        Spacer()
                        Text("\(checked.count) selected")
                            .font(.system(size: 11))
                            .foregroundStyle(TypeScale.tertiaryText)
                    }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(MaintenanceTask.allCases.enumerated()), id: \.element) { index, task in
                                taskListRow(task).staggerIn(index)
                            }
                        }
                    }
                }
                .frame(width: space.geometry.content.width * 0.38)

                taskDetail(focused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .staggerIn(1)
            }
            .foregroundStyle(TypeScale.primaryText)
            .padding(.top, 8)
            .padding(.bottom, space.buttonReserve)
            .overlay {
                PrimarySlot {
                    PrimaryButton(label: L10n.tr("运行", "Run", "Запустить"),
                                  meta: "\(checked.count) task\(checked.count == 1 ? "" : "s")",
                                  progress: isAnyRunning ? runProgress : nil,
                                  isEnabled: !checked.isEmpty) { runChecked() }
                }
            }
        }
        .alert(L10n.tr("包含高级任务", "Includes advanced tasks", "Есть расширенные задачи"), isPresented: $confirmBatch) {
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) {}
            Button(L10n.tr("仍要运行", "Run Anyway", "Всё равно запустить"), role: .destructive) { runBatch() }
        } message: {
            Text(checked.filter { $0.severity == .advanced }.map { "\($0.title): \($0.sideEffects)" }.joined(separator: "\n\n"))
        }
        .alert(
            L10n.tr("运行 \(taskAwaitingConfirmation?.title ?? "")？", "Run \(taskAwaitingConfirmation?.title ?? "")?", "Запустить \(taskAwaitingConfirmation?.title ?? "")?"),
            isPresented: Binding(
                get: { taskAwaitingConfirmation != nil },
                set: { if !$0 { taskAwaitingConfirmation = nil } }
            ),
            presenting: taskAwaitingConfirmation
        ) { task in
            Button(L10n.tr("取消", "Cancel", "Отмена"), role: .cancel) {
                taskAwaitingConfirmation = nil
            }
            Button(L10n.tr("仍要运行", "Run Anyway", "Всё равно запустить"), role: .destructive) {
                let captured = task
                taskAwaitingConfirmation = nil
                runTask(captured)
            }
        } message: { task in
            Text(task.sideEffects)
        }
    }


    private var runProgress: Double {
        let total = max(1, checked.count)
        let done = checked.filter { task in
            switch taskStates[task] { case .completed, .failed: true; default: false }
        }.count
        return Double(done) / Double(total)
    }

    /// Checkbox becomes the status while running: spinner → check / ✕.
    private func taskListRow(_ task: MaintenanceTask) -> some View {
        let isFocused = task == focused
        return HStack(spacing: 10) {
            Group {
                switch taskStates[task] {
                case .running:
                    ProgressView().controlSize(.small).frame(width: 16, height: 16)
                case .completed:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x5EE6A0))
                case .failed:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color(hex: 0xF8C04E))
                default:
                    TriStateCheckbox(state: checked.contains(task) ? .on : .off) {
                        if checked.contains(task) { checked.remove(task) } else { checked.insert(task) }
                    }
                }
            }
            .frame(width: 18)
            CategoryTile(symbol: task.icon, tint: ModulePalette.maintenance.top)
            Text(task.title).font(TypeScale.row).lineLimit(1)
            Spacer(minLength: 4)
            if task.severity == .advanced {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0xF8C04E))
                    .help(L10n.tr("高级", "Advanced", "Расширенная"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Surface.rowRadius, style: .continuous)
            .fill(isFocused ? Surface.rowSelection : .clear))
        .contentShape(Rectangle())
        .onTapGesture { focused = task }
    }

    private func taskDetail(_ task: MaintenanceTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title).font(TypeScale.reviewTitle)
            Text(task.description)
                .font(TypeScale.reviewDescription)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            if task.severity == .advanced {
                Label(task.sideEffects, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xF8C04E))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if task.requiresAdmin {
                Label(L10n.tr("需要管理员密码", "Asks for your administrator password.", "Нужен пароль администратора"), systemImage: "lock")
                    .font(.system(size: 12))
                    .foregroundStyle(TypeScale.secondaryText)
            }
            Text(lastRunText(task))
                .font(.system(size: 11))
                .foregroundStyle(TypeScale.tertiaryText)
            switch taskStates[task] {
            case .completed(let output) where !output.isEmpty:
                Text(output).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(TypeScale.secondaryText).lineLimit(6).textSelection(.enabled)
            case .failed(let message):
                Text(message).font(.system(size: 12)).foregroundStyle(Color(hex: 0xF8C04E)).textSelection(.enabled)
            default:
                EmptyView()
            }
            Button(L10n.tr("仅运行此项", "Run Only This", "Запустить только её")) { didTapRun(task) }
                .buttonStyle(.ghostPill)
                .disabled(isRunning(task))
        }
    }

    private func lastRunText(_ task: MaintenanceTask) -> String {
        guard let date = UserDefaults.standard.object(forKey: "clean1.maintenance.lastRun." + task.rawValue) as? Date else {
            return L10n.tr("从未运行", "Never run here", "Ещё не запускалась")
        }
        return "Last run " + date.formatted(.relative(presentation: .named))
    }

    private func runChecked() {
        if checked.contains(where: { $0.severity == .advanced }) { confirmBatch = true } else { runBatch() }
    }

    /// Sequential, like Mac Sai's safe run, so the admin password is asked once.
    private func runBatch() {
        let tasks = MaintenanceTask.allCases.filter(checked.contains)
        Task {
            for task in tasks { await executeAndStore(task) }
        }
    }

    private func taskRow(_ task: MaintenanceTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: task.icon)
                .font(.system(size: 16))
                .foregroundStyle(.primary.opacity(0.75))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    if task.severity == .advanced {
                        Text(L10n.tr("高级", "ADVANCED", "РАСШИРЕННАЯ"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                if case .failed(let message) = taskStates[task] {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.8))
                        .lineLimit(2)
                } else {
                    Text(task.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer()

            statusView(for: task)

            Button {
                didTapRun(task)
            } label: {
                Image(systemName: task.severity == .advanced
                      ? "exclamationmark.triangle.fill"
                      : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(task.severity == .advanced
                                     ? Color.orange.opacity(0.85)
                                     : Color.primary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .disabled(isRunning(task))
            .help(task.severity == .advanced
                  ? L10n.tr("可能带来持续数小时的影响——将打开确认窗口", "Has multi-hour side effects — opens a confirmation", "Может влиять на систему несколько часов — откроется окно подтверждения")
                  : L10n.tr("运行此任务", "Run this task", "Запустить эту задачу"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func statusView(for task: MaintenanceTask) -> some View {
        switch taskStates[task] {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(.primary)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(message)
        case .idle, .none:
            EmptyView()
        }
    }

    private func isRunning(_ task: MaintenanceTask) -> Bool {
        if case .running = taskStates[task] { return true }
        return false
    }

    /// Routes through the severity check: safe tasks run immediately,
    /// advanced tasks pop the confirmation alert first.
    private func didTapRun(_ task: MaintenanceTask) {
        switch task.severity {
        case .safe:
            runTask(task)
        case .advanced:
            taskAwaitingConfirmation = task
        }
    }

    private func executeAndStore(_ task: MaintenanceTask) async {
        taskStates[task] = .running
        let result = await executor.execute(task)
        UserDefaults.standard.set(Date(), forKey: "clean1.maintenance.lastRun." + task.rawValue)
        if result.success {
            taskStates[task] = .completed(result.output)
        } else {
            taskStates[task] = .failed(result.error ?? L10n.tr("未知错误", "Unknown error", "Неизвестная ошибка"))
        }
    }

    private func runTask(_ task: MaintenanceTask) {
        Task { await executeAndStore(task) }
    }

    /// Bulk button runs ONLY safe tasks, and runs them SEQUENTIALLY. Several
    /// safe tasks need admin (purge, periodic). Sequential order keeps the
    /// UI status per-task; the in-process AppleScript runner then reuses the
    /// cached admin password so the user types it once (issues #82 / #143).
    private func runSafeTasks() {
        let safeTasks = MaintenanceTask.allCases.filter { $0.severity == .safe }
        Task {
            for task in safeTasks {
                await executeAndStore(task)
            }
        }
    }
}
