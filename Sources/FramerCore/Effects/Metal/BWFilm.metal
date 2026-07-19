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
    float _pad0;
    float _pad1;
};

/// Weight of hue `h` (degrees) for a basis lobe centered at `center`:
/// triangular falloff over ±60°, so adjacent lobes cross at 0.5 and the
/// six lobes partition the hue circle.
inline float bwfHueLobe(float h, float center) {
    float d = fabs(h - center);
    d = min(d, 360.0 - d);
    return max(0.0, 1.0 - d / 60.0);
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
    g = saturate(g);

    // --- 2. Zone tonality ----------------------------------------------
    float shMask  = 1.0 - smoothstep(0.25, 0.6, g);
    float hiMask  = smoothstep(0.4, 0.75, g);
    float midMask = saturate(1.0 - shMask - hiMask);

    g += uniforms.brightness / 100.0 * 0.4
       + (uniforms.briShadows   * shMask
        + uniforms.briMidtones  * midMask
        + uniforms.briHighlights * hiMask) / 100.0 * 0.4;

    g = 0.5 + (g - 0.5) * (1.0 + uniforms.contrast / 100.0 * 1.2);
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

    float3 final = mix(src, float3(g), saturate(uniforms.intensity));
    return float4(final, 1.0);
}
