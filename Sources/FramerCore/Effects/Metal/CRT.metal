// CRT.metal
// Cathode-ray-tube look: barrel distortion + per-channel scanlines + soft
// rectangular vignette. Single fragment pass that mirrors
// ShaderRenderer.applyCRT (Sources/FramerCore/Processing/ShaderRenderer.swift)
// step-for-step.
//
// Pipeline:
//   1. Map UV to centred [-1, 1] coords, distort radially with "curvature"
//      (1/curvature acts as the inverse barrel strength — large curvature ⇒
//      flatter; small ⇒ heavier bulge).
//   2. If the distorted sample falls outside [0, 1]², output black (matches
//      the CPU early-out for sample-out-of-bounds pixels).
//   3. Per-RGB scanline modulation: green follows sin, R/B follow cos, all
//      scaled by `lineStrength` and offset by `brightness`.
//   4. Smoothstep vignette across both axes, derived from `vignette` (in CPU
//      pixels — converted to NDC fraction here).
//   5. Mix with the original source by `intensity`.
//
// Source attribution: original Framer effect, no Grainrad lineage.

#include "ShaderCommon.h"

struct CRTUniforms {
    FramerCommonUniforms common;
    FramerGeometryUniforms geometry;
    FramerColorUniforms colorBlock;     // unused

    float intensity;        // 0..1
    float curvature;        // ≥ 1 (CPU clamps with max(1.0, ...))
    float lineScale;        // pre-computed CPU-side: height / pow(2, lineSize)
    float lineStrength;     // ≥ 0
    float brightness;       // arbitrary additive
    float vignetteWidth;    // pixels (CPU value, ≥ 1)

    float widthPx;
    float heightPx;
};

inline float crtSmoothstep(float edge0, float edge1, float x) {
    float t = saturate((x - edge0) / max(0.0001, edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}

fragment float4 crtFragment(
    VertexOut                  in           [[stage_in]],
    texture2d<float>           source       [[texture(0)]],
    sampler                    texSampler   [[sampler(0)]],
    constant CRTUniforms&      uniforms     [[buffer(0)]]
) {
    float curvature = max(1.0, uniforms.curvature);
    float ny = in.uv.y;
    float nx = in.uv.x;

    // ---- Step 1: barrel distortion -----------------------------------------
    float crtX = nx * 2.0 - 1.0;
    float crtY = ny * 2.0 - 1.0;
    float offsetX = crtY / curvature;
    float offsetY = crtX / curvature;
    crtX += crtX * offsetX * offsetX;
    crtY += crtY * offsetY * offsetY;
    float sampleX = crtX * 0.5 + 0.5;
    float sampleY = crtY * 0.5 + 0.5;

    // Out of bounds → black. The CPU keeps the original alpha; we emit 1.0 to
    // stay consistent with every other GPU effect's opaque output (matters
    // because the GPU output is later composited via CIContext readback).
    float3 srcOrig = source.sample(texSampler, in.uv).rgb;
    if (sampleX <= 0.0 || sampleX >= 1.0 || sampleY <= 0.0 || sampleY >= 1.0) {
        float3 black = float3(0.0);
        float3 finalBlack = mix(srcOrig, black, saturate(uniforms.intensity));
        return float4(finalBlack, 1.0);
    }

    float3 c = source.sample(texSampler, float2(sampleX, sampleY)).rgb;

    // ---- Step 2: per-channel scanlines -------------------------------------
    float scanPhase = ny * uniforms.lineScale * 2.0;
    c.g *= (sin(scanPhase) + 1.0) * 0.15  * uniforms.lineStrength + 1.0 + uniforms.brightness;
    c.r *= (cos(scanPhase) + 1.0) * 0.135 * uniforms.lineStrength + 1.0 + uniforms.brightness;
    c.b *= (cos(scanPhase) + 1.0) * 0.135 * uniforms.lineStrength + 1.0 + uniforms.brightness;

    // ---- Step 3: vignette --------------------------------------------------
    float vigX = uniforms.vignetteWidth / max(uniforms.widthPx, 1.0);
    float vigY = uniforms.vignetteWidth / max(uniforms.heightPx, 1.0);
    float vx = crtSmoothstep(0.0, vigX, 1.0 - fabs(crtX));
    float vy = crtSmoothstep(0.0, vigY, 1.0 - fabs(crtY));

    c = saturate(c) * vx * vy;

    // ---- Step 4: blend with original by intensity --------------------------
    float3 final = mix(srcOrig, c, saturate(uniforms.intensity));
    return float4(final, 1.0);
}
