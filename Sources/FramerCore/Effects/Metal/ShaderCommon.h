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

inline float3 applyBrightnessContrast(float3 color, float brightness, float contrast) {
    float contrastFactor = (1.0 + contrast) / (1.0 - contrast * 0.99);
    float3 result = color + brightness;
    result = (result - 0.5) * contrastFactor + 0.5;
    return saturate(result);
}

inline float3 applyGamma(float3 color, float gamma) {
    if (gamma == 1.0) return color;
    return pow(max(color, float3(0.001)), float3(1.0 / max(gamma, 0.01)));
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
    float brightness;   // -1 .. 1  (normalized; Framer UI shows -100..100 and divides by 100)
    float contrast;     // -1 .. 1
    float saturation;   //  0 .. 2
    float hueRotation;  //  0 .. 360 (degrees)
    float sharpness;    //  0 .. 1
    float gamma;        //  0.1 .. 3
};

struct FramerGeometryUniforms {
    float scale;
    float spacing;
    float outputWidth;  // pixels (0 = auto)
    float _pad;         // keep struct 16-byte aligned
};

struct FramerColorUniforms {
    uint  mode;               // 0 = source, 1 = fg/bg, 2 = monochrome, 3 = palette
    float backgroundIntensity;
    float2 _pad;
    float4 foregroundRGBA;    // RGB in .xyz, unused in .w
    float4 backgroundRGBA;
};
