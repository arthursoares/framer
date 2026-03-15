import SwiftUI
import AVFoundation

struct VideoTimelineView: View {
    @Bindable var viewModel: VideoPlayerViewModel

    /// Height of the thumbnail strip area.
    private let thumbnailHeight: CGFloat = 54
    /// Width of the draggable trim handles.
    private let handleWidth: CGFloat = 12
    /// Color used for the trim handles and border.
    private let trimColor = Color.yellow

    var body: some View {
        VStack(spacing: 4) {
            if viewModel.duration > 0 {
                timelineContent
                timecodeBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width

            ZStack(alignment: .leading) {
                // Thumbnail strip
                thumbnailStrip(width: totalWidth)

                // Dimmed region before trim start
                dimmedOverlay(
                    x: 0,
                    width: xPosition(for: viewModel.trimStart, in: totalWidth)
                )

                // Dimmed region after trim end
                let trimEndX = xPosition(for: viewModel.trimEnd, in: totalWidth)
                dimmedOverlay(
                    x: trimEndX,
                    width: totalWidth - trimEndX
                )

                // Trim border (top and bottom between handles)
                trimBorder(in: totalWidth)

                // Left trim handle
                trimHandle(edge: .leading, in: totalWidth)

                // Right trim handle
                trimHandle(edge: .trailing, in: totalWidth)

                // Playhead
                playhead(in: totalWidth)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture { location in
                let fraction = location.x / totalWidth
                let time = fraction * viewModel.duration
                viewModel.seekTo(time)
            }
        }
        .frame(height: thumbnailHeight)
    }

    // MARK: - Thumbnail Strip

    private func thumbnailStrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if viewModel.thumbnails.isEmpty {
                Color(nsColor: .darkGray)
            } else {
                ForEach(Array(viewModel.thumbnails.enumerated()), id: \.offset) { _, cgImage in
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: width / CGFloat(viewModel.thumbnails.count),
                            height: thumbnailHeight
                        )
                        .clipped()
                }
            }
        }
        .frame(width: width, height: thumbnailHeight)
    }

    // MARK: - Dimmed Overlay

    private func dimmedOverlay(x: CGFloat, width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .frame(width: max(0, width), height: thumbnailHeight)
            .offset(x: x)
            .allowsHitTesting(false)
    }

    // MARK: - Trim Border

    private func trimBorder(in totalWidth: CGFloat) -> some View {
        let startX = xPosition(for: viewModel.trimStart, in: totalWidth)
        let endX = xPosition(for: viewModel.trimEnd, in: totalWidth)
        let trimWidth = max(0, endX - startX)

        return RoundedRectangle(cornerRadius: 2)
            .strokeBorder(trimColor, lineWidth: 2)
            .frame(width: trimWidth, height: thumbnailHeight)
            .offset(x: startX)
            .allowsHitTesting(false)
    }

    // MARK: - Trim Handles

    private enum HandleEdge {
        case leading, trailing
    }

    private func trimHandle(edge: HandleEdge, in totalWidth: CGFloat) -> some View {
        let time = edge == .leading ? viewModel.trimStart : viewModel.trimEnd
        let x = xPosition(for: time, in: totalWidth)
        let offsetX = edge == .leading ? x - handleWidth : x

        return RoundedRectangle(cornerRadius: 2)
            .fill(trimColor)
            .frame(width: handleWidth, height: thumbnailHeight)
            .overlay {
                // Grip lines
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 4, height: 1)
                    }
                }
            }
            .offset(x: offsetX)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let fraction = (value.location.x + (edge == .leading ? offsetX : offsetX)) / totalWidth
                        let newTime = max(0, min(viewModel.duration, fraction * viewModel.duration))

                        switch edge {
                        case .leading:
                            viewModel.trimStart = min(newTime, viewModel.trimEnd - 0.1)
                        case .trailing:
                            viewModel.trimEnd = max(newTime, viewModel.trimStart + 0.1)
                        }

                        // Keep playhead within trim range
                        viewModel.seekTo(viewModel.playheadPosition)
                    }
            )
            .accessibilityLabel(edge == .leading ? "Trim start handle" : "Trim end handle")
    }

    // MARK: - Playhead

    private func playhead(in totalWidth: CGFloat) -> some View {
        let x = xPosition(for: viewModel.playheadPosition, in: totalWidth)

        return Rectangle()
            .fill(Color.white)
            .frame(width: 2, height: thumbnailHeight + 6)
            .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
            .offset(x: x - 1)
            .allowsHitTesting(false)
    }

    // MARK: - Timecode Bar

    private var timecodeBar: some View {
        HStack {
            Text(formatTimecode(viewModel.trimStart))
                .foregroundStyle(.secondary)

            Spacer()

            Text(formatTimecode(viewModel.playheadPosition))
                .foregroundStyle(.primary)

            Spacer()

            Text(formatTimecode(viewModel.trimEnd))
                .foregroundStyle(.secondary)
        }
        .font(.system(.caption2, design: .monospaced))
        .padding(.horizontal, 2)
    }

    // MARK: - Helpers

    private func xPosition(for time: TimeInterval, in totalWidth: CGFloat) -> CGFloat {
        guard viewModel.duration > 0 else { return 0 }
        return CGFloat(time / viewModel.duration) * totalWidth
    }

    private func formatTimecode(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, time)
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let millis = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
    }
}
