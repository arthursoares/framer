// Glitch.metal
// Fragment shader for the Glitch bucket. Currently implements the VHS variant;
// PixelSort already has a dedicated shader at Sources/FramerCore/Effects/Metal/
// PixelSort.metal (used by the `.shader` pixel-sort layer type), so only VHS
// needs a bucket-system GPU path.
//
// CPU reference: Sources/FramerCore/Effects/Renderers/GlitchRenderer.swift.
// Uniform layout mirrors GlitchGPURenderer.Uniforms on the Swift side — keep
// field order, types, and padding identical.

#include "ShaderCommon.h"

struct GlitchUniforms {
    FramerCommonUniforms   common;
    FramerGeometryUniforms geometry;
    FramerColorUniforms    color;

    uint  variant;           // 0 = VHS (future: 1 = jpeg glitch, etc.)
    float intensity;         // 0..1, blend with original
    float amount;            // 0..1, overall glitch strength
    float distortion;        // 0..1, horizontal wobble

    float colorBleed;        // 0..1, R/B chromatic aberration magnitude
    float scanlines;         // 0..1, scanline darkening depth
    float trackingError;     // 0..1, row-shift amplitude
    float _pad0;
};

// =============================================================================
// VHS — stylised analogue-tape aesthetic: horizontal tracking drift +
// per-channel chromatic aberration + darkening scanlines + mild pixel wobble
// (distortion). Mirrors the CPU blend weights so switching GPU ↔ CPU produces
// visually equivalent output within float precision.
// =============================================================================

static float4 vhsVariant(
    VertexOut                in,
    texture2d<float>         source,
    sampler                  texSampler,
    constant GlitchUniforms& u
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    float2 invRes     = 1.0 / resolution;
    int2   pixel      = clamp(int2(floor(in.uv * resolution)),
                              int2(0), int2(resolution) - 1);
    float2 selfUV     = (float2(pixel) + 0.5) / resolution;

    float amount       = saturate(u.amount);
    float distortion   = saturate(u.distortion);
    float colorBleed   = saturate(u.colorBleed);
    float scanDepth    = saturate(u.scanlines);
    float tracking     = saturate(u.trackingError);

    // 1. Tracking error — horizontal shift that varies by scanline. Low-freq
    //    sine dominates with a high-freq hash layer for occasional glitches.
    float y = float(pixel.y);
    float trackShift = sin(y * 0.05) * tracking * 18.0 * amount
                     + (fract(sin(y * 12.9898) * 43758.5453) - 0.5) * tracking * 4.0 * amount;

    // 2. Distortion — small per-pixel horizontal wobble, tighter frequency
    //    than tracking. Sum of two sines to avoid a perfectly periodic look.
    float distShift = (sin(y * 0.4) + sin(y * 1.3) * 0.5) * distortion * 6.0 * amount;

    // 3. Chromatic aberration — R and B channels sampled at horizontally
    //    offset positions relative to G. Magnitude scales with colorBleed,
    //    modulated by amount.
    float chroma = colorBleed * 6.0 * amount;

    float2 baseShift = float2(trackShift + distShift, 0.0) * invRes;
    float2 rShift    = baseShift + float2( chroma, 0.0) * invRes;
    float2 bShift    = baseShift + float2(-chroma, 0.0) * invRes;
    float2 gShift    = baseShift;

    float r = source.sample(texSampler, selfUV + rShift).r;
    float g = source.sample(texSampler, selfUV + gShift).g;
    float b = source.sample(texSampler, selfUV + bShift).b;
    float3 shifted = float3(r, g, b);

    // 4. Scanlines — darken every other row pair; depth controls contrast.
    //    Uses pixel.y parity so the pattern is stable at all resolutions.
    float scanMod   = 0.5 + 0.5 * sin(y * M_PI_F);
    float scanMult  = 1.0 - scanDepth * 0.6 * (1.0 - scanMod);
    float3 scanned  = shifted * scanMult;

    float3 srcOrig = source.sample(texSampler, selfUV).rgb;
    float3 final   = mix(srcOrig, saturate(scanned), saturate(u.intensity));
    return float4(final, 1.0);
}

fragment float4 glitchFragment(
    VertexOut                in         [[stage_in]],
    texture2d<float>         source     [[texture(0)]],
    sampler                  texSampler [[sampler(0)]],
    constant GlitchUniforms& uniforms   [[buffer(0)]]
) {
    switch (uniforms.variant) {
        case 0:  return vhsVariant(in, source, texSampler, uniforms);
        default: return source.sample(texSampler, in.uv);
    }
}
