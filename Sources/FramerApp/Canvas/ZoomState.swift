import SwiftUI

@Observable
final class ZoomState {
    var scale: CGFloat = 1.0        // 1.0 = fit level
    var offset: CGSize = .zero      // pan translation in view coordinates
    var fitScale: CGFloat = 1.0     // image-pixels-to-view-points ratio at fit level

    // MARK: - Computed

    var displayPercent: Int {
        let value = scale * fitScale * 100
        guard value.isFinite else { return 100 }
        return Int(round(value))
    }

    var isAtFit: Bool {
        abs(scale - 1.0) < 0.005
    }

    // MARK: - Actions

    func zoomIn(anchor: CGPoint? = nil, viewSize: CGSize = .zero) {
        zoom(by: 1.25, anchor: anchor, viewSize: viewSize)
    }

    func zoomOut(anchor: CGPoint? = nil, viewSize: CGSize = .zero) {
        zoom(by: 0.8, anchor: anchor, viewSize: viewSize)
    }

    func fitToWindow() {
        scale = 1.0
        offset = .zero
    }

    func actualPixels() {
        guard fitScale > 0 else { return }
        scale = clampScale(1.0 / fitScale)
        offset = .zero
    }

    func toggleFitActual() {
        if isAtFit {
            actualPixels()
        } else {
            fitToWindow()
        }
    }

    // MARK: - Gesture Support

    /// Apply a magnification delta anchored at a point in the viewport.
    func applyMagnification(_ magnification: CGFloat, anchor: CGPoint, viewSize: CGSize) {
        let newScale = clampScale(scale * magnification)
        reanchor(from: scale, to: newScale, anchor: anchor, viewSize: viewSize)
        scale = newScale
    }

    /// Zoom by a factor, optionally anchored at a point.
    func zoom(by factor: CGFloat, anchor: CGPoint?, viewSize: CGSize) {
        let newScale = clampScale(scale * factor)
        if let anchor {
            reanchor(from: scale, to: newScale, anchor: anchor, viewSize: viewSize)
        }
        scale = newScale
        if isAtFit { offset = .zero }
    }

    /// Clamp the pan offset so the image center stays inside the viewport.
    func clampOffset(imageSize: CGSize, viewSize: CGSize) {
        guard scale > 1.0 else {
            offset = .zero
            return
        }
        let scaledW = imageSize.width * scale
        let scaledH = imageSize.height * scale
        let maxX = max(0, (scaledW - viewSize.width) / 2)
        let maxY = max(0, (scaledH - viewSize.height) / 2)
        offset.width = min(max(offset.width, -maxX), maxX)
        offset.height = min(max(offset.height, -maxY), maxY)
    }

    // MARK: - Fit Scale Calculation

    /// Update fitScale from the actual image dimensions and the viewport size.
    func updateFitScale(imageSize: CGSize, viewSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return }
        fitScale = min(viewSize.width / imageSize.width,
                       viewSize.height / imageSize.height)
    }

    // MARK: - Private

    private let maxZoom: CGFloat = 4.0  // 400% of actual pixels

    private func clampScale(_ s: CGFloat) -> CGFloat {
        guard fitScale > 0 else { return max(s, 1.0) }
        let maxRelative = max(1.0, maxZoom / fitScale)
        return min(max(s, 1.0), maxRelative)
    }

    private func reanchor(from oldScale: CGFloat, to newScale: CGFloat, anchor: CGPoint, viewSize: CGSize) {
        // Anchor point relative to the view center
        let centerX = anchor.x - viewSize.width / 2
        let centerY = anchor.y - viewSize.height / 2
        let ratio = newScale / oldScale
        offset.width = centerX - (centerX - offset.width) * ratio
        offset.height = centerY - (centerY - offset.height) * ratio
    }
}
