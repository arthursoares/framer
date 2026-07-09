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
    float lineCount;           // waveLines density boost: countFactor = lineCount/spacing
    float spacing;             // pixel spacing for waveLines (pre-computed)
    float cellSize;            // voronoi cell pitch (pixels)

    float edgeWidth;           // voronoi edge ring width (0..1)
    uint  randomize;           // voronoi per-cell seed jitter (0 / 1)
    float fieldWeight;         // voronoi/noiseField "field" multiplier (== fieldIntensity)
    uint  octaves;             // noiseField octaves (1..6)

    float4 edgeColor;          // colour for ink pixels (rgba, a unused)

    uint  noiseType;           // 0 value/IGN, 1 simplex, 2 cellular
    float _pad0;
    float _pad1;
    float _pad2;
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
    float3 srcOrig = applyCommonAdjustments(source.sample(texSampler, selfUV).rgb, u.common);
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
    } else if (u.color.mode == 3u) {
        // Palette: quantize the edge-intensity ramp to the nearest
        // palette entries (posterized edge bands).
        float bg = u.color.backgroundIntensity;
        ink = framerPalettePick(float3(max(bg, value)), u.color);
    } else {
        float bg = u.color.backgroundIntensity;
        ink = float3(max(bg, value));
    }

    // Optional per-variant colour tint from TextCellParameters-style edgeColor.
    // If provided as non-default, multiply into the ink contribution.
    // edgeColor defaults to (1,1,1,1) identity on the Swift side, so
    // multiplying unconditionally tints only when the user picked a colour.
    ink *= u.edgeColor.rgb;

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
    float3 srcOrig    = applyCommonAdjustments(source.sample(texSampler, selfUV).rgb, u.common);

    int   levels    = max(2, int(u.contourLevels));
    float fLevels   = float(levels);

    // Per grainrad reference: sample quantized levels at ±lineThick pixels
    // from the current fragment and emit a contour where the centre's
    // quantized level differs from any neighbour. `thickness` now controls
    // line width (was a dimensionless multiplier on lineStrength — that
    // was the "weird parameter mapping" users were hitting: Thickness and
    // Line Strength both ended up scaling the same luminance-band threshold,
    // so moving either slider produced visually identical results until
    // saturation). The `* 6.0` matches the UI slider range (0.05..1) to a
    // useful pixel-offset spread (≈0.3..6 px); the 0.5 floor guarantees at
    // least one texel of neighbour separation.
    float lineThick  = max(0.5, u.thickness * 6.0);
    float2 pixelStep = lineThick / resolution;

    // `quant` must apply `invert` symmetrically to the centre *and* every
    // neighbour; earlier code only inverted the centre, which broke detection
    // because the centre's quantized level landed in a different space than
    // its comparison neighbours. Helper closure-equivalent is inlined since
    // MSL forbids capturing lambdas inside fragment functions.
    float lumC = saturate(luminance(srcOrig));
    if (u.invert == 1u) lumC = 1.0 - lumC;
    float qC = floor(lumC * fLevels) / fLevels;

    float3 sL = applyCommonAdjustments(source.sample(texSampler, selfUV - float2(pixelStep.x, 0)).rgb, u.common);
    float3 sR = applyCommonAdjustments(source.sample(texSampler, selfUV + float2(pixelStep.x, 0)).rgb, u.common);
    float3 sU = applyCommonAdjustments(source.sample(texSampler, selfUV - float2(0, pixelStep.y)).rgb, u.common);
    float3 sD = applyCommonAdjustments(source.sample(texSampler, selfUV + float2(0, pixelStep.y)).rgb, u.common);

    float lL = saturate(luminance(sL)); if (u.invert == 1u) lL = 1.0 - lL;
    float lR = saturate(luminance(sR)); if (u.invert == 1u) lR = 1.0 - lR;
    float lU = saturate(luminance(sU)); if (u.invert == 1u) lU = 1.0 - lU;
    float lD = saturate(luminance(sD)); if (u.invert == 1u) lD = 1.0 - lD;

    float qL = floor(lL * fLevels) / fLevels;
    float qR = floor(lR * fLevels) / fLevels;
    float qU = floor(lU * fLevels) / fLevels;
    float qD = floor(lD * fLevels) / fLevels;

    bool isContour = (qL != qC) || (qR != qC) || (qU != qC) || (qD != qC);
    float strength = saturate(u.lineStrength);

    float value;
    if (u.contourFillMode == 1u) {
        // filledBands: each region at its quantized luminance, contour pixels
        // boosted by `fieldIntensity * strength`.
        float lineValue = saturate(qC + strength * max(0.01, u.fieldIntensity) * 0.3);
        value = isContour ? lineValue : qC;
    } else {
        // linesOnly: dim source, contour pixels at full `lineStrength`.
        float dim = lumC * 0.15;
        value = isContour ? strength : dim;
    }
    value = saturate(value);

    // Colour mapping: default is monochrome max(background, value); edgeColor
    // tint multiplied in when set.
    float bg = u.color.backgroundIntensity;
    float3 ink = float3(max(bg, value));
    // edgeColor defaults to (1,1,1,1) identity on the Swift side, so
    // multiplying unconditionally tints only when the user picked a colour.
    ink *= u.edgeColor.rgb;

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
    float3 srcOrig    = applyCommonAdjustments(source.sample(texSampler, selfUV).rgb, u.common);

    float lum     = saturate(luminance(srcOrig));
    float axis    = (u.direction == 1u) ? float(pixel.x) : float(pixel.y);
    float spacing = max(1.0, u.spacing);
    // CPU parity (`EdgeFieldRenderer.payloadFrequencyBoost`): lineCount above
    // the cell spacing multiplies frequency proportionally, so a higher
    // Line Count slider produces visibly more wave bands per axis.
    float countFactor = max(1.0, u.lineCount / spacing);
    float freq    = max(0.1, u.frequency * countFactor);
    float amp     = max(0.1, u.amplitude);

    float phase     = (axis / spacing) * freq;
    float wave      = sin(phase + lum * M_PI_F * amp);
    float threshold = max(0.03, u.thickness * max(0.1, u.lineStrength));
    float value     = (fabs(wave) < threshold) ? 1.0 : (lum * 0.15);
    if (u.invert == 1u) { value = 1.0 - value; }
    value = saturate(value);

    float bg = u.color.backgroundIntensity;
    float3 ink = float3(max(bg, value));
    // edgeColor defaults to (1,1,1,1) identity on the Swift side, so
    // multiplying unconditionally tints only when the user picked a colour.
    ink *= u.edgeColor.rgb;

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
    float3 srcOrig    = applyCommonAdjustments(source.sample(texSampler, selfUV).rgb, u.common);

    // This is a port of reference/shaders/voronoi__YS__L17259.wgsl, colorMode
    // = 1 (sample-at-centre). The previous implementation produced only a
    // grayscale wall/interior falloff and never sampled the source at the
    // seed — which is why users saw "BLACK and white, not the actual image
    // behind". Here `cellColor` is sampled at the seed pixel, so every
    // fragment inside a cell takes on that seed's source colour (classic
    // polygonal-mosaic look).
    float cellPitch = max(2.0, u.cellSize);
    float2 p        = float2(pixel) / cellPitch;
    float2 cellP    = floor(p);
    float2 fractP   = p - cellP;

    float2 closestCell = float2(0.0);
    float  nearest     = 1.0e10;
    float  secondNear  = 1.0e10;
    float  randomness  = (u.randomize == 1u) ? 1.0 : 0.0;

    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 neighbor = float2(float(i), float(j));
            float2 cellCtr  = cellP + neighbor;

            // hash2 from the reference — deterministic vec2 in [-1, 1].
            float2 k  = float2(0.3183099, 0.3678794);
            float2 pp = cellCtr * k + k.yx;
            float2 h  = fract(16.0 * k * fract(pp.x * pp.y * (pp.x + pp.y))) * 2.0 - 1.0;
            float2 randOffset = h * randomness * 0.5;
            float2 seed = neighbor + 0.5 + randOffset;

            float  d = length(seed - fractP);
            if (d < nearest) {
                secondNear  = nearest;
                nearest     = d;
                closestCell = cellCtr;
            } else if (d < secondNear) {
                secondNear  = d;
            }
        }
    }

    // Sample source at the closest seed's pixel position. Clamping the UV
    // matters — cells on the image boundary can resolve seeds outside [0,1].
    float2 seedUV    = clamp((closestCell + 0.5) * cellPitch / resolution, 0.0, 1.0);
    float3 cellColor = applyCommonAdjustments(source.sample(texSampler, seedUV).rgb, u.common);
    // UI "Cell Fill" (fieldWeight) scales cell brightness. 1.0 = source,
    // <1 = darkens, >1 = lifts. Floor at 0.1 so the slider never produces a
    // fully black mosaic (that's what `invert` is for).
    cellColor *= max(0.1, u.fieldWeight);

    // Wall mask via reference's edgeDist formula: 1 in interior, 0 at the
    // cell boundary. `edgeWidth * 0.3` matches the reference's falloff scale.
    float edgeDist = secondNear - nearest;
    float edgeW    = max(0.01, u.edgeWidth) * 0.3;
    float edge     = smoothstep(0.0, edgeW, edgeDist);

    // UI "Wall Strength" (lineStrength) hardens the transition: 0 keeps the
    // reference's soft smoothstep, 1 snaps to binary walls. Mixing between
    // the two rather than clamping preserves antialiasing at low strengths.
    edge = mix(edge, step(0.5, edge), saturate(u.lineStrength));

    // Wall colour: user-picked `edgeColor`. Swift-side default for voronoi
    // is black (set in EdgeFieldGPURenderer.renderVoronoi) so fresh layers
    // render the classic black-walls mosaic without UI tweaks.
    float3 wallColor = u.edgeColor.rgb;

    float3 mosaic = mix(wallColor, cellColor, edge);
    if (u.invert == 1u) { mosaic = 1.0 - mosaic; }

    // Existing "Background Intensity" slider acts as a floor on the darkest
    // pixels — unchanged behaviour from the old implementation.
    mosaic = max(mosaic, float3(u.color.backgroundIntensity));

    float3 final = mix(srcOrig, saturate(mosaic), saturate(u.intensity));
    return float4(final, 1.0);
}

// =============================================================================
// Noise primitives for `noiseFieldVariant`. Three flavours selected by
// `u.noiseType`:
//   0 — IGN (Jimenez 2014, defined in ShaderCommon.h)
//   1 — simplex 2D (Stefan Gustavson's webgl-noise, public domain port)
//   2 — cellular / Worley (minimum-distance to jittered grid seeds)
// All return [0,1]; FBM accumulator handles octave weighting.
// =============================================================================

static float3 mod289_3(float3 x) { return x - floor(x / 289.0) * 289.0; }
static float3 permute289(float3 x) { return mod289_3(((x * 34.0) + 1.0) * x); }

// Simplex 2D, remapped from native [-1,1] to [0,1].
static float simplex2D(float2 v) {
    const float4 C = float4( 0.211324865405187,
                             0.366025403784439,
                            -0.577350269189626,
                             0.024390243902439);
    float2 i  = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);
    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = i - floor(i / 289.0) * 289.0;
    float3 p = permute289(permute289(i.y + float3(0.0, i1.y, 1.0))
                          + i.x + float3(0.0, i1.x, 1.0));
    float3 m = max(0.5 - float3(dot(x0,  x0),
                                dot(x12.xy, x12.xy),
                                dot(x12.zw, x12.zw)), 0.0);
    m = m * m; m = m * m;
    float3 x  = 2.0 * fract(p * C.www) - 1.0;
    float3 h  = abs(x) - 0.5;
    float3 ox = floor(x + 0.5);
    float3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    float3 g;
    g.x  = a0.x  * x0.x  + h.x  * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return saturate(0.5 + 0.5 * 130.0 * dot(m, g));
}

// Cellular (Worley) F1 — minimum distance to any of nine jittered seeds in a
// 3x3 grid neighbourhood. Returns 0 at a seed, growing toward 1 as the point
// moves toward a cell boundary. Same hash as the voronoi variant for visual
// consistency.
static float cellular2D(float2 p) {
    float2 ip = floor(p);
    float2 fp = fract(p);
    float minDist = 1.0e10;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 neighbor = float2(float(i), float(j));
            float2 cellId   = ip + neighbor;
            float hx = fract(sin(dot(cellId, float2(127.1, 311.7))) * 43758.5453);
            float hy = fract(sin(dot(cellId, float2(269.5, 183.3))) * 43758.5453);
            float2 seedPos  = neighbor + float2(hx, hy);
            float  d        = length(fp - seedPos);
            minDist = min(minDist, d);
        }
    }
    return saturate(minDist);
}

// =============================================================================
// NOISE FIELD — multi-octave procedural noise. Sum N octaves at doubling
// frequencies with halving weights to produce FBM-style output. `octaves`
// (1..6) drives the detail depth; `amplitude` tunes the base spatial
// frequency; `fieldWeight` biases the output level. `noiseType` chooses
// between IGN (default), simplex, and cellular.
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
    float3 srcOrig    = applyCommonAdjustments(source.sample(texSampler, selfUV).rgb, u.common);

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
        float n;
        switch (u.noiseType) {
            case 1u: n = simplex2D(p * oct); break;
            case 2u: n = cellular2D(p * oct); break;
            default: n = ign(p * oct);       break;
        }
        accumulated += n * weight;
        weightSum   += weight;
    }
    float noise = accumulated / max(weightSum, 0.0001);
    float value = saturate(noise * u.lineStrength + u.fieldWeight * 0.3);
    if (u.invert == 1u) { value = 1.0 - value; }

    float bg = u.color.backgroundIntensity;
    float3 ink = float3(max(bg, value));
    // edgeColor defaults to (1,1,1,1) identity on the Swift side, so
    // multiplying unconditionally tints only when the user picked a colour.
    ink *= u.edgeColor.rgb;

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
