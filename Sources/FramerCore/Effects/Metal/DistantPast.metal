// DistantPast.metal
// Watercolor / "distant past" palette-snap look. Each fragment runs the four
// sequential steps from the CPU implementation in one pass:
//
//   1. Mild warm shift + desaturate toward luminance (controlled by `fade`)
//   2. Stochastic-dither palette snap to the nearest of up to 6 RGB colours
//      (Euclidean distance in RGB, with deterministic noise injected before
//      snapping to break up banding)
//   3. Radial vignette (skipped when fade ≤ 0.05)
//   4. Optional box blur softness
//   5. Deterministic grain
//   6. Final mix with the original source by intensity
//
// CPU reference: ShaderRenderer.applyDistantPast (Sources/FramerCore/Processing/
// ShaderRenderer.swift). Palette table mirrors the AcerolaFX_DistantPast.ini
// PaletteSwap colours, ordered dark → light.
//
// The palette and its active count are computed CPU-side and passed in via
// uniforms, so the shader stays a pure data-driven kernel.

#include "ShaderCommon.h"

// Hard cap matches the maximum palette length carried by the Swift uniform.
constant int MAX_PALETTE_COLORS = 6;

struct DistantPastUniforms {
    FramerCommonUniforms common;
    FramerGeometryUniforms geometry;
    FramerColorUniforms colorBlock;     // unused, present for layout symmetry

    float intensity;
    float fade;                         // 0..1
    float softness;                     // 0..1 — controls blur mix
    float grain;                        // 0..1

    uint  paletteCount;                 // 2..MAX_PALETTE_COLORS
    uint  blurRadius;                   // 0..3
    float blurMixAmount;                // 0..1
    float _pad0;

    // Resolution (pixels). Passed explicitly so vignette + grain map to the
    // same pixel grid the CPU loops over.
    float widthPx;
    float heightPx;
    float _pad1;
    float _pad2;

    float4 palette[MAX_PALETTE_COLORS]; // .xyz = RGB in 0..1, .w unused
};

// Same hash recipe as ShaderRenderer.applyDistantPast (note the *13 multiplier
// — the palette-dither path uses a different hash from the deterministic-grain
// helper, so the two noise patterns don't cross-correlate).
inline float dpDitherSeed(int2 px) {
    int seed = ((px.x * 31) + (px.y * 17) + ((px.x ^ px.y) * 13)) & 255;
    return (float(seed) / 255.0 - 0.5) * 0.06;
}

inline float3 dpGrain(float3 c, int2 px, float grainAmount) {
    if (grainAmount <= 0.0) { return c; }
    int seed = ((px.x * 29) + (px.y * 31) + ((px.x ^ px.y) * 17)) & 255;
    float centered = (float(seed) / 255.0) - 0.5;
    float delta = centered * (42.0 / 255.0) * grainAmount;
    return saturate(c + float3(delta));
}

// Same constraints as ColorGrade.cgBoxBlur.
inline float3 dpBoxBlur(texture2d<float> source,
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
    return mix(original, sum / max(count, 1.0), saturate(mixAmount));
}

fragment float4 distantPastFragment(
    VertexOut                    in           [[stage_in]],
    texture2d<float>             source       [[texture(0)]],
    sampler                      texSampler   [[sampler(0)]],
    constant DistantPastUniforms& uniforms    [[buffer(0)]]
) {
    float fade = saturate(uniforms.fade);
    float softness = saturate(uniforms.softness);
    float grain = saturate(uniforms.grain);

    float3 srcOriginal = source.sample(texSampler, in.uv).rgb;
    float3 c = srcOriginal;

    // ---- Step 1: warm shift + desaturate -----------------------------------
    float warmShift = fade * 0.04;
    float desatAmount = 1.0 - fade * 0.35;

    c.r += warmShift;
    c.b -= warmShift * 0.6;
    float lum = luminance(c);
    c = float3(lum) + (c - float3(lum)) * desatAmount;

    // ---- Step 2: dithered palette snap -------------------------------------
    int2 px = int2(in.uv * float2(uniforms.widthPx, uniforms.heightPx));
    float noise = dpDitherSeed(px);
    float3 dithered = c + float3(noise);

    int paletteCount = clamp(int(uniforms.paletteCount), 2, MAX_PALETTE_COLORS);
    float bestDist = 1.0e9;
    float3 bestColor = uniforms.palette[0].rgb;
    for (int i = 0; i < MAX_PALETTE_COLORS; i++) {
        if (i >= paletteCount) { break; }
        float3 pc = uniforms.palette[i].rgb;
        float3 d  = dithered - pc;
        float dist = dot(d, d);
        if (dist < bestDist) {
            bestDist = dist;
            bestColor = pc;
        }
    }
    c = bestColor;

    // ---- Step 3: vignette --------------------------------------------------
    if (fade > 0.05) {
        float2 cxy = float2(uniforms.widthPx, uniforms.heightPx) * 0.5;
        float2 dn  = (float2(px) - cxy) / cxy;
        float distSq = dot(dn, dn);
        float vigStr = fade * 0.8;
        float vignette = max(0.0, 1.0 - distSq * vigStr * 0.4);
        c *= vignette;
    }

    // ---- Step 4: softness blur (applied after palette to soften banding) ---
    float2 texel = 1.0 / float2(source.get_width(), source.get_height());
    c = dpBoxBlur(source, texSampler, in.uv, texel,
                  int(uniforms.blurRadius), uniforms.blurMixAmount, c);

    // ---- Step 5: grain -----------------------------------------------------
    c = dpGrain(c, px, grain);

    // ---- Step 6: blend with original by intensity --------------------------
    float3 final = mix(srcOriginal, c, saturate(uniforms.intensity));
    return float4(final, 1.0);
}
