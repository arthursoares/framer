// BWFilm.metal
// Silver-Efex-style black-and-white conversion. Modeled on the
// SilverEfexParams pipeline characterized by bundle inspection of Silver
// Efex Pro 3 (ColorFilter block deliberately omitted):
//
//   1. Six-channel spectral sensitivity (sensR/Ye/G/Cy/B/Mg): the pixel's
//      hue decomposes into six 60°-spaced basis lobes; each channel's
//      sensitivity shifts how strongly that hue family contributes to the
//      gray value, scaled by chroma (achromatic pixels are unaffected).
//   2. Zone tonality: brightness global + shadow/midtone/highlight bands
//      (smooth luminance masks), contrast about the mid pivot, and
//      protect-highlights/shadows soft knees.
//   3. Tone curve: sampled from a CPU-baked 256×1 r32Float LUT texture
//      (texture slot 1) via .read() — gamma, black/white nodes, and
//      control points are baked host-side (BWFilmRenderer.bakeCurve).
//
// Helper functions are bwf-prefixed: all .metal files compile as ONE
// translation unit under the runtime source-concatenation fallback.

#include "ShaderCommon.h"

struct BWFilmUniforms {
    FramerCommonUniforms   common;      // unused
    FramerGeometryUniforms geometry;    // unused
    FramerColorUniforms    colorBlock;  // unused

    float intensity;   // 0..1 mix with the color source
    float sensR;       // -100..100 each
    float sensYe;
    float sensG;

    float sensCy;
    float sensB;
    float sensMg;
    float brightness;  // -100..100

    float briHighlights;
    float briMidtones;
    float briShadows;
    float contrast;    // -100..100

    float protectHighlights;  // 0..100
    float protectShadows;     // 0..100
    float toningStrength;     // 0..100
    float toneHueHigh;        // degrees

    float toneStrengthHigh;
    float toneHueLow;
    float toneStrengthLow;
    float toneBalance;        // -100..100

    float vigStrength;        // -100..100
    float vigSize;            // 0..100
    float vigShape;           // 1..5 superellipse exponent
    float beStrengthTop;

    float beStrengthBottom;
    float beStrengthLeft;
    float beStrengthRight;
    float beSizeTop;

    float beSizeBottom;
    float beSizeLeft;
    float beSizeRight;
    float beTransitionTop;

    float beTransitionBottom;
    float beTransitionLeft;
    float beTransitionRight;
    float structureGlobal;    // -100..100

    float structureHighlights;
    float structureMidtones;
    float structureShadows;
    float fineStructure;      // 0..100

    float _pad0;
    float _pad1;
    float _pad2;
    float _pad3;
};

/// HSV -> RGB for the toning tints (h degrees, s/v 0..1).
inline float3 bwfHSVtoRGB(float h, float s, float v) {
    float c = v * s;
    float hp = fmod(h / 60.0, 6.0);
    float x = c * (1.0 - fabs(fmod(hp, 2.0) - 1.0));
    float3 rgb;
    if (hp < 1.0)      rgb = float3(c, x, 0);
    else if (hp < 2.0) rgb = float3(x, c, 0);
    else if (hp < 3.0) rgb = float3(0, c, x);
    else if (hp < 4.0) rgb = float3(0, x, c);
    else if (hp < 5.0) rgb = float3(x, 0, c);
    else               rgb = float3(c, 0, x);
    return rgb + (v - c);
}

/// One burn-edge contribution: distance-from-edge d (0..1), size sets
/// reach, transition sets softness. Returns the darkening weight 0..1.
inline float bwfBurnEdge(float d, float strength, float size, float transition) {
    if (strength <= 0.0) return 0.0;
    float reach = size / 100.0 * 0.5;
    float soft = max(transition / 100.0 * 0.5, 0.01);
    float w = 1.0 - smoothstep(reach - soft, reach + soft, d);
    return strength / 100.0 * w;
}

/// Weight of hue `h` (degrees) for a basis lobe centered at `center`:
/// triangular falloff over ±60°, so adjacent lobes cross at 0.5 and the
/// six lobes partition the hue circle.
inline float bwfHueLobe(float h, float center) {
    float d = fabs(h - center);
    d = min(d, 360.0 - d);
    return max(0.0, 1.0 - d / 60.0);
}

/// Spectral-sensitivity conversion of one RGB sample to gray — shared by
/// the center pixel and the structure kernel's neighbor samples.
inline float bwfConvertGray(float3 src, constant BWFilmUniforms& uniforms) {
    float mx = max(src.r, max(src.g, src.b));
    float mn = min(src.r, min(src.g, src.b));
    float chroma = mx - mn;
    float g = luminance(src);
    if (chroma > 1e-5) {
        float hue;
        if (mx == src.r)      hue = fmod((src.g - src.b) / chroma, 6.0);
        else if (mx == src.g) hue = (src.b - src.r) / chroma + 2.0;
        else                  hue = (src.r - src.g) / chroma + 4.0;
        hue *= 60.0;
        if (hue < 0.0) hue += 360.0;
        float shift =
            uniforms.sensR  * bwfHueLobe(hue,   0.0) +
            uniforms.sensYe * bwfHueLobe(hue,  60.0) +
            uniforms.sensG  * bwfHueLobe(hue, 120.0) +
            uniforms.sensCy * bwfHueLobe(hue, 180.0) +
            uniforms.sensB  * bwfHueLobe(hue, 240.0) +
            uniforms.sensMg * bwfHueLobe(hue, 300.0);
        // 0.6: full +100 sensitivity on a saturated hue moves it ~60% of
        // the range — comparable to SEP's strongest film responses.
        g += (shift / 100.0) * chroma * 0.6;
    }
    return saturate(g);
}

/// Mean converted gray over a sparse two-ring disc of radius `radius`
/// (uv units). 12 outer + 6 inner samples — a cheap Gaussian-ish blur for
/// the structure unsharp mask, deterministic fixed offsets.
inline float bwfBlurGray(texture2d<float> source, sampler s, float2 uv,
                         float2 radius, constant BWFilmUniforms& uniforms) {
    constexpr float TWO_PI = 6.28318530718;
    float total = 0.0;
    for (int i = 0; i < 12; i++) {
        float a = TWO_PI * (float(i) + 0.5) / 12.0;
        float2 o = float2(cos(a), sin(a)) * radius;
        total += bwfConvertGray(source.sample(s, uv + o).rgb, uniforms);
    }
    for (int i = 0; i < 6; i++) {
        float a = TWO_PI * (float(i) + 0.25) / 6.0;
        float2 o = float2(cos(a), sin(a)) * radius * 0.5;
        total += bwfConvertGray(source.sample(s, uv + o).rgb, uniforms);
    }
    return total / 18.0;
}

fragment float4 bwFilmFragment(
    VertexOut                in         [[stage_in]],
    texture2d<float>         source     [[texture(0)]],
    texture2d<float>         curveLUT   [[texture(1)]],
    sampler                  texSampler [[sampler(0)]],
    constant BWFilmUniforms& uniforms   [[buffer(0)]]
) {
    float2 dims = float2(max(float(source.get_width()), 1.0),
                         max(float(source.get_height()), 1.0));
    int2 pixel = clamp(int2(floor(in.uv * dims)), int2(0), int2(dims) - 1);
    float2 selfUV = (float2(pixel) + 0.5) / dims;
    float3 src = source.sample(texSampler, selfUV).rgb;

    // --- 1. Spectral-sensitivity conversion -----------------------------
    float g = bwfConvertGray(src, uniforms);

    // --- 1.5 Structure (two-scale unsharp mask on the converted gray) ---
    // Radii are fractions of min(w,h) so the effect is proportional at any
    // resolution; sampled with the linear sampler over a sparse disc.
    {
        float minDim = min(dims.x, dims.y);
        // Zone bands match the tonality masks below (widened per the
        // response-curve retune).
        float zoneStructure = uniforms.structureGlobal
            + uniforms.structureShadows   * (1.0 - smoothstep(0.15, 0.55, g))
            + uniforms.structureHighlights * smoothstep(0.45, 0.85, g)
            + uniforms.structureMidtones
              * saturate(1.0 - (1.0 - smoothstep(0.15, 0.55, g)) - smoothstep(0.45, 0.85, g));
        // Same progressive-response retune as the tonality block: the
        // detail term is soft-limited so strong edges can't blow into
        // halos at high settings — small texture detail passes nearly
        // linearly, large deltas roll off.
        if (fabs(zoneStructure) > 0.5) {
            float2 radius = float2(0.012 * minDim) / dims;
            float blurred = bwfBlurGray(source, texSampler, selfUV, radius, uniforms);
            float detail = g - blurred;
            g += zoneStructure / 100.0 * detail / (1.0 + 3.0 * fabs(detail));
        }
        if (uniforms.fineStructure > 0.5) {
            float2 radius = float2(0.0035 * minDim) / dims;
            float blurred = bwfBlurGray(source, texSampler, selfUV, radius, uniforms);
            float detail = g - blurred;
            g += uniforms.fineStructure / 100.0 * 0.8 * detail / (1.0 + 3.0 * fabs(detail));
        }
        g = saturate(g);
    }

    // --- 2. Zone tonality — MEASURED response laws ----------------------
    // Fitted against transfer curves exported from Silver Efex Pro 3
    // itself (gray-ramp chart, GUI-automated exports, 2026-07-19; fitting
    // script tools/sep-measurement/). All SEP tonality ops pin BOTH
    // endpoints — input 0 and 1 never move.
    //
    // Brightness: pure gamma. Positive law exponent = 2^(-b/50) is exact
    // (rms 0.34/255 at +50 and +100); the negative side runs slightly
    // hotter (best fit 2.285 at -50 → asymmetry factor 1.19, rms 7/255).
    float b = uniforms.brightness;
    if (fabs(b) > 0.01) {
        float e = exp2(-b / 50.0 * (b < 0.0 ? 1.19 : 1.0));
        g = pow(g, e);
    }

    // Zone brightness: measured weight functions (delta = slider × w(g)),
    // each fading to exact identity outside its band:
    //   shadows   w = 1.19·g^0.65·(1-g)^5.8   (rms 0.78/255)
    //   midtones  w = 0.79·g^0.80·(1-g)^1.4   (rms 0.75/255)
    //   highlights w = 0.17·g^1.95·(1-g)^0.4  (rms 3.4/255)
    if (g > 1e-6 && g < 1.0 - 1e-6) {
        float d = uniforms.briShadows   / 100.0 * 1.19 * pow(g, 0.65) * pow(1.0 - g, 5.8)
                + uniforms.briMidtones  / 100.0 * 0.79 * pow(g, 0.80) * pow(1.0 - g, 1.4)
                + uniforms.briHighlights / 100.0 * 0.17 * pow(g, 1.95) * pow(1.0 - g, 0.4);
        g = saturate(g + d);
    }

    // Contrast: log-odds sigmoid g^k / (g^k + (1-g)^k) — pins 0, 0.5, 1.
    // Positive law k = 3^(c/100) measured exact (rms 0.76/255 at +50);
    // negative side asymmetry factor 0.86 (best fit k 0.635 at -50).
    float c = uniforms.contrast;
    if (fabs(c) > 0.01 && g > 1e-6 && g < 1.0 - 1e-6) {
        float k = pow(3.0, c / 100.0 * (c < 0.0 ? 0.86 : 1.0));
        float a = pow(g, k);
        g = a / (a + pow(1.0 - g, k));
    }
    g = saturate(g);

    // Soft knees: pull crushed shadows up / blown highlights down.
    g += uniforms.protectShadows / 100.0 * 0.25
       * pow(saturate(1.0 - g / 0.3), 2.0);
    g -= uniforms.protectHighlights / 100.0 * 0.25
       * pow(saturate((g - 0.7) / 0.3), 2.0);
    g = saturate(g);

    // --- 3. Tone curve (baked LUT, linear interp between entries) -------
    float fi = g * 255.0;
    uint i0 = uint(clamp(floor(fi), 0.0, 255.0));
    uint i1 = min(i0 + 1, 255u);
    float t = fi - float(i0);
    float c0 = curveLUT.read(uint2(i0, 0)).r;
    float c1 = curveLUT.read(uint2(i1, 0)).r;
    g = saturate(mix(c0, c1, t));

    // --- 4. Vignette (superellipse falloff; negative strength darkens) --
    float2 pos = (float2(pixel) + 0.5) / dims;
    if (uniforms.vigStrength != 0.0) {
        float2 rel = pos - float2(0.5, 0.5);
        rel.x *= dims.x / dims.y;  // aspect-true circle at shape 2
        float e = clamp(uniforms.vigShape, 1.0, 5.0);
        float d = pow(pow(fabs(rel.x), e) + pow(fabs(rel.y), e), 1.0 / e);
        float radius = uniforms.vigSize / 100.0 * 0.9 + 0.1;
        float fall = smoothstep(radius * 0.55, radius * 1.35, d);
        g = saturate(g * (1.0 + uniforms.vigStrength / 100.0 * fall));
    }

    // --- 5. Burn edges ---------------------------------------------------
    float burn =
        bwfBurnEdge(pos.y,        uniforms.beStrengthTop,    uniforms.beSizeTop,    uniforms.beTransitionTop) +
        bwfBurnEdge(1.0 - pos.y,  uniforms.beStrengthBottom, uniforms.beSizeBottom, uniforms.beTransitionBottom) +
        bwfBurnEdge(pos.x,        uniforms.beStrengthLeft,   uniforms.beSizeLeft,   uniforms.beTransitionLeft) +
        bwfBurnEdge(1.0 - pos.x,  uniforms.beStrengthRight,  uniforms.beSizeRight,  uniforms.beTransitionRight);
    g = saturate(g * (1.0 - min(burn, 1.0) * 0.85));

    // --- 6. Split toning (silver = highlights, paper = shadows) ---------
    float3 outRGB = float3(g);
    if (uniforms.toningStrength > 0.0) {
        float pivot = 0.5 - uniforms.toneBalance / 100.0 * 0.3;
        float hiW = smoothstep(pivot - 0.35, pivot + 0.35, g);
        float3 toneHi = bwfHSVtoRGB(uniforms.toneHueHigh,
                                    uniforms.toneStrengthHigh / 100.0 * 0.8, g);
        float3 toneLo = bwfHSVtoRGB(uniforms.toneHueLow,
                                    uniforms.toneStrengthLow / 100.0 * 0.8, g);
        float3 toned = mix(toneLo, toneHi, hiW);
        outRGB = mix(outRGB, toned, saturate(uniforms.toningStrength / 100.0));
    }

    float3 final = mix(src, outRGB, saturate(uniforms.intensity));
    return float4(final, 1.0);
}
