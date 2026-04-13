// ColorGrade.metal
// Bucket fragment shader for Framer's three "look" presets that share the same
// per-pixel structure (no spatial-search / no neighbour-dependent algorithms,
// other than an optional small box blur):
//
//   variant 0 — Crimewave : neon channel-bias on saturated, contrast-pushed pixels
//   variant 1 — Narc      : contrast + crush + cool temperature shift
//   variant 2 — Shiba     : warm temperature + saturation lift
//
// CPU references:
//   Sources/FramerCore/Processing/ShaderRenderer.swift
//     - applyCrimewave  (lines ~40)
//     - applyNarc       (lines ~80)
//     - applyShiba      (lines ~110)
//   Sources/FramerCore/Processing/ShaderPrimitives.swift
//     - adjustContrastAndCrush
//     - adjustSaturation
//     - adjustTemperature
//     - applyChannelBias
//     - applyBoxBlur
//     - addDeterministicGrain
//
// All scalar constants from the CPU helpers live in 0..255 space; here we work
// in 0..1 float space, so additive amounts are divided by 255.0 to match.
//
// Grain uses the same integer-hash recipe as the CPU path so GPU and CPU grain
// patterns line up at identical pixel coordinates.
//
// No Grainrad code is referenced for these — they're original Framer looks.

#include "ShaderCommon.h"

// =============================================================================
// Uniforms
// =============================================================================

struct ColorGradeUniforms {
    FramerCommonUniforms common;        // unused, present so layout matches the
                                        // shared header pattern
    FramerGeometryUniforms geometry;
    FramerColorUniforms color;          // unused

    uint  variant;                      // 0 crimewave, 1 narc, 2 shiba
    float intensity;                    // 0..1, blend with original
    uint  blurRadius;                   // 0..3 — set 0 to skip blur
    float blurMixAmount;                // 0..1

    // crimewave
    float neon;
    float crimewaveContrast;            // already pre-multiplied by 1.3 in Swift

    // narc
    float narcContrast;                 // pre-multiplied by 1.4
    float narcCrush;                    // pre-clamped to 0..1
    float narcTemperature;              // pre-multiplied by 1.5

    // shiba
    float shibaWarmth;                  // pre-multiplied by 1.8
    float shibaSaturation;              // already premultiplied by 1.5

    // grain (every variant uses it)
    float grain;
    float _pad0;
    float _pad1;
};

// =============================================================================
// Shared per-pixel helpers (mirror ShaderPrimitives, in 0..1 float space)
// =============================================================================

inline float3 cgContrastCrush(float3 c, float contrast, float crush) {
    float3 result = (c - 0.5) * contrast + 0.5;
    if (crush > 0.0) {
        result = pow(max(result, float3(0.0)), float3(1.0 + crush * 1.8));
    }
    return saturate(result);
}

inline float3 cgSaturation(float3 c, float amount) {
    float luma = luminance(c);
    return saturate(float3(luma) + (c - float3(luma)) * amount);
}

inline float3 cgTemperature(float3 c, float amount) {
    // CPU shift = amount * 48 in 0..255 space → divide by 255 here.
    float shift = amount * (48.0 / 255.0);
    return saturate(float3(c.r + shift,
                           c.g + shift * 0.12,
                           c.b - shift * 0.85));
}

inline float3 cgChannelBias(float3 c, float3 bias255) {
    return saturate(c + bias255 / 255.0);
}

inline float3 cgGrain(float3 c, int2 px, float grainAmount) {
    if (grainAmount <= 0.0) { return c; }
    // Same hash recipe as ShaderPrimitives.addDeterministicGrain so GPU/CPU
    // produce identical noise patterns at matching coordinates.
    int seed = ((px.x * 29) + (px.y * 31) + ((px.x ^ px.y) * 17)) & 255;
    float centered = (float(seed) / 255.0) - 0.5;
    float delta = centered * (42.0 / 255.0) * grainAmount;
    return saturate(c + float3(delta));
}

// Branchless per-variant style application. Wrapped as its own function so the
// post-grade blur loop can re-apply the variant to each neighbour without
// duplicating the switch.
inline float3 applyVariantStyle(float3 c, constant ColorGradeUniforms& u);

// =============================================================================
// Per-variant pipelines
// =============================================================================

inline float3 crimewaveStyle(float3 c, constant ColorGradeUniforms& u) {
    c = cgContrastCrush(c, u.crimewaveContrast, 0.0);
    c = cgSaturation(c, 1.0 + u.neon * 1.6);
    c = cgChannelBias(c, float3(u.neon * 20.0, -u.neon * 15.0, u.neon * 40.0));
    return c;
}

inline float3 narcStyle(float3 c, constant ColorGradeUniforms& u) {
    c = cgContrastCrush(c, u.narcContrast, u.narcCrush);
    c = cgTemperature(c, u.narcTemperature);
    c = cgSaturation(c, 0.85);
    return c;
}

inline float3 shibaStyle(float3 c, constant ColorGradeUniforms& u) {
    c = cgTemperature(c, u.shibaWarmth);
    c = cgSaturation(c, 1.0 + u.shibaSaturation);
    return c;
}

inline float3 applyVariantStyle(float3 c, constant ColorGradeUniforms& u) {
    switch (u.variant) {
        case 1:  return narcStyle(c, u);
        case 2:  return shibaStyle(c, u);
        default: return crimewaveStyle(c, u);
    }
}

// =============================================================================
// Fragment entry — dispatch on variant
// =============================================================================

fragment float4 colorGradeFragment(
    VertexOut                    in           [[stage_in]],
    texture2d<float>             source       [[texture(0)]],
    sampler                      texSampler   [[sampler(0)]],
    constant ColorGradeUniforms& uniforms     [[buffer(0)]]
) {
    float2 resolution = float2(source.get_width(), source.get_height());

    // Pin to the integer pixel grid. Needed for the box-blur kernel-clipping
    // logic below to count "real" neighbours only.
    int2   pixel    = clamp(int2(floor(in.uv * resolution)), int2(0), int2(resolution) - 1);
    float2 selfUV   = (float2(pixel) + 0.5) / resolution;
    float3 src      = source.sample(texSampler, selfUV).rgb;

    // Grade the centre pixel FIRST. CPU's applyCrimewave/Narc/Shiba all apply
    // contrast/saturation/temperature/channel-bias in-place on the pixel
    // buffer BEFORE calling applyBoxBlur (ShaderRenderer.swift:102-120 for
    // Crimewave; parallel structure for Narc and Shiba). The previous version
    // blurred first and graded second — algebraically different whenever
    // grading is non-linear (contrast, saturation, channel bias, temperature
    // all are). Parity tests hid the bug by pinning softness = 0.
    float3 styled = applyVariantStyle(src, uniforms);

    // Blur AFTER grading. Re-apply the same variant style to each neighbour's
    // raw source value, average the styled neighbours, mix with centre
    // styled. Equivalent to "grade the entire image, then box-blur" because
    // a box blur is a spatial mean over the styled intermediate.
    //
    // Border handling matches CPU's ShaderPrimitives.applyBoxBlur exactly:
    // when the kernel hits the image edge, CPU clips its inner loop bounds
    // to in-bounds pixels and divides by the actual sample count, NOT by
    // the full kernel area (Sources/FramerCore/Processing/ShaderPrimitives
    // .swift:79-87). Earlier this shader trusted clamp-to-edge sampling
    // which repeated the border texel — codex review caught this as a
    // remaining systematic delta along the outer `radius`-pixel band.
    int radius = clamp(int(uniforms.blurRadius), 0, 3);
    if (radius > 0 && uniforms.blurMixAmount > 0.0) {
        float3 sum = float3(0.0);
        float  count = 0.0;
        int    maxX = int(resolution.x) - 1;
        int    maxY = int(resolution.y) - 1;
        for (int dy = -3; dy <= 3; dy++) {
            if (dy < -radius || dy > radius) { continue; }
            int ny = pixel.y + dy;
            if (ny < 0 || ny > maxY) { continue; }
            for (int dx = -3; dx <= 3; dx++) {
                if (dx < -radius || dx > radius) { continue; }
                int nx = pixel.x + dx;
                if (nx < 0 || nx > maxX) { continue; }
                float2 nUV = (float2(float(nx), float(ny)) + 0.5) / resolution;
                float3 nSrc = source.sample(texSampler, nUV).rgb;
                sum += applyVariantStyle(nSrc, uniforms);
                count += 1.0;
            }
        }
        float3 blurredStyled = sum / max(count, 1.0);
        styled = mix(styled, blurredStyled, saturate(uniforms.blurMixAmount));
    }

    styled = cgGrain(styled, pixel, uniforms.grain);

    // Final blend with the original source by intensity (matches
    // ShaderRenderer.mixStylizedContext).
    float3 final = mix(src, styled, saturate(uniforms.intensity));
    return float4(final, 1.0);
}
