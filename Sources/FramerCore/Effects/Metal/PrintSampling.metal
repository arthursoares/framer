// PrintSampling.metal
// Fragment shader for the PrintSampling bucket (threshold / crosshatch /
// dithering). Mirrors PrintSamplingRenderer's CPU algorithms so that
// switching between GPU and CPU produces the same effect at matching
// parameters (within float-precision tolerance + per-variant caveats noted
// inline).
//
// CPU reference: Sources/FramerCore/Effects/Renderers/PrintSamplingRenderer.swift
// Uniform layout mirrors PrintSamplingGPURenderer.Uniforms in the Swift
// wrapper — keep field order and padding identical.

#include "ShaderCommon.h"

struct PrintSamplingUniforms {
    FramerCommonUniforms   common;
    FramerGeometryUniforms geometry;
    FramerColorUniforms    color;

    uint  variant;           // 0 = threshold (crosshatch / dithering added later)
    float intensity;         // 0..1, blend with original
    float threshold;         // 0..1, base threshold
    uint  invert;            // 0 / 1

    uint  thresholdLevels;   // 2..32
    uint  thresholdDither;   // 0 / 1 — 2×2 checkerboard phase on threshold
    float _pad0;
    float _pad1;

    float4 foregroundRGBA;   // ink colour
    float4 backgroundRGBA;   // paper colour
};

// =============================================================================
// THRESHOLD — N-level luminance quantization with optional 2x2 checkerboard
// dither phase. Per-pixel (no cell averaging) — the CPU renderer's cell
// averaging is a pre-pixelation step that users can also get via a separate
// downscale layer, and per-pixel keeps the GPU shader simple and fast.
// =============================================================================

static float4 thresholdVariant(
    VertexOut                         in,
    texture2d<float>                  source,
    sampler                           texSampler,
    constant PrintSamplingUniforms&   u
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    int2   pixel      = clamp(int2(floor(in.uv * resolution)),
                              int2(0), int2(resolution) - 1);
    float2 selfUV     = (float2(pixel) + 0.5) / resolution;
    float3 src        = source.sample(texSampler, selfUV).rgb;

    float lum = luminance(src);
    int   levels    = max(2, int(u.thresholdLevels));
    float quantized = round(lum * float(levels - 1)) / float(levels - 1);

    float dither = 0.0;
    if (u.thresholdDither == 1u) {
        bool even = ((pixel.x + pixel.y) & 1) == 0;
        dither = even ? -0.08 : 0.08;
    }

    bool inked = (quantized + dither) < u.threshold;
    if (u.invert == 1u) { inked = !inked; }

    float3 painted = inked ? u.foregroundRGBA.rgb : u.backgroundRGBA.rgb;
    float3 final   = mix(src, painted, saturate(u.intensity));
    return float4(final, 1.0);
}

// =============================================================================
// Fragment entry — dispatch on variant. Future variants (crosshatch, dithering)
// slot into additional cases here, each with a matching `static float4 *Variant`
// helper above.
// =============================================================================

fragment float4 printSamplingFragment(
    VertexOut                         in         [[stage_in]],
    texture2d<float>                  source     [[texture(0)]],
    sampler                           texSampler [[sampler(0)]],
    constant PrintSamplingUniforms&   uniforms   [[buffer(0)]]
) {
    switch (uniforms.variant) {
        case 0:  return thresholdVariant(in, source, texSampler, uniforms);
        default: return source.sample(texSampler, in.uv);
    }
}
