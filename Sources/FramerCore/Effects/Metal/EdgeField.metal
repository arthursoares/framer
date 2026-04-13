// EdgeField.metal
// Fragment shader for the EdgeField bucket (edgeDetection / contour /
// waveLines / voronoi / noiseField). Mirrors EdgeFieldRenderer's CPU per-
// pixel algorithms so GPU and CPU produce visually equivalent output at the
// same parameters.
//
// CPU reference: Sources/FramerCore/Effects/Renderers/EdgeFieldRenderer.swift
// Uniform layout mirrors EdgeFieldGPURenderer.Uniforms in the Swift wrapper
// exactly — keep field order and padding identical, or uniforms read garbage.

#include "ShaderCommon.h"

// =============================================================================
// Uniforms
// =============================================================================

struct EdgeFieldUniforms {
    FramerCommonUniforms   common;
    FramerGeometryUniforms geometry;
    FramerColorUniforms    color;

    uint  variant;             // 0 edgeDetection, 1 contour, future: 2 waveLines, 3 voronoi, 4 noiseField
    float intensity;           // 0..1, blend with original
    float lineStrength;        // 0..1
    float thickness;           // 0..1

    float edgeThreshold;       // 0..1, subtracts from edge before shaping (edgeDetection)
    uint  edgeAlgorithm;       // 0 sobel, 1 laplacian (edge multiplier differs)
    uint  invert;              // 0 / 1
    float fieldIntensity;      // 0..1, contour-band modulation

    uint  contourLevels;       // ≥ 2, number of contour bands
    uint  contourFillMode;     // 0 linesOnly, 1 filledBands
    uint  direction;           // 0 horizontal, 1 vertical (waveLines)
    float amplitude;           // 0..1, waveLines source phase contribution

    float frequency;           // waveLines spatial-phase multiplier
    float lineCount;           // reserved for waveLines density boost
    float spacing;             // pixel spacing for waveLines (pre-computed)
    float cellSize;            // voronoi cell pitch (pixels)

    float edgeWidth;           // voronoi edge ring width (0..1)
    uint  randomize;           // voronoi per-cell seed jitter (0 / 1)
    float fieldWeight;         // voronoi/noiseField "field" multiplier (== fieldIntensity)
    uint  octaves;             // noiseField octaves (1..6)

    float4 edgeColor;          // colour for ink pixels (rgba, a unused)
};

// =============================================================================
// EDGE DETECTION — per-pixel Sobel-like gradient magnitude, thresholded and
// shaped by lineStrength/thickness. Matches CPU `edgeMagnitude`'s 4-tap
// approximation (|right-left| + |down-up|) rather than a full 3x3 Sobel —
// visibly the same at preview resolutions and half the sample count.
// =============================================================================

static float4 edgeDetectionVariant(
    VertexOut                    in,
    texture2d<float>             source,
    sampler                      texSampler,
    constant EdgeFieldUniforms&  u
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    float2 invRes     = 1.0 / resolution;
    int2   pixel      = clamp(int2(floor(in.uv * resolution)),
                              int2(0), int2(resolution) - 1);
    float2 selfUV     = (float2(pixel) + 0.5) / resolution;

    // 4-tap edge magnitude. Clamp-to-edge sampler handles out-of-bounds reads
    // so we don't need explicit neighbour clamping in the shader.
    float3 srcOrig = source.sample(texSampler, selfUV).rgb;
    float lC = luminance(srcOrig);
    float lL = luminance(source.sample(texSampler, selfUV + float2(-1, 0) * invRes).rgb);
    float lR = luminance(source.sample(texSampler, selfUV + float2( 1, 0) * invRes).rgb);
    float lU = luminance(source.sample(texSampler, selfUV + float2( 0,-1) * invRes).rgb);
    float lD = luminance(source.sample(texSampler, selfUV + float2( 0, 1) * invRes).rgb);
    (void)lC;
    float edge = saturate(abs(lR - lL) + abs(lD - lU));

    // Apply algorithm multiplier then the CPU's threshold + shaping formula.
    float algMult    = (u.edgeAlgorithm == 1u) ? 1.35 : 1.0;
    float thresholded = max(0.0, edge * algMult - u.edgeThreshold);
    float shaped     = thresholded * max(0.5, u.lineStrength / max(0.05, u.thickness));
    float value      = saturate(shaped);
    if (u.invert == 1u) { value = 1.0 - value; }

    // Colourise: value drives the ink contribution; edgeColor tints it.
    // colour.mode=1 (foregroundBackground) uses (value, value, backgroundIntensity)
    // per CPU's per-variant mapping; other modes use a monochrome
    // max(background, value) fill.
    float3 ink;
    if (u.color.mode == 1u) {
        ink = float3(value, value, u.color.backgroundIntensity);
    } else {
        float bg = u.color.backgroundIntensity;
        ink = float3(max(bg, value));
    }

    // Optional per-variant colour tint from TextCellParameters-style edgeColor.
    // If provided as non-default, multiply into the ink contribution.
    if (u.edgeColor.r + u.edgeColor.g + u.edgeColor.b > 0.0) {
        ink *= u.edgeColor.rgb;
    }

    float3 final = mix(srcOrig, saturate(ink), saturate(u.intensity));
    return float4(final, 1.0);
}

// =============================================================================
// CONTOUR — quantize source luminance into N bands, render band boundaries as
// lines. Two modes: linesOnly renders lines at full brightness over a dim
// background, filledBands renders each band at its quantized luminance with
// brighter line strokes.
// =============================================================================

static float4 contourVariant(
    VertexOut                    in,
    texture2d<float>             source,
    sampler                      texSampler,
    constant EdgeFieldUniforms&  u
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    int2   pixel      = clamp(int2(floor(in.uv * resolution)),
                              int2(0), int2(resolution) - 1);
    float2 selfUV     = (float2(pixel) + 0.5) / resolution;
    float3 srcOrig    = source.sample(texSampler, selfUV).rgb;

    float lum       = saturate(luminance(srcOrig));
    int   levels    = max(2, int(u.contourLevels));
    float quantized = floor(lum * float(levels)) / float(levels);
    float band      = fract(quantized * max(0.01, u.fieldIntensity) * float(levels));

    float value;
    if (u.contourFillMode == 1u) {
        // filledBands
        float lineWidth = max(0.04, u.lineStrength * u.thickness * 0.25);
        bool  isLine    = band < lineWidth;
        float bandValue = u.invert == 1u ? (1.0 - quantized) : quantized;
        float lineValue = min(1.0, bandValue + u.lineStrength * 0.18);
        value = isLine ? lineValue : bandValue;
    } else {
        // linesOnly
        float lineWidth = max(0.04, u.lineStrength * u.thickness * 0.4);
        bool  isLine    = band < lineWidth;
        float dim       = (u.invert == 1u) ? (1.0 - lum) : lum * 0.15;
        value = isLine ? 1.0 : dim;
    }
    value = saturate(value);

    // Colour mapping: default is monochrome max(background, value); edgeColor
    // tint multiplied in when set.
    float bg = u.color.backgroundIntensity;
    float3 ink = float3(max(bg, value));
    if (u.edgeColor.r + u.edgeColor.g + u.edgeColor.b > 0.0) {
        ink *= u.edgeColor.rgb;
    }

    float3 final = mix(srcOrig, saturate(ink), saturate(u.intensity));
    return float4(final, 1.0);
}

// =============================================================================
// WAVE LINES — source-modulated sinusoidal line bands along one axis. Phase
// = axis / spacing * frequency + sourceLum * π * amplitude. Lines render where
// |sin(phase)| < threshold, determined by thickness * lineStrength.
// =============================================================================

static float4 waveLinesVariant(
    VertexOut                    in,
    texture2d<float>             source,
    sampler                      texSampler,
    constant EdgeFieldUniforms&  u
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    int2   pixel      = clamp(int2(floor(in.uv * resolution)),
                              int2(0), int2(resolution) - 1);
    float2 selfUV     = (float2(pixel) + 0.5) / resolution;
    float3 srcOrig    = source.sample(texSampler, selfUV).rgb;

    float lum     = saturate(luminance(srcOrig));
    float axis    = (u.direction == 1u) ? float(pixel.x) : float(pixel.y);
    float spacing = max(1.0, u.spacing);
    float freq    = max(0.1, u.frequency);
    float amp     = max(0.1, u.amplitude);

    float phase     = (axis / spacing) * freq;
    float wave      = sin(phase + lum * M_PI_F * amp);
    float threshold = max(0.03, u.thickness * max(0.1, u.lineStrength));
    float value     = (fabs(wave) < threshold) ? 1.0 : (lum * 0.15);
    if (u.invert == 1u) { value = 1.0 - value; }
    value = saturate(value);

    float bg = u.color.backgroundIntensity;
    float3 ink = float3(max(bg, value));
    if (u.edgeColor.r + u.edgeColor.g + u.edgeColor.b > 0.0) {
        ink *= u.edgeColor.rgb;
    }

    float3 final = mix(srcOrig, saturate(ink), saturate(u.intensity));
    return float4(final, 1.0);
}

// =============================================================================
// VORONOI — 9-neighbourhood cellular pattern. For each fragment, searches the
// 3x3 grid of candidate cell-centre "seeds" (optionally jittered per-cell)
// and tracks the nearest and second-nearest seed distances. Edges where the
// two are close (cell boundaries) render bright; interiors render darker
// with a radial falloff from the nearest seed. Produces the classic Voronoi
// mosaic look — distinct polygonal cells with visible walls.
// =============================================================================

static float4 voronoiVariant(
    VertexOut                    in,
    texture2d<float>             source,
    sampler                      texSampler,
    constant EdgeFieldUniforms&  u
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    int2   pixel      = clamp(int2(floor(in.uv * resolution)),
                              int2(0), int2(resolution) - 1);
    float2 selfUV     = (float2(pixel) + 0.5) / resolution;
    float3 srcOrig    = source.sample(texSampler, selfUV).rgb;

    float cellPitch = max(2.0, u.cellSize);
    float2 p       = float2(pixel);
    float2 cellId  = floor(p / cellPitch);

    // Search the 3x3 neighbourhood of candidate seeds. Each cell's seed is at
    // (cellId + 0.5 + jitter) * cellPitch. When `randomize` is on we add
    // deterministic per-cell offsets to break the grid-aligned look.
    float nearest       = 1.0e10;
    float secondNearest = 1.0e10;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 neighborId = cellId + float2(float(i), float(j));
            float2 seedOffset = float2(0.5);
            if (u.randomize == 1u) {
                // Deterministic-per-cell jitter within 0..1 so seeds stay inside
                // their own cell (avoids holes when a seed escapes outside).
                float hx = fract(sin(dot(neighborId, float2(127.1, 311.7))) * 43758.5453);
                float hy = fract(sin(dot(neighborId, float2(269.5,  183.3))) * 43758.5453);
                seedOffset = float2(0.1 + hx * 0.8, 0.1 + hy * 0.8);
            }
            float2 seedPos = (neighborId + seedOffset) * cellPitch;
            float  d       = length(p - seedPos);
            if (d < nearest) {
                secondNearest = nearest;
                nearest       = d;
            } else if (d < secondNearest) {
                secondNearest = d;
            }
        }
    }

    // Cell-edge detection: where nearest and second-nearest are close, we're
    // on a boundary between two cells. `edgeWidth` tunes the wall thickness
    // relative to cell pitch.
    float edgeGap   = (secondNearest - nearest) / cellPitch;
    float edgeWidth = max(0.01, u.edgeWidth);
    float wall      = 1.0 - smoothstep(0.0, edgeWidth, edgeGap);

    // Interior falloff: bright at the seed, fading to the wall.
    float interior = 1.0 - saturate(nearest / (cellPitch * 0.6));

    float value = saturate(wall * u.lineStrength + interior * u.fieldWeight * 0.6);
    if (u.invert == 1u) { value = 1.0 - value; }

    float bg = u.color.backgroundIntensity;
    float3 ink = float3(max(bg, value));
    if (u.edgeColor.r + u.edgeColor.g + u.edgeColor.b > 0.0) {
        ink *= u.edgeColor.rgb;
    }

    float3 final = mix(srcOrig, saturate(ink), saturate(u.intensity));
    return float4(final, 1.0);
}

// =============================================================================
// NOISE FIELD — multi-octave procedural noise. Sum N octaves of IGN (see
// ShaderCommon.h) at doubling frequencies with halving weights to produce
// FBM-style output. `octaves` (1..6) drives the detail depth; `amplitude`
// tunes the base spatial frequency; `fieldWeight` biases the output level.
// =============================================================================

static float4 noiseFieldVariant(
    VertexOut                    in,
    texture2d<float>             source,
    sampler                      texSampler,
    constant EdgeFieldUniforms&  u
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    int2   pixel      = clamp(int2(floor(in.uv * resolution)),
                              int2(0), int2(resolution) - 1);
    float2 selfUV     = (float2(pixel) + 0.5) / resolution;
    float3 srcOrig    = source.sample(texSampler, selfUV).rgb;

    // `amplitude` (0..1 from the UI) → base spatial period in pixels. Smaller
    // amplitude = tighter noise grain. `120.0` keeps the default (amp=0.5) at
    // a ~60-pixel base period, which reads as recognisable "big splotches"
    // at common preview sizes.
    float baseScale = max(1.0, u.amplitude * 120.0);
    int   octaves   = clamp(int(u.octaves), 1, 6);
    float accumulated = 0.0;
    float weightSum   = 0.0;
    float2 p = float2(pixel) / baseScale;
    for (int o = 0; o < 6; o++) {
        if (o >= octaves) { break; }
        float oct    = exp2(float(o));
        float weight = 1.0 / oct;
        accumulated += ign(p * oct) * weight;
        weightSum   += weight;
    }
    float noise = accumulated / max(weightSum, 0.0001);
    float value = saturate(noise * u.lineStrength + u.fieldWeight * 0.3);
    if (u.invert == 1u) { value = 1.0 - value; }

    float bg = u.color.backgroundIntensity;
    float3 ink = float3(max(bg, value));
    if (u.edgeColor.r + u.edgeColor.g + u.edgeColor.b > 0.0) {
        ink *= u.edgeColor.rgb;
    }

    float3 final = mix(srcOrig, saturate(ink), saturate(u.intensity));
    return float4(final, 1.0);
}

// =============================================================================
// Fragment entry — dispatch on variant.
// =============================================================================

fragment float4 edgeFieldFragment(
    VertexOut                    in         [[stage_in]],
    texture2d<float>             source     [[texture(0)]],
    sampler                      texSampler [[sampler(0)]],
    constant EdgeFieldUniforms&  uniforms   [[buffer(0)]]
) {
    switch (uniforms.variant) {
        case 0:  return edgeDetectionVariant(in, source, texSampler, uniforms);
        case 1:  return contourVariant(in, source, texSampler, uniforms);
        case 2:  return waveLinesVariant(in, source, texSampler, uniforms);
        case 3:  return voronoiVariant(in, source, texSampler, uniforms);
        case 4:  return noiseFieldVariant(in, source, texSampler, uniforms);
        default: return source.sample(texSampler, in.uv);
    }
}
