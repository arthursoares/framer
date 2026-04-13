// EdgeField.metal
// Fragment shader for the EdgeField bucket (edgeDetection / contour /
// waveLines / voronoi / noiseField). Mirrors EdgeFieldRenderer's CPU per-
// pixel algorithms so GPU and CPU produce visually equivalent output at the
// same parameters.
//
// CPU reference: Sources/FramerCore/Effects/Renderers/EdgeFieldRenderer.swift
// Uniform layout mirrors EdgeFieldGPURenderer.Uniforms in the Swift wrapper
// exactly — keep field order and padding identical, or uniforms read garbage.

#include "ShaderCommon.h"

// =============================================================================
// Uniforms
// =============================================================================

struct EdgeFieldUniforms {
    FramerCommonUniforms   common;
    FramerGeometryUniforms geometry;
    FramerColorUniforms    color;

    uint  variant;             // 0 edgeDetection, future: 1 contour, 2 waveLines, 3 voronoi, 4 noiseField
    float intensity;           // 0..1, blend with original
    float lineStrength;        // 0..1
    float thickness;           // 0..1

    float edgeThreshold;       // 0..1, subtracts from edge before shaping
    uint  edgeAlgorithm;       // 0 sobel, 1 laplacian (edge multiplier differs)
    uint  invert;              // 0 / 1
    float _pad0;

    float4 edgeColor;          // colour for ink pixels (rgba, a unused)
};

// =============================================================================
// EDGE DETECTION — per-pixel Sobel-like gradient magnitude, thresholded and
// shaped by lineStrength/thickness. Matches CPU `edgeMagnitude`'s 4-tap
// approximation (|right-left| + |down-up|) rather than a full 3x3 Sobel —
// visibly the same at preview resolutions and half the sample count.
// =============================================================================

static float4 edgeDetectionVariant(
    VertexOut                    in,
    texture2d<float>             source,
    sampler                      texSampler,
    constant EdgeFieldUniforms&  u
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    float2 invRes     = 1.0 / resolution;
    int2   pixel      = clamp(int2(floor(in.uv * resolution)),
                              int2(0), int2(resolution) - 1);
    float2 selfUV     = (float2(pixel) + 0.5) / resolution;

    // 4-tap edge magnitude. Clamp-to-edge sampler handles out-of-bounds reads
    // so we don't need explicit neighbour clamping in the shader.
    float3 srcOrig = source.sample(texSampler, selfUV).rgb;
    float lC = luminance(srcOrig);
    float lL = luminance(source.sample(texSampler, selfUV + float2(-1, 0) * invRes).rgb);
    float lR = luminance(source.sample(texSampler, selfUV + float2( 1, 0) * invRes).rgb);
    float lU = luminance(source.sample(texSampler, selfUV + float2( 0,-1) * invRes).rgb);
    float lD = luminance(source.sample(texSampler, selfUV + float2( 0, 1) * invRes).rgb);
    (void)lC;
    float edge = saturate(abs(lR - lL) + abs(lD - lU));

    // Apply algorithm multiplier then the CPU's threshold + shaping formula.
    float algMult    = (u.edgeAlgorithm == 1u) ? 1.35 : 1.0;
    float thresholded = max(0.0, edge * algMult - u.edgeThreshold);
    float shaped     = thresholded * max(0.5, u.lineStrength / max(0.05, u.thickness));
    float value      = saturate(shaped);
    if (u.invert == 1u) { value = 1.0 - value; }

    // Colourise: value drives the ink contribution; edgeColor tints it.
    // colour.mode=1 (foregroundBackground) uses (value, value, backgroundIntensity)
    // per CPU's per-variant mapping; other modes use a monochrome
    // max(background, value) fill.
    float3 ink;
    if (u.color.mode == 1u) {
        ink = float3(value, value, u.color.backgroundIntensity);
    } else {
        float bg = u.color.backgroundIntensity;
        ink = float3(max(bg, value));
    }

    // Optional per-variant colour tint from TextCellParameters-style edgeColor.
    // If provided as non-default, multiply into the ink contribution.
    if (u.edgeColor.r + u.edgeColor.g + u.edgeColor.b > 0.0) {
        ink *= u.edgeColor.rgb;
    }

    float3 final = mix(srcOrig, saturate(ink), saturate(u.intensity));
    return float4(final, 1.0);
}

// =============================================================================
// Fragment entry — dispatch on variant.
// =============================================================================

fragment float4 edgeFieldFragment(
    VertexOut                    in         [[stage_in]],
    texture2d<float>             source     [[texture(0)]],
    sampler                      texSampler [[sampler(0)]],
    constant EdgeFieldUniforms&  uniforms   [[buffer(0)]]
) {
    switch (uniforms.variant) {
        case 0:  return edgeDetectionVariant(in, source, texSampler, uniforms);
        default: return source.sample(texSampler, in.uv);
    }
}
