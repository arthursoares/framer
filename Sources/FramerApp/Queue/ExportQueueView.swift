import SwiftUI

struct ExportQueueView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Queue")
                    .font(.headline)
                Spacer()
                if !appState.exportQueue.isEmpty {
                    Button("Clear Completed") {
                        clearCompleted()
                    }
                    .disabled(!hasCompleted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if appState.exportQueue.isEmpty {
                emptyState
            } else {
                jobList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("No exports yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Select photos and export them from the settings panel.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jobList: some View {
        List {
            ForEach(appState.exportQueue) { job in
                jobRow(job)
            }
        }
        .listStyle(.inset)
    }

    private func jobRow(_ job: ExportJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusIcon(job.status)
                Text("\(job.items.count) photo\(job.items.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
                Text(statusLabel(job.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if job.status == .running {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                Text("\(job.completedCount) of \(job.items.count) completed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(job.outputDirectory.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                if job.status == .done {
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(job.outputDirectory)
                    } label: {
                        Label("Reveal", systemImage: "arrow.right.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusIcon(_ status: ExportJob.JobStatus) -> some View {
        switch status {
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func statusLabel(_ status: ExportJob.JobStatus) -> String {
        switch status {
        case .queued: "Queued"
        case .running: "Exporting..."
        case .done: "Done"
        case .failed(let msg): "Failed: \(msg)"
        }
    }

    private var hasCompleted: Bool {
        appState.exportQueue.contains { $0.status == .done }
    }

    private func clearCompleted() {
        appState.exportQueue.removeAll { $0.status == .done }
    }
}
