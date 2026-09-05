import SwiftUI
import FramerCore

// MARK: - Color hex helper

extension Color {
    var hexString: String? {
        // Resolve through UIKit — `Color.cgColor` is nil for dynamic /
        // catalog colors, which made the picker bindings' guard fail and
        // silently drop the selection. UIColor(_:) always resolves.
        guard let cgColor = UIColor(self).cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        ),
        let components = cgColor.components,
        components.count >= 3 else { return nil }
        let r = Int((max(0, min(1, components[0])) * 255).rounded())
        let g = Int((max(0, min(1, components[1])) * 255).rounded())
        let b = Int((max(0, min(1, components[2])) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
