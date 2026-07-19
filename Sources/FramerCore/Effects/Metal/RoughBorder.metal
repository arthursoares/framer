// RoughBorder.metal
// Seeded procedural "darkroom" border: a rectangle inset from the image
// edge whose boundary is displaced by deterministic multi-octave value
// noise. Modeled on the behavior of Nik Silver Efex Pro 3's Image Borders
// (its engine filter "ImageBorderFilter": borderSize / borderSpread /
// borderGrunge / borderRandom) as characterized by bundle inspection —
// no assets, purely procedural, seeded so the same seed reproduces the
// identical border.
//
// Proportionality contract: all distances are measured in units of
// min(width, height), so the border reads the same at any resolution or
// aspect ratio. Noise is sampled in the same normalized space, so the
// border SHAPE is also resolution-independent for a given seed.
//
// Helper functions are rb-prefixed: every .metal file ships in a single
// translation unit under the runtime source-concatenation fallback
// (MetalEffectLibrary), so names must not collide across files.

#include "ShaderCommon.h"

struct RoughBorderUniforms {
    FramerCommonUniforms   common;      // unused
    FramerGeometryUniforms geometry;    // unused
    FramerColorUniforms    colorBlock;  // unused

    float intensity;   // 0..1 final mix with source
    float size;        // border thickness, fraction of min(w,h)
    float spread;      // 0..1 boundary displacement, fraction of size
    float roughness;   // 0..1 clean (long smooth waves) .. rough (jagged)
    float seed;        // vary-border seed (already reduced to float)
    float widthPx;
    float heightPx;
    float _pad0;
    float4 borderRGBA;
};

inline float rbHash(float2 p, float seed) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031 + seed * 0.017);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

inline float rbValueNoise(float2 p, float seed) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = rbHash(i, seed);
    float b = rbHash(i + float2(1.0, 0.0), seed);
    float c = rbHash(i + float2(0.0, 1.0), seed);
    float d = rbHash(i + float2(1.0, 1.0), seed);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// 4-octave fbm, output normalized to [0, 1]. `gain` sets how much energy
/// the higher octaves keep — the Roughness dial in disguise.
inline float rbFbm(float2 p, float seed, float gain) {
    float total = 0.0;
    float amp = 1.0;
    float norm = 0.0;
    float2 q = p;
    for (int i = 0; i < 4; i++) {
        total += rbValueNoise(q, seed + float(i) * 7.13) * amp;
        norm += amp;
        amp *= gain;
        q *= 2.17;  // non-integer lacunarity avoids octave lattice alignment
    }
    return total / norm;
}

fragment float4 roughBorderFragment(
    VertexOut                     in         [[stage_in]],
    texture2d<float>              source     [[texture(0)]],
    sampler                       texSampler [[sampler(0)]],
    constant RoughBorderUniforms& uniforms   [[buffer(0)]]
) {
    float2 dims = float2(max(uniforms.widthPx, 1.0), max(uniforms.heightPx, 1.0));
    float minDim = min(dims.x, dims.y);

    // Pin to the integer pixel grid (house rule — in.uv arrives at fragment
    // centers; see Halftone.metal:60-66) so the mask is exactly reproducible
    // for a given (seed, resolution).
    int2 pixel = clamp(int2(floor(in.uv * dims)), int2(0), int2(dims) - 1);
    float2 selfUV = (float2(pixel) + 0.5) / dims;
    float3 src = source.sample(texSampler, selfUV).rgb;

    // Normalized space: 1.0 == min(w,h) pixels. Border thickness and noise
    // both live here, which is what keeps the look aspect-ratio-proportional.
    float2 p = (float2(pixel) + 0.5) / minDim;
    float2 ext = dims / minDim;

    // Inner distance to the nearest image edge.
    float d = min(min(p.x, ext.x - p.x), min(p.y, ext.y - p.y));

    // Seeded displacement: low roughness = long smooth undulation, high
    // roughness = dense jagged grain. Noise is [-1, 1].
    float freq = mix(6.0, 28.0, saturate(uniforms.roughness));
    float gain = mix(0.35, 0.75, saturate(uniforms.roughness));
    float n = rbFbm(p * freq, uniforms.seed, gain) * 2.0 - 1.0;

    // Boundary: base thickness, wandering by ±spread of itself.
    float threshold = max(uniforms.size * (1.0 + uniforms.spread * n), 0.0);

    // ~1.5px anti-aliasing band regardless of resolution.
    float aa = 1.5 / minDim;
    float t = smoothstep(threshold - aa, threshold + aa, d);

    float3 bordered = mix(uniforms.borderRGBA.rgb, src, t);
    float3 final = mix(src, bordered, saturate(uniforms.intensity));
    return float4(final, 1.0);
}
