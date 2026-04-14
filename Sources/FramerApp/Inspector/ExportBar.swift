import SwiftUI
import FramerCore

private enum ExportBarLayout {
    static let buttonSpacing = 4.0
    static let buttonVerticalPadding = 7.0
    static let queuePopoverWidth = 260.0
}

struct ExportBar: View {
    @Environment(AppState.self) var appState
    @AppStorage("lastExportDirectory") private var lastExportDirectory: String = ""
    @State private var showingExportSheet = false
    @State private var showingQueuePopover = false
    @State private var pendingExportItems: [PhotoItem] = []
    @State private var selectedPresetIDs: Set<UUID> = []
    @State private var includeCurrentSettings = true

    private let metrics = SidebarMetrics()

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.borderDefault).frame(height: 1)
            HStack(spacing: metrics.expandedBodyInset) {
                actionButton(
                    title: "Selected",
                    systemImage: "square.and.arrow.up",
                    count: appState.selectedItems.isEmpty ? nil : appState.selectedItems.count,
                    stateStyle: .hover,
                    countBackground: Color.surface3,
                    countForeground: Color.text1,
                    action: {
                        promptAndExport(appState.library.filter { appState.selectedItems.contains($0.id) })
                    }
                )
                .disabled(appState.selectedItems.isEmpty)

                Spacer()

                if !appState.exportQueue.isEmpty {
                    Button {
                        showingQueuePopover.toggle()
                    } label: {
                        queueIndicator
                            .padding(.horizontal, metrics.outerInset)
                            .padding(.vertical, ExportBarLayout.buttonVerticalPadding)
                            .background(SidebarStateStyle.hover.backgroundColor, in: RoundedRectangle(cornerRadius: CornerRadius.md))
                            .overlay {
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .stroke(SidebarStateStyle.hover.borderColor, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingQueuePopover) {
                        ExportQueuePopover()
                    }
                }

                actionButton(
                    title: "All",
                    systemImage: "square.and.arrow.up.on.square",
                    count: appState.library.isEmpty ? nil : appState.library.count,
                    stateStyle: .selectedCurrent,
                    countBackground: Color.accentGlow,
                    countForeground: Color.accent,
                    action: {
                        promptAndExport(appState.library)
                    }
                )
                .disabled(appState.library.isEmpty)
            }
            .padding(.horizontal, metrics.outerInset)
            .padding(.vertical, metrics.expandedBodyInset)
            .background(Color.surface1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerExportSelected)) { _ in
            promptAndExport(appState.library.filter { appState.selectedItems.contains($0.id) })
        }
        .onReceive(NotificationCenter.default.publisher(for: .framerExportAll)) { _ in
            promptAndExport(appState.library)
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
    }

    @ViewBuilder
    private var queueIndicator: some View {
        let running = appState.exportQueue.filter { $0.status == .running }
        let failed = appState.exportQueue.filter { if case .failed = $0.status { return true }; return false }
        let cancelled = appState.exportQueue.filter { $0.status == .cancelled }

        HStack(spacing: ExportBarLayout.buttonSpacing) {
            if let job = running.first {
                ProgressView(value: job.progress)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .tint(Color.accent)
                Text("\(job.completedCount)/\(job.items.count)")
                    .font(AppFont.photoCount)
                    .foregroundStyle(Color.text2)
            } else if !failed.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.error)
            } else if !cancelled.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.text3)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.success)
            }
        }
    }

    private func actionButton(
        title: LocalizedStringKey,
        systemImage: String,
        count: Int?,
        stateStyle: SidebarStateStyle,
        countBackground: Color,
        countForeground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: ExportBarLayout.buttonSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(title)
                    .font(AppFont.buttonText)

                if let count {
                    Text("\(count)")
                        .font(AppFont.badgeSummary)
                        .foregroundStyle(countForeground)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(countBackground, in: Capsule())
                }
            }
            .foregroundStyle(stateStyle.foregroundColor)
            .padding(.horizontal, metrics.outerInset)
            .padding(.vertical, ExportBarLayout.buttonVerticalPadding)
            .background(stateStyle.backgroundColor, in: RoundedRectangle(cornerRadius: CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(stateStyle.borderColor, lineWidth: 1)
            }
            .opacity(stateStyle.opacity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export Logic

    private func promptAndExport(_ items: [PhotoItem]) {
        guard !items.isEmpty else { return }
        if appState.presets.isEmpty {
            directExport(items)
        } else {
            pendingExportItems = items
            showingExportSheet = true
        }
    }

    private func directExport(_ items: [PhotoItem]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose output folder"
        if !lastExportDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: lastExportDirectory)
        }
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        lastExportDirectory = dir.path
        appState.exportItems(items, to: dir)
    }

    private func performExport() {
        showingExportSheet = false
        let items = pendingExportItems
        guard !items.isEmpty else { return }
        guard includeCurrentSettings || !selectedPresetIDs.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose output folder"
        if !lastExportDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: lastExportDirectory)
        }
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        lastExportDirectory = dir.path

        if includeCurrentSettings {
            appState.exportItems(items, to: dir)
        }

        let presetConfigs = appState.presets
            .filter { selectedPresetIDs.contains($0.id) }
            .map { (name: $0.name, config: $0.config) }

        if !presetConfigs.isEmpty {
            appState.exportItems(items, to: dir, withPresets: presetConfigs)
        }

        selectedPresetIDs.removeAll()
    }

    private var exportSheet: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("Export \(pendingExportItems.count) photo\(pendingExportItems.count == 1 ? "" : "s")")
                    .font(AppFont.body(14, weight: .semibold))
                    .foregroundStyle(Color.text0)

                Toggle(isOn: $includeCurrentSettings) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Color.text2)
                        Text("Current Settings")
                            .font(AppFont.body(12))
                        if let name = appState.activePresetName {
                            Text("(\(name))")
                                .font(AppFont.body(11))
                                .foregroundStyle(Color.text2)
                        }
                    }
                }

                if !appState.presets.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Also export with presets:")
                            .font(AppFont.body(11))
                            .foregroundStyle(Color.text2)

                        ForEach(appState.presets) { preset in
                            Toggle(isOn: presetToggleBinding(preset.id)) {
                                Text(preset.name)
                                    .font(AppFont.body(12))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)

            Divider()

            HStack {
                Button("Cancel") {
                    showingExportSheet = false
                    selectedPresetIDs.removeAll()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                let totalExports = (includeCurrentSettings ? 1 : 0) + selectedPresetIDs.count
                Button("Export\(totalExports > 1 ? " (\(totalExports) presets)" : "")") {
                    performExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(totalExports == 0)
            }
            .padding(20)
        }
        .frame(width: 340)
    }

    private func presetToggleBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedPresetIDs.contains(id) },
            set: { enabled in
                if enabled { selectedPresetIDs.insert(id) }
                else { selectedPresetIDs.remove(id) }
            }
        )
    }
}

// MARK: - Export Queue Popover

struct ExportQueuePopover: View {
    @Environment(AppState.self) var appState

    private let metrics = SidebarMetrics()

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
            HStack {
                Text("EXPORT QUEUE")
                    .font(AppFont.sectionHeader)
                    .tracking(1.5)
                    .foregroundStyle(Color.text3)
                Spacer()
                if appState.exportQueue.contains(where: { $0.status == .done || $0.status == .cancelled }) {
                    Button("Clear") {
                        appState.exportQueue.removeAll { $0.status == .done || $0.status == .cancelled }
                    }
                    .font(AppFont.body(10))
                    .foregroundStyle(Color.text2)
                    .buttonStyle(.plain)
                }
            }

            ForEach(appState.exportQueue) { job in
                jobRow(job)
            }
        }
        .padding(metrics.outerInset)
        .frame(width: ExportBarLayout.queuePopoverWidth)
        .background(Color.surface1)
    }

    private func jobRow(_ job: ExportJob) -> some View {
        let rowStyle = jobRowStyle(job)

        return HStack(spacing: Spacing.sm) {
            statusIcon(job.status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(job.items.count) photo\(job.items.count == 1 ? "" : "s")")
                        .font(AppFont.body(11))
                        .foregroundStyle(Color.text1)
                    if let label = job.label {
                        Text(label)
                            .font(AppFont.mono(9))
                            .foregroundStyle(Color.text3)
                    }
                }
                .lineLimit(1)
                if job.status == .running {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                        .tint(Color.accent)
                        .frame(height: 3)
                }
            }
            Spacer()
            if job.status == .done {
                Button {
                    NSWorkspace.shared.open(job.outputDirectory)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.text2)
                }
                .buttonStyle(.plain)
            }
            if job.status == .running {
                Button {
                    appState.cancelJob(job)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.text2)
                }
                .buttonStyle(.plain)
            }
            if case .failed = job.status {
                Button {
                    appState.retryJob(job)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.text2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, metrics.expandedBodyInset)
        .padding(.vertical, metrics.expandedBodyInset)
        .background(rowStyle.backgroundColor, in: RoundedRectangle(cornerRadius: CornerRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(rowStyle.borderColor, lineWidth: 1)
        }
    }

    private func jobRowStyle(_ job: ExportJob) -> SidebarStateStyle {
        switch job.status {
        case .running:
            return .focus
        case .queued, .done, .cancelled, .failed:
            return .hover
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: ExportJob.JobStatus) -> some View {
        switch status {
        case .queued:
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundStyle(Color.text3)
        case .running:
            ProgressView()
                .controlSize(.mini)
                .tint(Color.accent)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.success)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.text3)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.error)
        }
    }
}
