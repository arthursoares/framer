import SwiftUI

// MARK: - Color Tokens

extension Color {
    // Surface hierarchy
    static let surface0 = Color(red: 14/255, green: 14/255, blue: 16/255)   // #0E0E10
    static let surface1 = Color(red: 20/255, green: 20/255, blue: 22/255)   // #141416
    static let surface2 = Color(red: 26/255, green: 26/255, blue: 30/255)   // #1A1A1E
    static let surface3 = Color(red: 34/255, green: 34/255, blue: 38/255)   // #222226
    static let surface4 = Color(red: 42/255, green: 42/255, blue: 47/255)   // #2A2A2F

    // Text hierarchy
    static let text0 = Color(red: 240/255, green: 237/255, blue: 232/255)   // #F0EDE8
    static let text1 = Color(red: 184/255, green: 180/255, blue: 173/255)   // #B8B4AD
    static let text2 = Color(red: 125/255, green: 122/255, blue: 116/255)   // #7D7A74
    static let text3 = Color(red: 78/255, green: 76/255, blue: 72/255)      // #4E4C48

    // Accent (warm amber)
    static let accent = Color(red: 212/255, green: 149/255, blue: 106/255)  // #D4956A
    static let accentDim = Color(red: 160/255, green: 104/255, blue: 64/255) // #A06840
    static let accentGlow = Color(red: 212/255, green: 149/255, blue: 106/255).opacity(0.08)
    static let accentSubtle = Color(red: 212/255, green: 149/255, blue: 106/255).opacity(0.15)

    // Functional
    static let success = Color(red: 94/255, green: 159/255, blue: 109/255)  // #5E9F6D
    static let error = Color(red: 199/255, green: 93/255, blue: 93/255)     // #C75D5D

    // Border
    static let borderDefault = Color.white.opacity(0.06)
    static let borderActive = Color.white.opacity(0.12)
}

// MARK: - Typography

enum AppFont {
    /// Atkinson Hyperlegible for UI text
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Atkinson Hyperlegible Next", size: size).weight(weight)
    }

    /// Source Code Pro for data values
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Source Code Pro", size: size).weight(weight)
    }

    // Presets for common uses
    static let sectionHeader = body(10, weight: .semibold)
    static let layerName = body(12, weight: .medium)
    static let controlLabel = body(11)
    static let buttonText = body(11, weight: .semibold)
    static let toggleLabel = body(10, weight: .semibold)

    static let exifChip = mono(10)
    static let hexValue = mono(10)
    static let templateToken = mono(9)
    static let badgeSummary = mono(9)
    static let numericInput = mono(10)
    static let photoCount = mono(10)
    static let brandTitle = mono(12)
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 16
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 10
}
