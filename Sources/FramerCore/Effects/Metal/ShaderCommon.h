// ShaderCommon.h
// Shared declarations and inline utility functions for Framer's GPU effects.
// Included from every effect .metal file. DOES NOT define any Metal entry
// points (vertex / fragment / kernel) — those live in dedicated .metal files
// so the Metal compiler doesn't see duplicate symbol definitions.
//
// Approach patterns (fullscreen triangle, branchless selects, precomputed reciprocals,
// IGN procedural blue noise for dither thresholds) studied from Grainrad
// (@almmaasoglu, https://grainrad.com — public bundle inspected 2026-04-13).
// This file is written fresh; no Grainrad code is copied.
//
// Primary references:
//   - Jimenez, "Next Generation Post Processing in Call of Duty Advanced Warfare",
//     SIGGRAPH 2014 — for the Interleaved Gradient Noise function.
//   - Bayer, "An Optimum Method for Two-Level Rendition of Continuous-Tone Pictures",
//     IEEE ICC 1973 — for the ordered-dither matrices.
//   - Rec. ITU-R BT.601-7 — for the luma coefficients.

#pragma once
#include <metal_stdlib>
using namespace metal;

// =============================================================================
// Shared vertex-shader output type (the fullscreen vertex entry lives in
// FullscreenVertex.metal — this struct is the interface every fragment uses).
// =============================================================================

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// =============================================================================
// Color / luma helpers
// =============================================================================

// Rec. 601 luma (same coefficients every Grainrad shader uses; matches how the
// CPU Dither Layer in Framer computes brightness, so GPU/CPU stay consistent).
inline float luminance(float3 c) {
    return dot(c, float3(0.299, 0.587, 0.114));
}

// Max-RGB brightness — Kim Asendorf's choice for pixel-sort "bright" / "dark" modes.
// Different from luminance; preserves saturated colors better for span detection.
inline float maxRGB(float3 c) {
    return max(max(c.r, c.g), c.b);
}

// `contrast = 1.0` is identity (matches GPUEffectCommonParameters' Swift
// default and the ColorGrade.metal convention). `brightness` shifts every
// channel additively. Output is saturated to 0..1 so adjustments don't
// produce out-of-gamut values for downstream luminance/colour math.
inline float3 applyBrightnessContrast(float3 color, float brightness, float contrast) {
    float3 result = color + brightness;
    result = (result - 0.5) * contrast + 0.5;
    return saturate(result);
}

inline float3 applyGamma(float3 color, float gamma) {
    if (gamma == 1.0) return color;
    return pow(max(color, float3(0.001)), float3(1.0 / max(gamma, 0.01)));
}

// Saturation 0..2 (1.0 = identity). Linear blend between Rec.601 luma and
// the original colour. Out-of-range values clip via saturate at the call site.
inline float3 applySaturation(float3 color, float saturation) {
    if (saturation == 1.0) return color;
    float gray = luminance(color);
    return mix(float3(gray), color, saturation);
}

// Hue rotation (degrees, 0 = identity). Rotates around the luma axis in YIQ-
// like chroma space. Cheap (a 2x2 trig rotation on the I/Q components).
//
// MSL `float3x3(col0, col1, col2)` builds a column-major matrix, so each
// column below holds the per-input-channel coefficients of one output
// component (e.g. col0 of rgbToYiq holds Y/I/Q coefficients for input R).
inline float3 applyHueRotation(float3 color, float degrees) {
    if (degrees == 0.0) return color;
    const float3x3 rgbToYiq = float3x3(
        float3(0.299,     0.595716,  0.211456),  // R-channel contributions
        float3(0.587,    -0.274453, -0.522591),  // G-channel contributions
        float3(0.114,    -0.321263,  0.311135)); // B-channel contributions
    const float3x3 yiqToRgb = float3x3(
        float3(1.0,       1.0,       1.0),       // Y-channel contributions
        float3(0.9563,   -0.2721,   -1.1070),    // I-channel contributions
        float3(0.6210,   -0.6474,    1.7046));   // Q-channel contributions
    float3 yiq = rgbToYiq * color;
    float radians = degrees * (M_PI_F / 180.0);
    float c = cos(radians);
    float s = sin(radians);
    float i =  yiq.y * c - yiq.z * s;
    float q =  yiq.y * s + yiq.z * c;
    return saturate(yiqToRgb * float3(yiq.x, i, q));
}


// =============================================================================
// Interleaved Gradient Noise (IGN) — procedural blue-noise approximation.
//
// Source: Jimenez, SIGGRAPH 2014.
//
// Used by the dither shader to approximate error diffusion. See notes/dithering.md
// for why error diffusion is replaced by blue-noise thresholds on GPU.
// =============================================================================

inline float ign(float2 pos) {
    return fract(52.9829189 * fract(dot(pos, float2(0.06711056, 0.00583715))));
}

// =============================================================================
// Bayer ordered-dither matrices (classic — Bayer 1973)
// =============================================================================

constant float bayer2x2[4] = {
    0.0 / 4.0, 2.0 / 4.0,
    3.0 / 4.0, 1.0 / 4.0,
};

constant float bayer4x4[16] = {
     0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
    12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
     3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
    15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0,
};

constant float bayer8x8[64] = {
     0.0/64, 32.0/64,  8.0/64, 40.0/64,  2.0/64, 34.0/64, 10.0/64, 42.0/64,
    48.0/64, 16.0/64, 56.0/64, 24.0/64, 50.0/64, 18.0/64, 58.0/64, 26.0/64,
    12.0/64, 44.0/64,  4.0/64, 36.0/64, 14.0/64, 46.0/64,  6.0/64, 38.0/64,
    60.0/64, 28.0/64, 52.0/64, 20.0/64, 62.0/64, 30.0/64, 54.0/64, 22.0/64,
     3.0/64, 35.0/64, 11.0/64, 43.0/64,  1.0/64, 33.0/64,  9.0/64, 41.0/64,
    51.0/64, 19.0/64, 59.0/64, 27.0/64, 49.0/64, 17.0/64, 57.0/64, 25.0/64,
    15.0/64, 47.0/64,  7.0/64, 39.0/64, 13.0/64, 45.0/64,  5.0/64, 37.0/64,
    63.0/64, 31.0/64, 55.0/64, 23.0/64, 61.0/64, 29.0/64, 53.0/64, 21.0/64,
};

inline float bayerThreshold2(uint2 pos) {
    return bayer2x2[(pos.y % 2) * 2 + (pos.x % 2)];
}

inline float bayerThreshold4(uint2 pos) {
    return bayer4x4[(pos.y % 4) * 4 + (pos.x % 4)];
}

inline float bayerThreshold8(uint2 pos) {
    return bayer8x8[(pos.y % 8) * 8 + (pos.x % 8)];
}

// =============================================================================
// Common uniform layouts (header-only — kept here so effect shaders stay small)
//
// Mirror these exactly in Swift when building the MTLBuffer. If layouts drift,
// uniforms read garbage and debugging is painful.
// =============================================================================

struct FramerCommonUniforms {
    float brightness;   // -1 .. 1  (0 = identity; UI shows -100..100, divides by 100)
    float contrast;     //  0 .. 2  (1 = identity)
    float saturation;   //  0 .. 2  (1 = identity)
    float hueRotation;  //  0 .. 360 (degrees; 0 = identity)
    float sharpness;    //  0 .. 1  (0 = identity; not consumed by helpers)
    float gamma;        //  0.1 .. 3 (1 = identity)
};

// Convenience: brightness/contrast → saturation → hue → gamma, in that order
// (matches the order applied by Framer's CPU FrameProcessor adjustment chain).
// Sharpness is intentionally NOT applied here — proper sharpening needs
// neighbour samples, which is up to each effect to do in its own kernel.
inline float3 applyCommonAdjustments(float3 color, FramerCommonUniforms common) {
    color = applyBrightnessContrast(color, common.brightness, common.contrast);
    color = applySaturation(color, common.saturation);
    color = applyHueRotation(color, common.hueRotation);
    color = applyGamma(color, common.gamma);
    return color;
}

struct FramerGeometryUniforms {
    float scale;
    float spacing;
    float outputWidth;  // pixels (0 = auto)
    float _pad;         // keep struct 16-byte aligned
};

// Hard cap on uploaded palette colours for `mode == 3`. Mirrors
// FramerColorUniformsLayout.setPalette in SharedUniforms.swift and the
// 16-colour cap DitherColorMode.palette already enforces.
#define FRAMER_MAX_PALETTE 16

struct FramerColorUniforms {
    uint  mode;               // 0 = source, 1 = fg/bg, 2 = monochrome, 3 = palette
    float backgroundIntensity;
    uint  paletteCount;       // 1..FRAMER_MAX_PALETTE — only read when mode == 3
    float _pad1;
    float4 foregroundRGBA;    // RGB in .xyz, unused in .w
    float4 backgroundRGBA;
    // Quantization targets for mode == 3. Zero-filled past paletteCount.
    float4 palette[FRAMER_MAX_PALETTE];
};

// Palette nearest-match (Euclidean distance in 0..1 RGB) — the same pick
// DitherGPURenderer's palettePick performs, shared so every bucket effect
// quantizes identically in palette colour mode.
inline float3 framerPalettePick(float3 c, constant FramerColorUniforms &color) {
    int n = clamp(int(color.paletteCount), 1, FRAMER_MAX_PALETTE);
    float bestDist = 1e30;
    float3 bestColor = color.palette[0].rgb;
    for (int i = 0; i < n; i++) {
        float3 p = color.palette[i].rgb;
        float3 d = c - p;
        float dist = dot(d, d);
        if (dist < bestDist) {
            bestDist = dist;
            bestColor = p;
        }
    }
    return bestColor;
}
