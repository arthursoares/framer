import UIKit

struct FontManager {
    // Get all available fonts
    static func getAvailableFonts() -> [String] {
        // Focus on fonts that work well for framing captions
        let fontFamilies = [
            "Courier", 
            "American Typewriter",
            "Menlo",
            "Futura",
            "Avenir Next",
            "Gill Sans",
            "Helvetica Neue",
            "SF Mono",
            "Times New Roman",
            "Copperplate"
        ]
        
        var availableFonts: [String] = []
        
        for family in fontFamilies {
            let fontNames = UIFont.fontNames(forFamilyName: family)
            availableFonts.append(contentsOf: fontNames)
        }
        
        // Add system fonts
        availableFonts.append(UIFont.systemFont(ofSize: 17).fontName)
        availableFonts.append(UIFont.boldSystemFont(ofSize: 17).fontName)
        availableFonts.append(UIFont.monospacedSystemFont(ofSize: 17, weight: .regular).fontName)
        availableFonts.append(UIFont.monospacedSystemFont(ofSize: 17, weight: .bold).fontName)
        
        return availableFonts.sorted()
    }
    
    // Get font display name
    static func getDisplayName(for fontName: String) -> String {
        let parts = fontName.split(separator: "-")
        if parts.count > 1 {
            return "\(parts[0]) \(parts[1])"
        }
        return fontName
    }
}