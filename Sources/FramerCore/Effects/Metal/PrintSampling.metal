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

    uint  variant;           // 0 threshold, 1 crosshatch
    float intensity;         // 0..1, blend with original
    float threshold;         // 0..1, base threshold
    uint  invert;            // 0 / 1

    uint  thresholdLevels;   // 2..32
    uint  thresholdDither;   // 0 / 1 — 2×2 checkerboard phase on threshold
    float hatchAngle;        // degrees (crosshatch)
    float hatchDensity;      // >=0.1 (crosshatch)

    float hatchLineWidth;    // 0..1 (crosshatch)
    uint  hatchLayers;       // 1..3 (crosshatch)
    float hatchRandomness;   // 0..1 (crosshatch)
    float _pad0;

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
    float3 src        = applyCommonAdjustments(source.sample(texSampler, selfUV).rgb, u.common);

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
// CROSSHATCH — pencil/etching line pattern at 1..3 configurable angles.
// Mirrors CPU's cell-local formulation (PrintSamplingRenderer.swift:141-151):
// rotate pixel coords by hatchAngle, test for line crossing at intervals of
// `baseStep = max(resolution) / (hatchDensity * 10)`, add a second axis-
// perpendicular layer, and a third diagonal layer when hatchLayers >= 3.
// Inked only where the pixel is dark (luminance < threshold).
// =============================================================================

static float4 crosshatchVariant(
    VertexOut                        in,
    texture2d<float>                 source,
    sampler                          texSampler,
    constant PrintSamplingUniforms&  u
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    int2   pixel      = clamp(int2(floor(in.uv * resolution)),
                              int2(0), int2(resolution) - 1);
    float2 selfUV     = (float2(pixel) + 0.5) / resolution;
    float3 src        = applyCommonAdjustments(source.sample(texSampler, selfUV).rgb, u.common);

    float lum  = luminance(src);
    bool  dark = lum < u.threshold;

    float angle   = u.hatchAngle * (M_PI_F / 180.0);
    float density = max(1.0, u.hatchDensity * 10.0);
    float baseStep = max(1.0, max(resolution.x, resolution.y) / density);
    float lineWidth = max(0.03, u.hatchLineWidth * 0.5);

    float cx = float(pixel.x);
    float cy = float(pixel.y);
    float rX = cx * cos(angle) - cy * sin(angle);
    float rY = cx * sin(angle) + cy * cos(angle);

    bool lineA = fabs(fract(rX / baseStep) - 0.5) < lineWidth;
    bool lineB = u.hatchLayers >= 2u && fabs(fract(rY / baseStep) - 0.5) < lineWidth;
    bool lineC = u.hatchLayers >= 3u && fabs(fract((rX + rY) / baseStep) - 0.5) < lineWidth;

    bool noiseToggle = (u.hatchRandomness > 0.0)
                    && sin(float((pixel.x + pixel.y) * 13)) > (1.0 - u.hatchRandomness);

    bool inked = dark && (lineA || lineB || lineC || noiseToggle);
    if (u.invert == 1u) { inked = !inked; }

    float3 painted = inked ? u.foregroundRGBA.rgb : u.backgroundRGBA.rgb;
    float3 final   = mix(src, painted, saturate(u.intensity));
    return float4(final, 1.0);
}

// =============================================================================
// Fragment entry — dispatch on variant.
// =============================================================================

fragment float4 printSamplingFragment(
    VertexOut                         in         [[stage_in]],
    texture2d<float>                  source     [[texture(0)]],
    sampler                           texSampler [[sampler(0)]],
    constant PrintSamplingUniforms&   uniforms   [[buffer(0)]]
) {
    switch (uniforms.variant) {
        case 0:  return thresholdVariant(in, source, texSampler, uniforms);
        case 1:  return crosshatchVariant(in, source, texSampler, uniforms);
        default: return source.sample(texSampler, in.uv);
    }
}
