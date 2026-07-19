// RoughBorder.metal
// Seeded procedural "darkroom" borders: 14 edge characters (Type 1–14)
// mirroring the family in Nik Silver Efex Pro 3's Image Borders (engine
// filter "ImageBorderFilter": borderSize / borderSpread / borderGrunge /
// borderRandom, characterized by bundle inspection — no assets, purely
// procedural, seeded so the same seed reproduces the identical border).
// The per-type recipes here are original reconstructions of the family's
// characters, not byte-level ports.
//
// Proportionality contract: all distances are measured in units of
// min(width, height), so every border reads the same at any resolution or
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
    uint  borderType;  // 1..14 recipe selector
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

/// Ridged turbulence in [0, 1]: sharp creases where the noise crosses its
/// midline — spiky, flame-like edges.
inline float rbRidged(float2 p, float seed, float gain) {
    float total = 0.0;
    float amp = 1.0;
    float norm = 0.0;
    float2 q = p;
    for (int i = 0; i < 4; i++) {
        float n = rbValueNoise(q, seed + float(i) * 7.13);
        total += (1.0 - fabs(2.0 * n - 1.0)) * amp;
        norm += amp;
        amp *= gain;
        q *= 2.17;
    }
    return total / norm;
}

/// Hard border edge with a resolution-independent ~1.5px AA band.
/// Returns 1 inside the image, 0 inside the border.
inline float rbEdge(float d, float threshold, float aa) {
    return smoothstep(threshold - aa, threshold + aa, d);
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

    // Inner distances to each image edge; d = nearest, e = which edge,
    // tc = coordinate ALONG that edge (for directional recipes).
    float4 edgeDist = float4(p.x, ext.x - p.x, p.y, ext.y - p.y);
    float d = min(min(edgeDist.x, edgeDist.y), min(edgeDist.z, edgeDist.w));
    int e = 0;
    if (edgeDist.y == d) e = 1;
    if (edgeDist.z == d) e = 2;
    if (edgeDist.w == d) e = 3;
    float tc = (e < 2) ? p.y : p.x;
    float edgeOffset = float(e) * 13.7;  // decorrelate the four edges

    float t = uniforms.size;
    float spread = saturate(uniforms.spread);
    float rough = saturate(uniforms.roughness);
    float seed = uniforms.seed;
    float aa = 1.5 / minDim;

    // Shared noise fields. n2 is isotropic (blobby tears), n1 follows the
    // edge tangent (linework wobble), both in [-1, 1].
    float freq = mix(6.0, 28.0, rough);
    float gain = mix(0.35, 0.75, rough);
    float n2 = rbFbm(p * freq, seed, gain) * 2.0 - 1.0;
    float n1 = rbFbm(float2(tc * freq, edgeOffset), seed, gain) * 2.0 - 1.0;

    // alpha: 1 = image, 0 = border ink.
    float alpha;
    switch (uniforms.borderType) {

    case 1u: {  // Clean Line — near-straight rebate, faint wobble.
        float T = t * (1.0 + 0.1 * spread * n1);
        alpha = rbEdge(d, T, aa);
        break;
    }

    case 2u: {  // Double Rebate — band plus a detached thin inner line.
        float T = t * (1.0 + 0.12 * spread * n1);
        float lineCenter = T * 1.8 + 0.004;
        float lineHalf = max(t * 0.12, 0.0012) * (1.0 + 0.3 * spread * n1);
        float band = rbEdge(d, T, aa);
        float line = 1.0 - (smoothstep(lineCenter - lineHalf - aa, lineCenter - lineHalf + aa, d)
                          - smoothstep(lineCenter + lineHalf - aa, lineCenter + lineHalf + aa, d));
        alpha = min(band, line);
        break;
    }

    default:
    case 3u: {  // Torn — blobby emulsion tear (the original recipe).
        float T = t * (1.0 + spread * n2);
        alpha = rbEdge(d, max(T, 0.0), aa);
        break;
    }

    case 4u: {  // Fine Ragged — smaller, denser tearing.
        float nf = rbFbm(p * freq * 2.5, seed, min(gain + 0.1, 0.85)) * 2.0 - 1.0;
        float T = t * (1.0 + 0.5 * spread * nf);
        alpha = rbEdge(d, max(T, 0.0), aa);
        break;
    }

    case 5u: {  // Brushed — long streaks running along each edge.
        float streak = rbFbm(float2(tc * freq * 3.0, d * freq * 0.4 + edgeOffset),
                             seed, gain) * 2.0 - 1.0;
        float T = t * (1.0 + spread * streak);
        alpha = rbEdge(d, max(T, 0.0), aa * 2.0);
        break;
    }

    case 6u: {  // Heavy Torn — big slow blobs, softer lip.
        float nh = rbFbm(p * freq * 0.5, seed, gain) * 2.0 - 1.0;
        float T = t * (1.0 + 1.6 * spread * nh);
        alpha = rbEdge(d, max(T, 0.0), aa * 3.0);
        break;
    }

    case 7u: {  // Jagged — ridged spikes biting into the frame.
        float r = rbRidged(float2(tc * freq * 1.5, edgeOffset), seed, gain);
        float T = t * (1.0 + spread * (r * 2.0 - 1.0));
        alpha = rbEdge(d, max(T, 0.0), aa);
        break;
    }

    case 8u: {  // Dashed — rebate broken into irregular film-strip dashes.
        float T = t * (1.0 + 0.15 * spread * n1);
        float dashField = rbFbm(float2(tc * mix(10.0, 40.0, rough), edgeOffset),
                                seed, 0.5);
        float dashOn = step(mix(0.25, 0.45, spread), dashField);
        float band = rbEdge(d, T, aa);
        alpha = max(band, 1.0 - dashOn);
        break;
    }

    case 9u: {  // Soft Fade — burned-in gradient edge, noise-modulated.
        float reach = max(t * (1.0 + 2.0 * spread), 1e-4);
        float dMod = d * (1.0 + 0.35 * rough * n2);
        alpha = smoothstep(0.0, reach, dMod);
        break;
    }

    case 10u: {  // Torn + Line — tear band with a wobbling accent line.
        float T = t * (1.0 + spread * n2);
        float band = rbEdge(d, max(T, 0.0), aa);
        float lineCenter = max(t, 0.002) * 2.2 * (1.0 + 0.25 * n1);
        float lineHalf = max(t * 0.1, 0.001);
        float line = 1.0 - (smoothstep(lineCenter - lineHalf - aa, lineCenter - lineHalf + aa, d)
                          - smoothstep(lineCenter + lineHalf - aa, lineCenter + lineHalf + aa, d));
        alpha = min(band, line);
        break;
    }

    case 11u: {  // Spatter — thin band trailing into speckles.
        float T = t * (1.0 + 0.3 * spread * n2);
        float band = rbEdge(d, max(T, 0.0), aa);
        float zone = max(t * (1.0 + 3.0 * spread), 1e-4);
        float fallOff = saturate((d - T) / zone);           // 0 at band → 1 far
        float speck = rbFbm(p * mix(30.0, 90.0, rough), seed + 3.1, 0.6);
        float speckOn = step(mix(0.35, 0.6, fallOff), speck);  // sparser with distance
        alpha = min(band, 1.0 - (1.0 - fallOff) * speckOn);
        break;
    }

    case 12u: {  // Wavy — one slow smooth undulation, clean edge.
        float nw = rbFbm(float2(tc * 3.0, edgeOffset), seed, 0.4) * 2.0 - 1.0;
        float T = t * (1.0 + spread * nw);
        alpha = rbEdge(d, max(T, 0.0), aa);
        break;
    }

    case 13u: {  // Turbulent — flame-like ridged field eating inward.
        float r = rbRidged(p * freq, seed, gain);
        float T = t * (1.0 + 1.2 * spread * (r * 2.0 - 1.0));
        alpha = rbEdge(d, max(T, 0.0), aa * 2.0);
        break;
    }

    case 14u: {  // Grunge Band — torn outer edge, weathered holes inside.
        float T = t * (1.0 + spread * n2);
        float band = rbEdge(d, max(T, 0.0), aa);
        float wear = rbFbm(p * mix(20.0, 60.0, rough), seed + 5.7, 0.65);
        float holes = step(mix(0.85, 0.62, spread), wear);  // more spread → more wear
        float inBorder = 1.0 - band;
        alpha = 1.0 - inBorder * (1.0 - holes);
        break;
    }
    }

    float3 bordered = mix(uniforms.borderRGBA.rgb, src, saturate(alpha));
    float3 final = mix(src, bordered, saturate(uniforms.intensity));
    return float4(final, 1.0);
}
