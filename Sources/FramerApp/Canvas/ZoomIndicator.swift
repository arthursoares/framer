import SwiftUI

struct ZoomIndicator: View {
    let zoomState: ZoomState
    let onFit: () -> Void
    let onToggle: () -> Void

    @State private var isVisible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Text("\(zoomState.displayPercent)%")
                    .font(AppFont.mono(12))
                    .foregroundStyle(Color.text1)
            }
            .buttonStyle(.plain)

            if !zoomState.isAtFit {
                Button(action: onFit) {
                    Text("Fit")
                        .font(AppFont.mono(11))
                        .foregroundStyle(Color.text2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.surface3, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.borderDefault, lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isVisible)
        .onChange(of: zoomState.scale) { _, _ in
            scheduleVisibility()
        }
        .onChange(of: zoomState.isAtFit) { _, atFit in
            if atFit {
                scheduleFade()
            } else {
                isVisible = true
                hideTask?.cancel()
            }
        }
        .onAppear {
            if !zoomState.isAtFit {
                isVisible = true
            }
        }
    }

    private func scheduleVisibility() {
        isVisible = true
        if zoomState.isAtFit {
            scheduleFade()
        } else {
            hideTask?.cancel()
        }
    }

    private func scheduleFade() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            isVisible = false
        }
    }
}
