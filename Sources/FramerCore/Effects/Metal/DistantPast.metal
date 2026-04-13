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

// Per-pixel DistantPast pipeline: steps 1 (warm shift + desat), 2 (dithered
// palette snap), 3 (vignette). Re-runnable on any (raw source, integer pixel)
// pair so the post-grade box blur can sample neighbours and apply the same
// pipeline before averaging — algebraically equivalent to "process whole
// image then box-blur," which is what CPU does
// (ShaderRenderer.swift:233-326).
// CPU's per-stage byte quantization is reproduced here so that the palette
// snap in step 2 sees the same input domain CPU sees. ShaderPrimitives
// .clampByte rounds to nearest integer in 0..255 and writes back as UInt8;
// the next stage then re-reads via Double(pixels[i]) / 255.0. Net effect:
// each intermediate gets snapped to a 1/255 grid. For ColorGrade's
// continuous transforms this adds ~0.5/255 fp noise that compounds little;
// for DistantPast the palette-snap stage is sensitive to ≤1/255 input
// changes near a palette boundary and a missing quantization can flip the
// chosen colour, producing 255 max delta vs CPU. Codex flagged.
inline float3 dpQuantizeToByte(float3 c) {
    return floor(saturate(c) * 255.0 + 0.5) / 255.0;
}

inline float3 dpProcessPixel(float3 src, int2 px, constant DistantPastUniforms& u) {
    float fade = saturate(u.fade);

    // Step 1: warm shift + desaturate. Then byte-quantize to mirror CPU's
    // pixels[idx] = clampByte(...) write at ShaderRenderer.swift:254-256.
    float warmShift = fade * 0.04;
    float desatAmount = 1.0 - fade * 0.35;
    float3 c = src;
    c.r += warmShift;
    c.b -= warmShift * 0.6;
    float lum = luminance(c);
    c = float3(lum) + (c - float3(lum)) * desatAmount;
    c = dpQuantizeToByte(c);

    // Step 2: dithered palette snap. Palette colours are already in 0..1 from
    // the uniform, so the snap result is exact. CPU writes the snapped colour
    // back as bytes (clampByte(pc.r * 255)) — equivalent to dpQuantizeToByte
    // on the palette entry, which is a no-op since palette colours are
    // already on the 1/255 grid by construction. Skip the extra quantize
    // here for clarity.
    float noise = dpDitherSeed(px);
    float3 dithered = c + float3(noise);
    int paletteCount = clamp(int(u.paletteCount), 2, MAX_PALETTE_COLORS);
    float bestDist  = 1.0e9;
    float3 bestColor = u.palette[0].rgb;
    for (int i = 0; i < MAX_PALETTE_COLORS; i++) {
        if (i >= paletteCount) { break; }
        float3 pc = u.palette[i].rgb;
        float3 d  = dithered - pc;
        float dist = dot(d, d);
        if (dist < bestDist) {
            bestDist = dist;
            bestColor = pc;
        }
    }
    c = bestColor;

    // Step 3: vignette. Then byte-quantize to mirror CPU's clampByte writes
    // at ShaderRenderer.swift:310-312.
    if (fade > 0.05) {
        float2 cxy = float2(u.widthPx, u.heightPx) * 0.5;
        float2 dn  = (float2(px) - cxy) / cxy;
        float distSq = dot(dn, dn);
        float vigStr = fade * 0.8;
        float vignette = max(0.0, 1.0 - distSq * vigStr * 0.4);
        c *= vignette;
        c = dpQuantizeToByte(c);
    }

    return c;
}

fragment float4 distantPastFragment(
    VertexOut                    in           [[stage_in]],
    texture2d<float>             source       [[texture(0)]],
    sampler                      texSampler   [[sampler(0)]],
    constant DistantPastUniforms& uniforms    [[buffer(0)]]
) {
    float grain = saturate(uniforms.grain);

    float2 resolution = float2(uniforms.widthPx, uniforms.heightPx);
    int2   pixel      = clamp(int2(floor(in.uv * resolution)), int2(0), int2(resolution) - 1);
    float2 selfUV     = (float2(pixel) + 0.5) / resolution;

    float3 srcOriginal = source.sample(texSampler, selfUV).rgb;

    // Steps 1-3 on the centre pixel.
    float3 c = dpProcessPixel(srcOriginal, pixel, uniforms);

    // Step 4: softness blur — applied to the PROCESSED intermediate, not the
    // raw source. Previous version sampled `source` inside the blur loop,
    // which dragged the unprocessed image back into the result whenever
    // softness > 0 (codex flagged: DistantPast.metal:144-147 in pre-fix).
    // Match CPU's grade-then-box-blur order by re-running the per-pixel
    // pipeline on each in-bounds neighbour, averaging, then mixing with the
    // centre processed value. Border policy: clip kernel to in-bounds pixels
    // and divide by actual sample count (matches ShaderPrimitives
    // .applyBoxBlur:79-87).
    int radius = clamp(int(uniforms.blurRadius), 0, 3);
    if (radius > 0 && uniforms.blurMixAmount > 0.0) {
        float3 sum   = float3(0.0);
        float  count = 0.0;
        int    maxX  = int(resolution.x) - 1;
        int    maxY  = int(resolution.y) - 1;
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
                sum += dpProcessPixel(nSrc, int2(nx, ny), uniforms);
                count += 1.0;
            }
        }
        float3 blurredProcessed = sum / max(count, 1.0);
        c = mix(c, blurredProcessed, saturate(uniforms.blurMixAmount));
    }

    // Step 5: grain
    c = dpGrain(c, pixel, grain);

    // Step 6: blend with original by intensity
    float3 final = mix(srcOriginal, c, saturate(uniforms.intensity));
    return float4(final, 1.0);
}
