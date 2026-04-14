import SwiftUI

struct SidebarStateStyle: Sendable, Equatable {
    enum Background: String, Sendable, Equatable {
        case clear
        case raisedSurface
        case accentedSurface
        case accentGlow
    }

    enum Border: String, Sendable, Equatable {
        case clear
        case standard
        case active
        case accent
    }

    enum Foreground: String, Sendable, Equatable {
        case primary
        case secondary
        case accent
    }

    let background: Background
    let border: Border
    let foreground: Foreground
    let opacity: Double

    static let `default` = SidebarStateStyle(background: .clear, border: .clear, foreground: .primary, opacity: 1)
    static let hover = SidebarStateStyle(background: .raisedSurface, border: .standard, foreground: .primary, opacity: 1)
    static let expanded = SidebarStateStyle(background: .raisedSurface, border: .standard, foreground: .primary, opacity: 1)
    static let selectedCurrent = SidebarStateStyle(background: .accentedSurface, border: .accent, foreground: .accent, opacity: 1)
    static let disabled = SidebarStateStyle(background: .clear, border: .clear, foreground: .secondary, opacity: 0.65)
    static let dragging = SidebarStateStyle(background: .raisedSurface, border: .active, foreground: .secondary, opacity: 0.72)
    static let dropTarget = SidebarStateStyle(background: .accentGlow, border: .accent, foreground: .primary, opacity: 1)
    static let focus = SidebarStateStyle(background: .raisedSurface, border: .active, foreground: .primary, opacity: 1)

    static let catalog: [SidebarState: SidebarStateStyle] = [
        .default: .default,
        .hover: .hover,
        .expanded: .expanded,
        .selectedCurrent: .selectedCurrent,
        .disabled: .disabled,
        .dragging: .dragging,
        .dropTarget: .dropTarget,
        .focus: .focus,
    ]

    static func style(for state: SidebarState) -> SidebarStateStyle {
        catalog[state] ?? .default
    }

    var backgroundColor: Color {
        switch background {
        case .clear:
            .clear
        case .raisedSurface:
            .surface2
        case .accentedSurface:
            .accentSubtle
        case .accentGlow:
            .accentGlow
        }
    }

    var borderColor: Color {
        switch border {
        case .clear:
            .clear
        case .standard:
            .borderDefault
        case .active:
            .borderActive
        case .accent:
            .accent
        }
    }

    var foregroundColor: Color {
        switch foreground {
        case .primary:
            .text0
        case .secondary:
            .text2
        case .accent:
            .accent
        }
    }
}
