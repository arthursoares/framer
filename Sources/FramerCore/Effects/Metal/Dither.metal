// Dither.metal
// GPU dithering via blue-noise threshold approximation.
//
// CRITICAL DESIGN INSIGHT (read grainrad/notes/dithering.md before changing):
// True error diffusion (Floyd-Steinberg, Atkinson, Stucki, Artistic Drip) is
// inherently serial — each pixel's quantization error feeds forward into
// neighbours. Naïvely parallelising it gives wrong output. Grainrad sidesteps
// this by approximating each error-diffusion algorithm with a procedural
// blue-noise threshold (Jorge Jimenez's IGN function) tuned per-algorithm to
// look like its serial counterpart on natural images. The trade-off is that
// pathological synthetic patterns (smooth gradients, test charts) will reveal
// the approximation. For real photos the eye can't tell.
//
// Visual character per error-diffusion algorithm comes from a single
// per-algorithm scaling coefficient applied to the IGN noise around 0.5:
//
//     threshold = 0.5 + (ign(pos) - 0.5) * COEF
//
// Larger COEF → broader noise spread → coarser-looking output. The
// coefficients here are eyeballed to produce visual character close to the
// CPU implementations in ShaderASCIIRenderer/DitherRenderer for natural
// photo input. Tune by comparing output side-by-side on representative
// images, not by chasing pixel-perfect parity (which is impossible).
//
// Algorithms NOT GPU-portable in this shader:
//   - Riemersma (Hilbert-curve traversal). The Swift wrapper throws
//     `MetalEffectError.metalUnavailable` for that algorithm so the CPU path
//     handles it as the export-quality fallback.
//
// CPU reference: Sources/FramerCore/Processing/DitherRenderer.swift
// Bayer matrices and IGN come from ShaderCommon.h.
//
// Primary references (no Grainrad code copied):
//   - Bayer (1973) — ordered-dither matrices
//   - Floyd & Steinberg (1976), Atkinson (1984), Stucki (1981) — serial kernels
//   - Jimenez (2014, SIGGRAPH) — Interleaved Gradient Noise

#include "ShaderCommon.h"

// =============================================================================
// Algorithm IDs — keep in lockstep with DitherAlgorithm in Swift / CPU enum.
// =============================================================================
//   0 bayer
//   1 floydSteinberg
//   2 atkinson
//   3 blueNoise
//   4 artisticDrip
//   5 halftone
//   6 stucki
//   7 whiteNoise
//   8 riemersma  ← unsupported on GPU, Swift forces CPU path

constant uint DITHER_BAYER          = 0u;
constant uint DITHER_FLOYD          = 1u;
constant uint DITHER_ATKINSON       = 2u;
constant uint DITHER_BLUE_NOISE     = 3u;
constant uint DITHER_ARTISTIC_DRIP  = 4u;
constant uint DITHER_HALFTONE       = 5u;
constant uint DITHER_STUCKI         = 6u;
constant uint DITHER_WHITE_NOISE    = 7u;

// =============================================================================
// Color mode IDs
// =============================================================================
//   0 bw / twoTone / dominantTwoTone (monochrome dither, optional 2-colour map)
//   1 color (per-channel quantization with dithered offset)

constant uint DITHER_COLOR_MONO   = 0u;
constant uint DITHER_COLOR_LEVELS = 1u;

struct DitherUniforms {
    FramerCommonUniforms common;        // unused
    FramerGeometryUniforms geometry;    // unused
    FramerColorUniforms colorBlock;     // unused

    uint  algorithm;        // 0..7 (8 = CPU only)
    uint  bayerLevel;       // 1..4 → matrix 4/8/16/32
    uint  colorMode;        // 0 mono, 1 per-channel levels
    uint  colorLevels;      // 2..8 (only used when colorMode == 1)

    float threshold;        // 0.1..0.9 — shifts the decision point; 0.5 = neutral
    float sharpenAmount;    // 0..1
    float contrastAmount;   // 0..1
    float _pad0;

    // Two-tone palette for the mono mode. Used when colorMode == 0 to map the
    // 0/1 dither output to actual colours (matches CPU
    // applyTwoToneMapping); pure-bw mode just leaves these as black/white.
    float4 foregroundRGBA;
    float4 backgroundRGBA;
    uint   useTwoTone;      // 0 = bw, 1 = use foreground/background mapping
    float  _pad1;
    float  _pad2;
    float  _pad3;
};

// =============================================================================
// Procedural Bayer threshold for sizes 4, 8, 16, 32.
// Uses the standard bit-interleave construction so any power of two works.
// Result is a valid Bayer matrix with dispersed-dot ordering — the exact pixel
// positions differ from CPU's recursive M_n construction by a permutation,
// but the visual character is identical.
// =============================================================================

inline float bayerProcedural(uint2 pos, int nBits) {
    uint x = pos.x;
    uint y = pos.y;
    uint v = 0u;
    for (int k = 0; k < nBits; k++) {
        uint bx = (x >> k) & 1u;
        uint by = (y >> k) & 1u;
        // Bit pair at position 2*(nBits-1-k): (bx XOR by) and (bx).
        // Reverses bit order so the lowest-frequency oscillation lives in
        // the most significant bits — the standard ordered-dither pattern.
        uint bits = (bx ^ by) | (bx << 1);
        v |= bits << (2u * uint(nBits - 1 - k));
    }
    uint total = 1u << (2u * uint(nBits));
    return (float(v) + 0.5) / float(total);
}

inline float bayerThreshold(uint2 pos, uint level) {
    // bayerLevel 1..4 → 2..5 bits → matrix 4..32.
    int nBits = clamp(int(level) + 1, 2, 5);
    return bayerProcedural(pos, nBits);
}

// =============================================================================
// Clustered-dot halftone (6×6 matrix — same as DitherRenderer.cachedHalftoneFlat).
// Hard-coded so we don't pay an additional uniform for it.
// =============================================================================

constant float halftone6x6[36] = {
    34.5/36.0, 29.5/36.0, 17.5/36.0, 21.5/36.0, 30.5/36.0, 35.5/36.0,
    28.5/36.0, 14.5/36.0,  9.5/36.0, 16.5/36.0, 20.5/36.0, 31.5/36.0,
    13.5/36.0,  8.5/36.0,  4.5/36.0,  5.5/36.0, 15.5/36.0, 19.5/36.0,
    12.5/36.0,  3.5/36.0,  0.5/36.0,  1.5/36.0, 10.5/36.0, 18.5/36.0,
    27.5/36.0,  7.5/36.0,  2.5/36.0,  6.5/36.0, 11.5/36.0, 24.5/36.0,
    33.5/36.0, 26.5/36.0, 22.5/36.0, 23.5/36.0, 25.5/36.0, 32.5/36.0,
};

inline float halftoneThreshold(uint2 pos) {
    return halftone6x6[(pos.y % 6u) * 6u + (pos.x % 6u)];
}

// =============================================================================
// Hash-based white noise for the whiteNoise algorithm. Different recipe from
// IGN so the noise pattern is genuinely white (uncorrelated across pixels)
// rather than blue.
// =============================================================================

inline float whiteNoise(uint2 pos) {
    uint h = pos.x * 374761393u + pos.y * 668265263u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h = h ^ (h >> 16);
    return float(h & 0xFFFFFFu) / float(0xFFFFFFu);
}

// =============================================================================
// Per-algorithm threshold (returns the value compared against luminance).
//
// Coefficients chosen to approximate the CPU algorithm's character:
//  - Floyd-Steinberg: full diffusion of error → broad noise distribution → 0.85
//  - Stucki: similar diffusion structure but more spread → 0.80
//  - Atkinson: only 6/8 of error diffused → tighter result → 0.75
//  - Artistic Drip: heavier downward bias in CPU kernel → tighter still → 0.65
// =============================================================================

inline float thresholdForAlgorithm(uint algorithm, uint2 pos, uint bayerLevel,
                                   float baseThreshold) {
    switch (algorithm) {
        case DITHER_BAYER: {
            // Bayer just shifts the matrix value by (baseThreshold - 0.5) so
            // the threshold tracks the user's threshold knob.
            float m = bayerThreshold(pos, bayerLevel);
            return clamp(m + (baseThreshold - 0.5), 0.0, 1.0);
        }
        case DITHER_HALFTONE: {
            float m = halftoneThreshold(pos);
            return clamp(m + (baseThreshold - 0.5), 0.0, 1.0);
        }
        case DITHER_BLUE_NOISE: {
            return clamp(ign(float2(pos)) + (baseThreshold - 0.5), 0.0, 1.0);
        }
        case DITHER_WHITE_NOISE: {
            return clamp(whiteNoise(pos) + (baseThreshold - 0.5), 0.0, 1.0);
        }
        case DITHER_FLOYD: {
            float n = ign(float2(pos));
            return clamp(baseThreshold + (n - 0.5) * 0.85, 0.0, 1.0);
        }
        case DITHER_STUCKI: {
            float n = ign(float2(pos));
            return clamp(baseThreshold + (n - 0.5) * 0.80, 0.0, 1.0);
        }
        case DITHER_ATKINSON: {
            float n = ign(float2(pos));
            return clamp(baseThreshold + (n - 0.5) * 0.75, 0.0, 1.0);
        }
        case DITHER_ARTISTIC_DRIP: {
            float n = ign(float2(pos));
            return clamp(baseThreshold + (n - 0.5) * 0.65, 0.0, 1.0);
        }
        default:
            return baseThreshold;
    }
}

// =============================================================================
// Pre-processing: 3×3 box-blur unsharp mask + S-curve contrast
// =============================================================================

inline float3 ditherSharpen(texture2d<float> source, sampler s,
                            float2 uv, float2 texelSize, float amount,
                            float3 original) {
    if (amount <= 0.0) { return original; }
    float3 sum = float3(0.0);
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            sum += source.sample(s, uv + float2(float(dx), float(dy)) * texelSize).rgb;
        }
    }
    float3 blurred = sum / 9.0;
    return saturate(original + 2.0 * amount * (original - blurred));
}

// Symmetric S-curve about 0.5. CPU uses a precomputed LUT with strength
// factor `amount * 5.0`; reproduce the same shape directly.
inline float3 ditherContrast(float3 c, float amount) {
    if (amount <= 0.0) { return c; }
    float strength = amount * 5.0;
    // Centre on 0.5, apply odd polynomial skew, recentre.
    float3 centred = c - 0.5;
    float3 sign = float3(centred.r >= 0.0 ? 1.0 : -1.0,
                         centred.g >= 0.0 ? 1.0 : -1.0,
                         centred.b >= 0.0 ? 1.0 : -1.0);
    float3 magnitude = abs(centred) * 2.0;     // 0..1
    float3 boosted = pow(magnitude, 1.0 / (1.0 + strength));
    return saturate(0.5 + sign * boosted * 0.5);
}

// =============================================================================
// Mono dither: returns 0 or 1 per pixel, mapped through fg/bg if requested.
// =============================================================================

inline float3 ditherMono(float3 c, float threshold, uint useTwoTone,
                         float3 fg, float3 bg) {
    float lum = luminance(c);
    float bit = step(threshold, lum);
    if (useTwoTone == 1u) {
        return mix(bg, fg, bit);
    }
    return float3(bit);
}

// =============================================================================
// Per-channel quantization with dithered offset. Output is `colorLevels`
// uniformly-spaced steps per channel — when paired with the threshold offset
// from the algorithm, gives the GameBoy-palette / vintage-game look.
// =============================================================================

inline float quantizeChannel(float v, float threshold, uint levels) {
    if (levels < 2u) { return v; }
    float steps = float(levels - 1u);
    // Offset the input by (threshold - 0.5) / steps so the dithered noise
    // wiggles the input across step boundaries.
    float offset = (threshold - 0.5) / steps;
    float adjusted = saturate(v + offset);
    return round(adjusted * steps) / steps;
}

// =============================================================================
// Fragment entry
// =============================================================================

fragment float4 ditherFragment(
    VertexOut                  in           [[stage_in]],
    texture2d<float>           source       [[texture(0)]],
    sampler                    texSampler   [[sampler(0)]],
    constant DitherUniforms&   uniforms     [[buffer(0)]]
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    float2 texel      = 1.0 / resolution;

    float3 src = source.sample(texSampler, in.uv).rgb;

    // ---- Pre-processing ---------------------------------------------------
    src = ditherSharpen(source, texSampler, in.uv, texel, uniforms.sharpenAmount, src);
    src = ditherContrast(src, uniforms.contrastAmount);

    uint2 pixel = uint2(in.uv * resolution);

    if (uniforms.colorMode == DITHER_COLOR_LEVELS) {
        // Per-channel dither: each channel gets its own threshold via the
        // algorithm function (decorrelated by adding small per-channel
        // offsets to the position so channels don't align identically).
        float thrR = thresholdForAlgorithm(uniforms.algorithm,
                                            pixel,
                                            uniforms.bayerLevel,
                                            uniforms.threshold);
        float thrG = thresholdForAlgorithm(uniforms.algorithm,
                                            pixel + uint2(13u, 7u),
                                            uniforms.bayerLevel,
                                            uniforms.threshold);
        float thrB = thresholdForAlgorithm(uniforms.algorithm,
                                            pixel + uint2(31u, 19u),
                                            uniforms.bayerLevel,
                                            uniforms.threshold);
        float3 q = float3(quantizeChannel(src.r, thrR, uniforms.colorLevels),
                          quantizeChannel(src.g, thrG, uniforms.colorLevels),
                          quantizeChannel(src.b, thrB, uniforms.colorLevels));
        return float4(q, 1.0);
    } else {
        float threshold = thresholdForAlgorithm(uniforms.algorithm,
                                                pixel,
                                                uniforms.bayerLevel,
                                                uniforms.threshold);
        float3 outRGB = ditherMono(src,
                                   threshold,
                                   uniforms.useTwoTone,
                                   uniforms.foregroundRGBA.rgb,
                                   uniforms.backgroundRGBA.rgb);
        return float4(outRGB, 1.0);
    }
}
