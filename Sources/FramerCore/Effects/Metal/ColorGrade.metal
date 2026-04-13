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

// Small box blur, branchless on radius via a fixed max loop bound. radius is
// clamped to 0..3 (matches ShaderPrimitives.applyBoxBlur's hard cap), so the
// inner loop runs at most 7×7 = 49 samples — fine for fragment rate.
inline float3 cgBoxBlur(texture2d<float> source,
                        sampler          sampleState,
                        float2           uv,
                        float2           texelSize,
                        int              radius,
                        float            mixAmount,
                        float3           original) {
    if (radius <= 0 || mixAmount <= 0.0) { return original; }
    int r = clamp(radius, 1, 3);

    float3 sum = float3(0.0);
    float  count = 0.0;
    for (int dy = -3; dy <= 3; dy++) {
        if (dy < -r || dy > r) { continue; }
        for (int dx = -3; dx <= 3; dx++) {
            if (dx < -r || dx > r) { continue; }
            float2 sampleUV = uv + float2(float(dx), float(dy)) * texelSize;
            sum += source.sample(sampleState, sampleUV).rgb;
            count += 1.0;
        }
    }
    float3 blurred = sum / max(count, 1.0);
    return mix(original, blurred, saturate(mixAmount));
}

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
    float2 texel      = 1.0 / resolution;

    // Optionally blur first so subsequent grading reads a softened sample.
    // ShaderRenderer's CPU path applies blur AFTER the grading; doing it here
    // pre-blurs but the visual difference is small and saves an extra pass.
    float3 src = source.sample(texSampler, in.uv).rgb;
    float3 blurred = cgBoxBlur(source, texSampler, in.uv, texel,
                               int(uniforms.blurRadius), uniforms.blurMixAmount, src);

    float3 styled;
    switch (uniforms.variant) {
        case 1:  styled = narcStyle(blurred, uniforms); break;
        case 2:  styled = shibaStyle(blurred, uniforms); break;
        default: styled = crimewaveStyle(blurred, uniforms); break;
    }

    int2 px = int2(in.uv * resolution);
    styled  = cgGrain(styled, px, uniforms.grain);

    // Final blend with the original source by intensity (matches
    // ShaderRenderer.mixStylizedContext).
    float3 final = mix(src, styled, saturate(uniforms.intensity));
    return float4(final, 1.0);
}
