// Kuwahara.metal
// Edge-preserving 4-quadrant Kuwahara filter with optional unsharp-mask
// sharpening. Mirrors ShaderRenderer.applyKuwahara
// (Sources/FramerCore/Processing/ShaderRenderer.swift) — same quadrant layout,
// same variance-of-quadrant-means metric, same sharpness blend formula.
//
// Cost is 4 × (R+1)² source samples per fragment. The CPU clamps R to 15, so
// the worst case is 4 × 256 = 1024 samples — heavy but trivially parallel.
// Driving the GPU at preview resolutions (≈ 1920 × 1080) keeps a ~7 ms budget
// on integrated GPUs.
//
// Sample bounds rely on the bound sampler being clamp-to-edge, so we don't
// need explicit min/max arithmetic; the texture handles edge wrapping.

#include "ShaderCommon.h"

constant int KUWAHARA_MAX_RADIUS = 15;

struct KuwaharaUniforms {
    FramerCommonUniforms common;
    FramerGeometryUniforms geometry;
    FramerColorUniforms colorBlock;     // unused

    float intensity;
    int   kernelSize;       // CPU clamps 1..15
    float sharpness;        // ≥ 0
    float _pad0;
};

fragment float4 kuwaharaFragment(
    VertexOut                  in           [[stage_in]],
    texture2d<float>           source       [[texture(0)]],
    sampler                    texSampler   [[sampler(0)]],
    constant KuwaharaUniforms& uniforms     [[buffer(0)]]
) {
    int radius = clamp(uniforms.kernelSize, 1, KUWAHARA_MAX_RADIUS);
    float sharpness = max(0.0, uniforms.sharpness);

    float2 resolution = float2(source.get_width(), source.get_height());
    float2 invRes     = 1.0 / resolution;
    float2 centerPx   = in.uv * resolution;

    float bestVariance = 1.0e30;
    float3 bestColor   = float3(0.0);

    // Iterate the four quadrants. For each, accumulate sum and sum-of-squares
    // across (radius + 1)² samples (matches CPU's inclusive `startY...endY`
    // ranges that include the centre row/column in every quadrant).
    for (int qy = 0; qy <= 1; qy++) {
        int startY = (qy == 0) ? -radius : 0;
        int endY   = (qy == 0) ?  0      : radius;
        for (int qx = 0; qx <= 1; qx++) {
            int startX = (qx == 0) ? -radius : 0;
            int endX   = (qx == 0) ?  0      : radius;

            float3 sum   = float3(0.0);
            float3 sumSq = float3(0.0);
            float  count = 0.0;

            // Runtime-bounded loop. Capped at the constant max above so the
            // shader compiler can still pre-allocate registers for the worst
            // case rather than deferring the bound to runtime.
            for (int ky = -KUWAHARA_MAX_RADIUS; ky <= KUWAHARA_MAX_RADIUS; ky++) {
                if (ky < startY || ky > endY) { continue; }
                for (int kx = -KUWAHARA_MAX_RADIUS; kx <= KUWAHARA_MAX_RADIUS; kx++) {
                    if (kx < startX || kx > endX) { continue; }
                    float2 sampleUV = (centerPx + float2(float(kx), float(ky))) * invRes;
                    float3 c = source.sample(texSampler, sampleUV).rgb;
                    sum   += c;
                    sumSq += c * c;
                    count += 1.0;
                }
            }

            float3 mean = sum / max(count, 1.0);
            float3 var  = sumSq / max(count, 1.0) - mean * mean;
            float varianceScalar = var.r + var.g + var.b;

            if (varianceScalar < bestVariance) {
                bestVariance = varianceScalar;
                bestColor    = mean;
            }
        }
    }

    // Unsharp mask: blend toward the original sample by sharpness/8 (same
    // factor as the CPU version).
    float3 srcOrig = source.sample(texSampler, in.uv).rgb;
    if (sharpness > 0.0) {
        float factor = sharpness / 8.0;
        bestColor = bestColor + (srcOrig - bestColor) * factor;
    }

    float3 final = mix(srcOrig, saturate(bestColor), saturate(uniforms.intensity));
    return float4(final, 1.0);
}
