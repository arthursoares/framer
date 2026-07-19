// FilmGrain.metal
// Seeded procedural film grain, modeled on Silver Efex's grain engine
// (characterized by bundle inspection: `NewFilmType` grainSliderStrength /
// grainSliderSoftness plus `Film_Grain_1` protect_hilights / protect_shadows;
// fully procedural — no scanned grain plates anywhere in the bundle).
//
// The model:
//   - grainsPerPixel (1..500, HIGHER = finer): sets the grain lattice pitch.
//     Few grains per pixel → each grain spans multiple pixels (chunky);
//     many → sub-pixel grains average out (tight, smooth).
//   - softness: 0 = hard crisp specks (nearest-cell noise), 1 = soft blobs
//     (smooth value-noise interpolation).
//   - protectHighlights / protectShadows: midtone weighting — real film
//     grain lives in the midtones; pure white and black carry almost none.
//   - Achromatic: the same offset is added to all three channels.
//
// pitchScale carries the preview→export scale factor (currentMax /
// previewBaseDimension, same convention as DitherGPURenderer) so exports
// reproduce the grain scale the preview showed.
//
// Helper functions are fg-prefixed: all .metal files are compiled as ONE
// translation unit under the runtime source-concatenation fallback.

#include "ShaderCommon.h"

struct FilmGrainUniforms {
    FramerCommonUniforms   common;      // unused
    FramerGeometryUniforms geometry;    // unused
    FramerColorUniforms    colorBlock;  // unused

    float intensity;         // 0..1 grain amount
    float grainsPerPixel;    // 1..500
    float softness;          // 0..1
    float protectHighlights; // 0..1

    float protectShadows;    // 0..1
    float seed;
    float widthPx;
    float heightPx;

    float pitchScale;        // preview→export grain-size compensation
    float _pad0;
    float _pad1;
    float _pad2;
};

inline float fgHash(float2 p, float seed) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031 + seed * 0.019);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

/// Smooth value noise over the grain lattice.
inline float fgValueNoise(float2 q, float seed) {
    float2 i = floor(q);
    float2 f = fract(q);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = fgHash(i, seed);
    float b = fgHash(i + float2(1.0, 0.0), seed);
    float c = fgHash(i + float2(0.0, 1.0), seed);
    float d = fgHash(i + float2(1.0, 1.0), seed);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fragment float4 filmGrainFragment(
    VertexOut                   in         [[stage_in]],
    texture2d<float>            source     [[texture(0)]],
    sampler                     texSampler [[sampler(0)]],
    constant FilmGrainUniforms& uniforms   [[buffer(0)]]
) {
    float2 dims = float2(max(uniforms.widthPx, 1.0), max(uniforms.heightPx, 1.0));

    // Pin to the integer pixel grid (house rule; see Halftone.metal:60-66)
    // so the grain field is exactly reproducible per (seed, resolution).
    int2 pixel = clamp(int2(floor(in.uv * dims)), int2(0), int2(dims) - 1);
    float2 selfUV = (float2(pixel) + 0.5) / dims;
    float3 src = source.sample(texSampler, selfUV).rgb;

    float g = clamp(uniforms.grainsPerPixel, 1.0, 500.0);
    float softness = saturate(uniforms.softness);

    // Grain lattice pitch in pixels: chunky at low g, sub-pixel at high g.
    float pitch = clamp(16.0 / sqrt(g), 0.8, 24.0) * max(uniforms.pitchScale, 0.05);
    float2 q = (float2(pixel) + 0.5) / pitch;

    // Hard = one random value per lattice cell (crisp speck edges);
    // soft = smoothly interpolated field (blobs). Softness blends them.
    float hard = fgHash(floor(q), uniforms.seed);
    float soft = fgValueNoise(q, uniforms.seed);
    float n = mix(hard, soft, softness) - 0.5;   // [-0.5, 0.5]

    // Fine grain reads weaker (many grains averaging inside a pixel).
    float amp = uniforms.intensity * 0.5 * mix(1.0, 0.45, saturate(g / 500.0));

    // Midtone weighting: grain thins toward pure black/white, with the
    // protect dials widening the guarded tonal bands.
    float L = luminance(src);
    float shadowBand = uniforms.protectShadows * 0.5 + 0.02;
    float highlightBand = uniforms.protectHighlights * 0.5 + 0.02;
    float w = smoothstep(0.0, shadowBand, L)
            * (1.0 - smoothstep(1.0 - highlightBand, 1.0, L));

    float3 grained = saturate(src + n * amp * w);
    return float4(grained, 1.0);
}
