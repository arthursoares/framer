import SwiftUI
import FramerCore

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

            // Video export progress (shown above queue when active)
            if appState.isExportingVideo {
                videoExportProgress
            }

            if appState.exportQueue.isEmpty && !appState.isExportingVideo {
                emptyState
            } else {
                jobList
            }
        }
    }

    private var videoExportProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Exporting Video...")
                    .font(.headline)
                Spacer()
                Text("\(Int(appState.videoExportProgress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: appState.videoExportProgress)
                .progressViewStyle(.linear)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                Text(jobItemLabel(job))
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

    private func jobItemLabel(_ job: ExportJob) -> String {
        let videoCount = job.items.filter { AppState.isVideoFile($0.url) }.count
        let photoCount = job.items.count - videoCount
        var parts: [String] = []
        if photoCount > 0 {
            parts.append("\(photoCount) photo\(photoCount == 1 ? "" : "s")")
        }
        if videoCount > 0 {
            parts.append("\(videoCount) video\(videoCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }

    private var hasCompleted: Bool {
        appState.exportQueue.contains { $0.status == .done }
    }

    private func clearCompleted() {
        appState.exportQueue.removeAll { $0.status == .done }
    }
}
