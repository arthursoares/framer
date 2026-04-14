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
    uint  direction;        // 0 horizontal, 1 vertical, 2 diagonal
    int   spanCap;          // 1..PIXEL_SORT_MAX_WALK

    float widthPx;
    float heightPx;
    uint  spanMode;         // 0 luminance, 1 kimBlack, 2 kimWhite, 3 kimBright, 4 kimDark
    uint  reverse;          // 0/1 — descending sort when 1

    float randomness;       // 0..1 — per-line threshold jitter
    uint  sortBy;           // 0 luminance, 1 brightness=max(r,g,b), 2 hue
    float _pad0;
    float _pad1;
};

// Mode 0 is luminance (the default); referenced implicitly via switch
// `default:`. The Kim-Asendorf modes below need explicit constants for
// clarity in the per-mode passthrough logic.
constant uint PS_MODE_KIM_BLACK = 1u;
constant uint PS_MODE_KIM_WHITE = 2u;
constant uint PS_MODE_KIM_BRIGHT = 3u;
constant uint PS_MODE_KIM_DARK = 4u;

// Direction 0 is horizontal (default); vertical + diagonal need explicit
// constants for the axis-selection branches.
constant uint PS_DIR_VERTICAL = 1u;
constant uint PS_DIR_DIAGONAL = 2u;

// Sort criterion — what value pixels are RANKED by inside a span (orthogonal
// to the span-detection mode above). 0 = luminance (Rec.601) is the default
// and matches Framer's pre-refactor behaviour; 1 = max(r,g,b) aka
// "brightness" in Kim Asendorf's sketch preserves saturated colours better;
// 2 = HSV hue angle produces the characteristic rainbow-sorted streaks.
constant uint PS_SORT_BRIGHTNESS = 1u;
constant uint PS_SORT_HUE        = 2u;

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

// Span predicate. Mirrors the CPU isInSpan() exactly. `effective` is the
// per-line jittered threshold (already adjusted for randomness).
inline bool psInSpan(float3 c, float effective, uint mode) {
    switch (mode) {
        case PS_MODE_KIM_BLACK:
            return luminance(c) > effective * 0.25;
        case PS_MODE_KIM_WHITE:
            return luminance(c) < (1.0 - effective * 0.25);
        case PS_MODE_KIM_BRIGHT:
            return maxRGB(c) > effective;
        case PS_MODE_KIM_DARK:
            return maxRGB(c) < effective;
        default:
            return luminance(c) >= effective;
    }
}

// Sort criterion — orthogonal to span mode. Default luminance matches the
// shader's prior behaviour so existing presets without an explicit `sortBy`
// keep producing identical output. Brightness = max(r,g,b) preserves
// saturated colours during the sort (a deliberately-different look from
// luminance). Hue sorts pixels by their HSV angle, producing the classic
// rainbow-streak effect when applied to varied-hue spans.
inline float psSortValue(float3 c, uint sortBy) {
    switch (sortBy) {
        case PS_SORT_BRIGHTNESS:
            return maxRGB(c);
        case PS_SORT_HUE: {
            // Standard HSV hue derivation — returns 0..1 matching
            // atan2(√3·(G-B), 2R-G-B) / (2π). Cheap enough for a per-pixel
            // sort-key evaluation (runs at most 24 times per fragment via
            // the local sort loop).
            float cMax = max(c.r, max(c.g, c.b));
            float cMin = min(c.r, min(c.g, c.b));
            float delta = cMax - cMin;
            if (delta < 1e-5) { return 0.0; }
            float h;
            if      (cMax == c.r) { h = (c.g - c.b) / delta; }
            else if (cMax == c.g) { h = 2.0 + (c.b - c.r) / delta; }
            else                  { h = 4.0 + (c.r - c.g) / delta; }
            h /= 6.0;
            return (h < 0.0) ? (h + 1.0) : h;
        }
        default:
            return luminance(c);
    }
}

// Per-line jitter: same recipe the CPU function uses
// (sin(lineCoord * 0.173) * 43758.5453, fract). Stable line-coord →
// stable threshold → no shimmer between renders.
inline float psJitteredThreshold(float baseThreshold, int lineCoord, float randomness) {
    if (randomness <= 0.0) { return baseThreshold; }
    float raw = sin(float(lineCoord) * 0.173) * 43758.5453;
    float frac = raw - floor(raw);
    return saturate(baseThreshold * (1.0 + (frac - 0.5) * randomness * 0.5));
}

// Direction setup: returns the unit step (in integer pixels) and computes the
// `lineCoord` that lines stay constant on. Diagonal uses the anti-diagonal
// `dir = (1, 1)` and `lineCoord = floor(x - y)`.
inline void psPickDirection(uint direction, int2 pixel,
                            thread int2& dir, thread int& lineCoord) {
    if (direction == PS_DIR_VERTICAL) {
        dir = int2(0, 1);
        lineCoord = pixel.x;
    } else if (direction == PS_DIR_DIAGONAL) {
        dir = int2(1, 1);
        lineCoord = pixel.x - pixel.y;
    } else {
        dir = int2(1, 0);
        lineCoord = pixel.y;
    }
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

    int2 dir;
    int  lineCoord;
    psPickDirection(uniforms.direction, px, dir, lineCoord);

    int   spanCap     = clamp(uniforms.spanCap, 1, PIXEL_SORT_MAX_WALK);
    float effective   = psJitteredThreshold(saturate(uniforms.threshold),
                                            lineCoord, saturate(uniforms.randomness));

    float3 currentColor = psSampleAt(source, texSampler, px, invRes);

    // If this pixel itself doesn't satisfy the span predicate, it can't be
    // part of a sort run. Return the source colour unchanged so the CPU's
    // "walk past it" semantics are preserved.
    if (!psInSpan(currentColor, effective, uniforms.spanMode)) {
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
        if (!psInSpan(c, effective, uniforms.spanMode)) { break; }
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
        if (!psInSpan(c, effective, uniforms.spanMode)) { break; }
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
        lums[i]   = psSortValue(c, uniforms.sortBy);
    }

    // ---- Bubble sort (ascending or descending by luminance) ---------------
    // Bounded by SAMPLE_COUNT so the loop is fully unrollable. ~276 ops worst
    // case at SAMPLE_COUNT = 24 — fits in registers, no scratch memory.
    bool descending = (uniforms.reverse == 1u);
    for (int i = 0; i < PIXEL_SORT_SAMPLE_COUNT - 1; i++) {
        if (i >= count - 1) { break; }
        for (int j = 0; j < PIXEL_SORT_SAMPLE_COUNT - 1; j++) {
            if (j >= count - 1 - i) { break; }
            bool needSwap = descending
                ? (lums[j] < lums[j + 1])
                : (lums[j] > lums[j + 1]);
            if (needSwap) {
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
