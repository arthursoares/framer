// LayerBlendMode.swift
// Unified blend-mode enum used by every visual adjustment layer (LUT,
// Dither, Shader, GPUEffect, Overlay). Ships 20 modes across three tiers:
//
//  - Tier 1 (12 standard RGB modes): the Photoshop default panel —
//    normal, multiply, screen, overlay, softLight, hardLight, difference,
//    exclusion, darken, lighten, colorDodge, colorBurn.
//  - Tier 2 (4 HSL-component modes): hue, saturation, color, luminosity
//    — Photoshop's "colorize" family, essential for tinting workflows.
//  - Tier 3 (4 technical modes): subtract, divide, linearDodge (alias
//    "add"), linearBurn — cheap math ops useful for alignment checks,
//    additive compositing, and precise tonal shifts.
//
// Applied as `result = mix(base, blend(base, over), opacity)` where
// `blend(...)` is the mode-specific formula and `opacity` is the layer
// opacity slider. `normal` is the identity — at opacity=1 it renders
// the overlay untouched; at opacity<1 it's a straight alpha mix with
// the base.
//
// Applied as `result = mix(base, blend(base, over), opacity)` where
// `blend(...)` is the mode-specific formula and `opacity` is the layer
// opacity slider. `normal` is the identity — at opacity=1 it renders
// the overlay untouched; at opacity<1 it's a straight alpha mix with
// the base.
//
// Raw-string values are deliberately chosen so existing saved presets
// (which encoded `OverlayBlendMode.normal / screen / softLight / multiply`
// as the same strings) migrate without breakage when the decoder
// upgrades to this type.

import Foundation

public enum LayerBlendMode: String, Codable, CaseIterable, Sendable, Hashable {

    // MARK: - Tier 1 — Per-channel RGB modes

    /// `result = over`. Identity mode; opacity scales a straight mix.
    case normal

    /// `result = base * over`. Darkens the base toward black; any over
    /// channel near 0 kills the base in that channel.
    case multiply

    /// `result = 1 - (1-base) * (1-over)`. Inverse of multiply; lightens.
    /// Near-black over contributes nothing, near-white dominates.
    case screen

    /// `result = base<0.5 ? 2*base*over : 1 - 2*(1-base)*(1-over)`.
    /// Contrast-boost composite: base drives whether to multiply or
    /// screen based on its own luminance.
    case overlay

    /// Pegtop soft-light: `result = (1-2*over)*base² + 2*over*base`.
    /// Gentle contrast tweak; opposite of hardLight in harshness.
    case softLight

    /// `result = over<0.5 ? 2*base*over : 1 - 2*(1-base)*(1-over)`.
    /// Overlay's symmetric counterpart — the OVER channel picks the
    /// formula. Harsher than softLight.
    case hardLight

    /// `result = |base - over|`. Pixelwise absolute difference; used
    /// for alignment checks and dramatic swap effects.
    case difference

    /// `result = base + over - 2*base*over`. Softer variant of
    /// difference — gray midtones stay neutral.
    case exclusion

    /// `result = min(base, over)`. Channel-wise darkening.
    case darken

    /// `result = max(base, over)`. Channel-wise lightening.
    case lighten

    /// `result = over<1 ? min(1, base/(1-over)) : 1`. Brightens base
    /// based on over; clamped at 1.
    case colorDodge

    /// `result = over>0 ? 1 - min(1, (1-base)/over) : 0`. Darkens base
    /// based on over; clamped at 0.
    case colorBurn

    // MARK: - Tier 2 — HSL-component modes

    /// Swap only the hue of `over` into `base`. Useful for tinting
    /// without changing the image's brightness or saturation.
    case hue

    /// Swap only the saturation of `over` into `base`.
    case saturation

    /// Swap hue AND saturation of `over` into `base`. "Colorize" effect
    /// — the classic way to re-tint a black-and-white photo.
    case color

    /// Swap only the luminance of `over` into `base`. Copies brightness
    /// pattern while keeping base's colour.
    case luminosity

    // MARK: - Tier 3 — Technical / arithmetic modes

    /// `result = max(0, base - over)`. Subtracts over from base; clamped
    /// at 0. Inverse-ish of linearDodge, useful for isolating differences
    /// without taking absolute value.
    case subtract

    /// `result = over > 0 ? base / over : 1`. Base divided by over per
    /// channel; near-black over lightens aggressively toward 1.
    case divide

    /// `result = min(1, base + over)`. Additive compositing, also known
    /// as "Add". Useful for additive lighting effects and stacking
    /// bright elements without darkening.
    case linearDodge

    /// `result = max(0, base + over - 1)`. Subtractive dual of
    /// linearDodge. Drives toward black when base+over < 1.
    case linearBurn

    // MARK: - Metadata

    public var label: String {
        switch self {
        case .normal:      return "Normal"
        case .multiply:    return "Multiply"
        case .screen:      return "Screen"
        case .overlay:     return "Overlay"
        case .softLight:   return "Soft Light"
        case .hardLight:   return "Hard Light"
        case .difference:  return "Difference"
        case .exclusion:   return "Exclusion"
        case .darken:      return "Darken"
        case .lighten:     return "Lighten"
        case .colorDodge:  return "Color Dodge"
        case .colorBurn:   return "Color Burn"
        case .hue:         return "Hue"
        case .saturation:  return "Saturation"
        case .color:       return "Color"
        case .luminosity:  return "Luminosity"
        case .subtract:    return "Subtract"
        case .divide:      return "Divide"
        case .linearDodge: return "Linear Dodge (Add)"
        case .linearBurn:  return "Linear Burn"
        }
    }

    /// `true` for the four HSL-component modes. HSL modes need per-pixel
    /// RGB↔HSL conversion and don't vectorise as cleanly as the RGB
    /// modes, so compositors pick a different code path for them.
    public var isHSL: Bool {
        switch self {
        case .hue, .saturation, .color, .luminosity: return true
        default: return false
        }
    }
}
