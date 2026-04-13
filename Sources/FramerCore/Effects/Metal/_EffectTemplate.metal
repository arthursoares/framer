// _EffectTemplate.metal
// Blank skeleton for a new effect-bucket shader.
// Copy this file, rename to <Bucket>.metal, fill in TODOs.
//
// Intended to be used as the starting point for:
//   - PrintSampling.metal (Dithering, Halftone, Threshold, Crosshatch)
//   - EdgeField.metal     (Contour, Edge Detection, Wave Lines, Voronoi, Noise Field)
//   - Glitch.metal        (Pixel Sort, VHS)
//
// Attribution: any Grainrad-studied technique must be cited at the top of the
// resulting file. Match the header pattern in TextCell.metal.

#include "ShaderCommon.h"

// =============================================================================
// TODO: define <Bucket>Uniforms struct here.
// Mirror the Swift struct in Sources/FramerCore/Effects/Models/GPUEffectParameters.swift.
// Keep field order and padding identical, or uniforms read garbage.
// =============================================================================

struct __BucketUniforms {
    FramerCommonUniforms   common;
    FramerGeometryUniforms geometry;
    FramerColorUniforms    color;

    uint variant;   // 0, 1, 2, ... mapping to variant enum (e.g. PrintSamplingVariant)
    // TODO: add bucket-specific fields
    float3 _pad;    // keep 16-byte aligned
};

// =============================================================================
// Main fragment — dispatch on variant. Keep this tiny; real work lives in
// per-variant inline helpers below.
// =============================================================================

fragment float4 __bucketFragment(
    VertexOut                    in       [[stage_in]],
    texture2d<float>             source   [[texture(0)]],
    sampler                      texSampler [[sampler(0)]],
    constant __BucketUniforms&  uniforms [[buffer(0)]]
) {
    switch (uniforms.variant) {
        // TODO: case 0: return variantA(in, source, texSampler, uniforms);
        // TODO: case 1: return variantB(in, source, texSampler, uniforms);
        default: return source.sample(texSampler, in.uv);  // passthrough
    }
}

// =============================================================================
// TODO: per-variant inline helpers.
//
// Pattern (from TextCell.metal::dotsVariant):
//   1. Compute target geometry (cell center, grid snap, etc.)
//   2. Sample source at an appropriate UV (center of cell, current pixel, or neighbours)
//   3. Adjust (brightness/contrast/gamma) using the FramerCommonUniforms helpers
//   4. Compute the per-pixel decision (in-shape? threshold? sort-order?)
//   5. Select color from {source, grayscale, foreground-tinted, background}
//   6. Return float4(color, 1.0)
// =============================================================================

// inline float4 variantA(
//     VertexOut                    in,
//     texture2d<float>             source,
//     sampler                      texSampler,
//     constant __BucketUniforms&  u
// ) {
//     // implementation
// }
