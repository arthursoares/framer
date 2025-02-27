import SwiftUI

enum BorderStyle: String, CaseIterable, Identifiable {
    case solid
    case instagram
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .solid: return "Solid"
        case .instagram: return "Instagram (4:5)"
        }
    }
}

class FramerSettings: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var borderStyle: BorderStyle = .solid
    @Published var borderThickness: CGFloat = 20
    @Published var borderColor: Color = .black
    @Published var padding: CGFloat = 150
    @Published var caption: String = ""
    @Published var useExifDate: Bool = true
    @Published var fontSize: CGFloat = 20
    @Published var fontColor: Color = .black
    @Published var fontName: String = "Courier-Bold"
    @Published var instagramMaxSize: CGFloat = 900
    
    // Helper to convert SwiftUI Color to UIColor
    func uiBorderColor() -> UIColor {
        UIColor(borderColor)
    }
    
    func uiFontColor() -> UIColor {
        UIColor(fontColor)
    }
    
    // Helper to convert thickness to percentage or pixels for display
    func thicknessDisplayValue() -> String {
        return "\(Int(borderThickness))"
    }
    
    // Reset to defaults based on style
    func resetToDefaults() {
        switch borderStyle {
        case .instagram:
            borderThickness = 5
            padding = 0
            fontSize = 20
            instagramMaxSize = 1000
        case .solid:
            borderThickness = 20
            padding = 150
            fontSize = 50
            instagramMaxSize = 900
        }
    }
}