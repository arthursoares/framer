// Halftone.metal
// CMYK halftone (rotated dot screens per channel) with an optional monochrome
// mode. Mirrors ShaderRenderer.applyHalftone (Sources/FramerCore/Processing/
// ShaderRenderer.swift) — same dot-pattern function, same rotation angles, same
// CMY-to-RGB conversion.
//
// Reference angles (radians) come straight from the CPU implementation:
//   cyan = 15°, magenta = 75°, yellow = 0°, black = 45°
//
// The halftone "dot" function intentionally uses sums of sines (cheap, no
// distance fields) rather than a true round-dot Bourke pattern — matches the
// CPU look exactly.

#include "ShaderCommon.h"

struct HalftoneUniforms {
    FramerCommonUniforms common;
    FramerGeometryUniforms geometry;
    FramerColorUniforms colorBlock;     // unused

    float intensity;
    float dotSize;          // ≥ 0.1
    float halftoneContrast; // ≥ 0.1
    uint  monochrome;       // 0 / 1

    float widthPx;
    float heightPx;
    float _pad0;
    float _pad1;
};

constant float HALFTONE_CYAN_ANGLE    = 0.261799;     // 15°
constant float HALFTONE_MAGENTA_ANGLE = 1.309;        // 75°
constant float HALFTONE_BLACK_ANGLE   = 0.785398;     // 45°
// yellow uses 0° (no rotation).

inline float halftonePattern(float ux, float uy, float wf, float hf,
                             float dotSize, float contrastExp, float value) {
    float pattern = (sin(ux * wf * dotSize) + sin(uy * hf * dotSize)) * 0.5;
    return (pattern < pow(saturate(value), contrastExp)) ? 1.0 : 0.0;
}

inline float2 halftoneRotate(float ux, float uy, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(ux * c - uy * s, ux * s + uy * c);
}

fragment float4 halftoneFragment(
    VertexOut                  in           [[stage_in]],
    texture2d<float>           source       [[texture(0)]],
    sampler                    texSampler   [[sampler(0)]],
    constant HalftoneUniforms& uniforms     [[buffer(0)]]
) {
    float wf = max(uniforms.widthPx, 1.0);
    float hf = max(uniforms.heightPx, 1.0);
    float dotSize = max(uniforms.dotSize, 0.1);
    float contrastExp = max(uniforms.halftoneContrast, 0.1);

    // Pin to the integer pixel grid so the halftone phase math matches CPU's
    // `ux = x / width`, `uy = y / height` exactly. Without this, `in.uv` at
    // fragment centers introduces a half-texel phase shift, and the halftone
    // dot pattern (a sin() of `ux * wf * dotSize`) drifts ~half a dot relative
    // to CPU. Mean delta on the parity test was 32/255 before this fix.
    float2 resolution = float2(wf, hf);
    int2   pixel      = int2(floor(in.uv * resolution));
    pixel = clamp(pixel, int2(0), int2(resolution) - 1);
    float ux = float(pixel.x) / wf;
    float uy = float(pixel.y) / hf;
    float2 selfUV = (float2(pixel) + 0.5) / resolution;

    float3 src = source.sample(texSampler, selfUV).rgb;

    float3 outRGB;
    if (uniforms.monochrome == 1u) {
        float lum = luminance(src);
        float2 rot = halftoneRotate(ux, uy, HALFTONE_BLACK_ANGLE);
        float dot = halftonePattern(rot.x, rot.y, wf, hf, dotSize, contrastExp, lum);
        outRGB = float3(dot);
    } else {
        // CMYK separation. Black channel = min ink under each colour.
        float k = min(1.0 - src.r, min(1.0 - src.g, 1.0 - src.b));
        float invK = 1.0 - k;
        float c_val = 0.0, m_val = 0.0, y_val = 0.0;
        if (invK > 0.001) {
            c_val = (1.0 - src.r - k) / invK;
            m_val = (1.0 - src.g - k) / invK;
            y_val = (1.0 - src.b - k) / invK;
        }

        float2 cRot = halftoneRotate(ux, uy, HALFTONE_CYAN_ANGLE);
        float cDot = halftonePattern(cRot.x, cRot.y, wf, hf, dotSize, contrastExp, c_val);

        float2 mRot = halftoneRotate(ux, uy, HALFTONE_MAGENTA_ANGLE);
        float mDot = halftonePattern(mRot.x, mRot.y, wf, hf, dotSize, contrastExp, m_val);

        float yDot = halftonePattern(ux, uy, wf, hf, dotSize, contrastExp, y_val);

        float2 kRot = halftoneRotate(ux, uy, HALFTONE_BLACK_ANGLE);
        float kDot = halftonePattern(kRot.x, kRot.y, wf, hf, dotSize, contrastExp, k);

        outRGB = saturate(float3(1.0 - cDot - kDot,
                                 1.0 - mDot - kDot,
                                 1.0 - yDot - kDot));
    }

    float3 final = mix(src, outRGB, saturate(uniforms.intensity));
    return float4(final, 1.0);
}
