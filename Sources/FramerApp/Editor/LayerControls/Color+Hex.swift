import SwiftUI
import AppKit
import FramerCore

// MARK: - Color Helper

extension Color {
    var hexString: String? {
        // Resolve to a concrete RGB NSColor — handles catalog, pattern, and named colors
        let nsColor: NSColor
        if let resolved = NSColor(self).usingColorSpace(.sRGB) {
            nsColor = resolved
        } else if let resolved = NSColor(self).usingColorSpace(.deviceRGB) {
            nsColor = resolved
        } else {
            return nil
        }
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X",
                      max(0, min(255, r)),
                      max(0, min(255, g)),
                      max(0, min(255, b)))
    }
}
