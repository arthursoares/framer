// PixelSort.metal
// Single-pass fragment-shader pixel sort. Each fragment independently locates
// its enclosing "sortable" span, samples up to 24 evenly-spaced positions
// across the span, bubble-sorts that local array by luminance, and returns the
// colour at this fragment's proportional position in the sorted sequence.
//
// The fragment-per-pixel approach (vs. a serial row sweep) is the trick from
// Grainrad's `pixel-sort__GS__L16326.wgsl`, documented in
// /home/user/grainrad/notes/pixel-sort.md. No Grainrad code is copied — the
// MSL below is written fresh against the documented design.
//
// CPU reference: ShaderPixelSortRenderer.apply
// (Sources/FramerCore/Processing/ShaderPixelSortRenderer.swift). This shader
// matches the CPU's semantics:
//   - Span criterion: luminance ≥ threshold (continues a run; below threshold
//     ends it). The CPU's `currentLuminance >= threshold` predicate.
//   - Sort criterion: luminance ascending.
//   - Direction: horizontal or vertical (no diagonal yet).
//   - Span size cap: clamped 1..256, matches CPU `max(1, min(256, span))`.
//   - Output blend: `mix(original, sorted, intensity)` where intensity =
//     params.intensity * pixelSortParams.amount (Swift pre-multiplies).
//
// The 24-sample cap (SAMPLE_COUNT) means spans longer than 24 pixels become
// sub-sampled — CPU sorts every pixel exactly. For typical short spans (≤ 24,
// which is Framer's default) outputs match within fp tolerance. For long
// deliberate streaks, prefer the CPU export path. See migration plan.

#include "ShaderCommon.h"

constant int PIXEL_SORT_SAMPLE_COUNT = 24;
constant int PIXEL_SORT_MAX_WALK = 256;     // matches CPU `min(256, span)` cap

struct PixelSortUniforms {
    FramerCommonUniforms common;
    FramerGeometryUniforms geometry;
    FramerColorUniforms colorBlock;     // unused

    float intensity;        // pre-multiplied (params.intensity * amount)
    float threshold;        // 0..1
    uint  direction;        // 0 horizontal, 1 vertical
    int   spanCap;          // 1..PIXEL_SORT_MAX_WALK

    float widthPx;
    float heightPx;
    float _pad0;
    float _pad1;
};

// Sample helpers — pixel-coordinate access through the bound sampler. The
// sampler is clamp-to-edge so out-of-bounds reads silently fold to the border;
// we still test bounds explicitly when walking so the span stops at the image
// edge instead of repeating the border colour.
inline float3 psSampleAt(texture2d<float> source, sampler s,
                         int2 px, float2 invRes) {
    float2 uv = (float2(px) + 0.5) * invRes;
    return source.sample(s, uv).rgb;
}

inline float psLuminance(float3 c) {
    return luminance(c);
}

inline bool psInBounds(int2 px, int2 res) {
    return px.x >= 0 && px.y >= 0 && px.x < res.x && px.y < res.y;
}

fragment float4 pixelSortFragment(
    VertexOut                  in           [[stage_in]],
    texture2d<float>           source       [[texture(0)]],
    sampler                    texSampler   [[sampler(0)]],
    constant PixelSortUniforms& uniforms    [[buffer(0)]]
) {
    int2 res = int2(int(uniforms.widthPx), int(uniforms.heightPx));
    float2 invRes = 1.0 / float2(res);
    int2 px = int2(in.uv * float2(res));
    px = clamp(px, int2(0), res - int2(1));

    int2 dir = (uniforms.direction == 0u) ? int2(1, 0) : int2(0, 1);

    float3 currentColor = psSampleAt(source, texSampler, px, invRes);
    float  currentLum   = psLuminance(currentColor);
    float  threshold    = saturate(uniforms.threshold);
    int    spanCap      = clamp(uniforms.spanCap, 1, PIXEL_SORT_MAX_WALK);

    // If this pixel itself is below threshold, it can never be part of a
    // sortable span (CPU walks past it without including it). Return source.
    if (currentLum < threshold) {
        return float4(currentColor, 1.0);
    }

    // ---- Walk backward to locate the span start -----------------------------
    // The CPU sweep would have started a span at the first pixel above
    // threshold and walked forward up to `span`. Mirror that here by walking
    // back from this fragment until we hit either:
    //   - a below-threshold pixel (span boundary),
    //   - the image edge,
    //   - or `spanCap - 1` steps (span size limit).
    int back = 0;
    int maxBack = spanCap - 1;
    for (int i = 1; i <= PIXEL_SORT_MAX_WALK; i++) {
        if (i > maxBack) { break; }
        int2 q = px - dir * i;
        if (!psInBounds(q, res)) { break; }
        float3 c = psSampleAt(source, texSampler, q, invRes);
        if (psLuminance(c) < threshold) { break; }
        back = i;
    }

    // ---- Walk forward to locate the span end -------------------------------
    int forward = 0;
    int maxForward = (spanCap - 1) - back;
    for (int i = 1; i <= PIXEL_SORT_MAX_WALK; i++) {
        if (i > maxForward) { break; }
        int2 q = px + dir * i;
        if (!psInBounds(q, res)) { break; }
        float3 c = psSampleAt(source, texSampler, q, invRes);
        if (psLuminance(c) < threshold) { break; }
        forward = i;
    }

    int spanSize = back + forward + 1;
    if (spanSize < 2) {
        return float4(currentColor, 1.0);
    }

    // ---- Sample up to SAMPLE_COUNT positions across the span ---------------
    // For spans ≤ SAMPLE_COUNT we read every pixel (parity with CPU). For
    // longer spans we read a strided subset and the rank lookup interpolates.
    int   count = min(spanSize, PIXEL_SORT_SAMPLE_COUNT);
    int2  spanStart = px - dir * back;

    float3 colors[PIXEL_SORT_SAMPLE_COUNT];
    float  lums[PIXEL_SORT_SAMPLE_COUNT];
    for (int i = 0; i < PIXEL_SORT_SAMPLE_COUNT; i++) {
        if (i >= count) { break; }
        int offset;
        if (count == spanSize) {
            offset = i;
        } else {
            // Stride sampling: position i of count maps to span offset
            // round(i * (spanSize - 1) / (count - 1)).
            offset = int(round(float(i) * float(spanSize - 1) / float(count - 1)));
        }
        offset = clamp(offset, 0, spanSize - 1);
        int2 q = spanStart + dir * offset;
        float3 c = psSampleAt(source, texSampler, q, invRes);
        colors[i] = c;
        lums[i]   = psLuminance(c);
    }

    // ---- Bubble sort (ascending by luminance) -------------------------------
    // Bounded by SAMPLE_COUNT so the loop is fully unrollable. ~276 ops worst
    // case at SAMPLE_COUNT = 24 — fits in registers, no scratch memory.
    for (int i = 0; i < PIXEL_SORT_SAMPLE_COUNT - 1; i++) {
        if (i >= count - 1) { break; }
        for (int j = 0; j < PIXEL_SORT_SAMPLE_COUNT - 1; j++) {
            if (j >= count - 1 - i) { break; }
            if (lums[j] > lums[j + 1]) {
                float3 tc = colors[j]; colors[j] = colors[j + 1]; colors[j + 1] = tc;
                float  tl = lums[j];   lums[j]   = lums[j + 1];   lums[j + 1]   = tl;
            }
        }
    }

    // ---- Map this fragment's span position to a sorted index ---------------
    int posInSpan = back;   // we walked `back` steps to reach the span start.
    int sortedIdx;
    if (count == spanSize) {
        sortedIdx = posInSpan;
    } else {
        sortedIdx = int(round(float(posInSpan) * float(count - 1) / float(spanSize - 1)));
    }
    sortedIdx = clamp(sortedIdx, 0, count - 1);

    float3 sortedColor = colors[sortedIdx];

    // ---- Final blend with the original by intensity ------------------------
    float3 final = mix(currentColor, sortedColor, saturate(uniforms.intensity));
    return float4(final, 1.0);
}
