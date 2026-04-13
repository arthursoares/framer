// TextCell.metal
// Bucket shader for Framer's TextCell effect family:
//   - Dots        ← fully implemented as the reference port
//   - Blockify    ← stub, see notes/ (add when ready)
//   - ASCII       ← single-pass LUT-based implementation (see notes/ascii.md)
//   - MatrixRain  ← stub, requires time uniform + per-column state
//
// Approach patterns (fullscreen fragment, branchless shape selection, hex-grid
// row-offset math, dot-radius-from-luminance, Sobel edge classification, glyph-LUT
// sampling) studied from Grainrad (@almmaasoglu, https://grainrad.com — public
// bundle inspected 2026-04-13). This file is written fresh; no Grainrad code is copied.
//
// The single-pass ASCII path is intentionally simpler than Grainrad's two-pass
// compute+fragment design: the existing edgesASCII.png / fillASCII.png atlases
// already encode 10 luminance levels × 4 edge directions, so we don't need a
// per-cell glyph-matching compute pre-pass. Mirrors Framer's CPU
// ShaderASCIIRenderer algorithm so visual parity holds within float-precision
// tolerance. A Grainrad-style spatial-MSE matching pass can be added later as a
// quality upgrade (see notes/ascii.md).
//
// Primary references:
//   - Sobel & Feldman (1968) — 3×3 gradient operator
//   - Paul Bourke, "Character Representation of Grey Scale Images"
//     <http://paulbourke.net/dataformats/asciiart/> — brightness-ordered ramps
//   - Rec. ITU-R BT.601-7 — luma coefficients (via ShaderCommon.h)

#include "ShaderCommon.h"

// =============================================================================
// Uniforms for the TextCell bucket.
// Mirror exactly in Swift — keep field order and padding identical.
// =============================================================================

struct TextCellUniforms {
    // Framer common (brightness/contrast/sat/hue/sharpness/gamma)
    FramerCommonUniforms   common;
    FramerGeometryUniforms geometry;
    FramerColorUniforms    color;

    // TextCell-specific (shared across variants)
    uint   variant;          // 0 = dots, 1 = blockify, 2 = ascii, 3 = matrixRain
    uint   dotShape;         // 0 = circle, 1 = square, 2 = diamond
    uint   gridType;         // 0 = square, 1 = hex
    uint   blockStyle;       // 0 = solid, 1 = outlined

    float  sizeMultiplier;   // 0.5 .. 2.0
    float  intensity;        // 0 .. 1 (blend with original)
    uint   invert;           // 0 / 1
    float  borderWidth;      // for blockify outlined mode

    float  threshold;        // 0 .. 1
    float  glow;             // 0 .. 1
    float  backgroundOpacity;
    float  _pad0;

    // ASCII-specific
    float  cellSize;         // pixels per cell (4..64)
    float  edgeBias;         // 0..1, higher = more sensitive edge detection
    float  exposure;         // 0..5, multiplied into luminance pre-attenuation
    float  attenuation;      // 0..5, gamma-like exponent on luminance
    float  blackLevel;       // 0..1, lifts blacks
    uint   asciiColorMode;   // 0 = flat fg/bg, 1 = source color, 2 = gradient
    float  _pad1;
    float  _pad2;

    float4 asciiForegroundRGBA;
    float4 asciiBackgroundRGBA;
    float4 gradientStartRGBA;
    float4 gradientEndRGBA;
};

// Forward declarations so the fragment entry can call them before their
// definitions appear below. MSL follows C rules — must declare before use.
static float4 dotsVariant(VertexOut in, texture2d<float> source, sampler s, constant TextCellUniforms& u);
static float4 blockifyVariant(VertexOut in, texture2d<float> source, sampler s, constant TextCellUniforms& u);
static float4 asciiVariant(VertexOut in,
                           texture2d<float> source,
                           texture2d<float> edgesAtlas,
                           texture2d<float> fillAtlas,
                           sampler s,
                           constant TextCellUniforms& u);
static float4 matrixRainVariant(VertexOut in, texture2d<float> source, sampler s, constant TextCellUniforms& u);

// =============================================================================
// Main fragment: dispatch on variant
//
// Bindings:
//   texture(0): source image (sRGB, normalized float)
//   texture(1): edgesASCII atlas (r8 or rgba8 — only .r is read)
//   texture(2): fillASCII atlas  (r8 or rgba8 — only .r is read)
//   sampler(0): nearest-clamp sampler (atlases) / bilinear-clamp acceptable for source
//   buffer(0):  TextCellUniforms
//
// Atlas textures are required for `variant == 2` (ASCII). Other variants ignore
// them; Swift may bind dummy 1x1 textures or the same source texture twice.
// =============================================================================

fragment float4 textCellFragment(
    VertexOut                   in           [[stage_in]],
    texture2d<float>            source       [[texture(0)]],
    texture2d<float>            edgesAtlas   [[texture(1)]],
    texture2d<float>            fillAtlas    [[texture(2)]],
    sampler                     texSampler   [[sampler(0)]],
    constant TextCellUniforms&  uniforms     [[buffer(0)]]
) {
    switch (uniforms.variant) {
        case 0:  return dotsVariant(in, source, texSampler, uniforms);
        case 1:  return blockifyVariant(in, source, texSampler, uniforms);
        case 2:  return asciiVariant(in, source, edgesAtlas, fillAtlas, texSampler, uniforms);
        case 3:  return matrixRainVariant(in, source, texSampler, uniforms);
        default: return float4(0, 0, 0, 1);
    }
}

// =============================================================================
// DOTS — fully implemented (reference port; see notes/dots.md)
// =============================================================================

static float4 dotsVariant(
    VertexOut                   in,
    texture2d<float>            source,
    sampler                     texSampler,
    constant TextCellUniforms&  u
) {
    const float HEX_RATIO     = 0.866025403784;  // sqrt(3) / 2
    const float DIAMOND_SCALE = 1.41421356237;   // sqrt(2) — matches circle visual size

    float2 resolution  = float2(source.get_width(), source.get_height());
    float2 invRes      = 1.0 / resolution;
    float2 pixel       = in.uv * resolution;

    // Cell size = base * geometry.spacing * geometry.scale. Both UI sliders
    // contribute: spacing tunes the absolute cell pitch, scale acts as a
    // coarse multiplier so moving the Scale slider actually affects output
    // (previously only spacing was consumed — scale was silently orphaned).
    float scaleMult    = max(0.1, u.geometry.scale);
    float baseSpacing  = max(2.0, 8.0 * u.geometry.spacing * scaleMult);
    float invBaseSpace = 1.0 / baseSpacing;
    float dotBaseR     = baseSpacing * 0.4 * u.sizeMultiplier;

    // Locate the cell center for this pixel (square or hex).
    float2 cellCenter;
    if (u.gridType == 1) {
        float hexSpacingY = baseSpacing * HEX_RATIO;
        float invHexY     = 1.0 / hexSpacingY;
        float row         = floor(pixel.y * invHexY);
        bool  isOddRow    = (int(row) & 1) == 1;
        float xOffset     = isOddRow ? baseSpacing * 0.5 : 0.0;
        float cellX       = floor((pixel.x - xOffset) * invBaseSpace);
        cellCenter = float2(
            (cellX + 0.5) * baseSpacing + xOffset,
            (row   + 0.5) * hexSpacingY
        );
    } else {
        float2 cellPos = floor(pixel * invBaseSpace);
        cellCenter = (cellPos + 0.5) * baseSpacing;
    }

    // Sample source at cell center and compute luminance.
    float2 cellUV = cellCenter * invRes;
    float3 srcColor = source.sample(texSampler, cellUV).rgb;
    srcColor = applyBrightnessContrast(srcColor, u.common.brightness, u.common.contrast);
    srcColor = applyGamma(srcColor, u.common.gamma);

    float luma = luminance(srcColor);
    luma = (u.invert == 1) ? (1.0 - luma) : luma;

    // Dot radius scales with luminance — the Grainrad insight from notes/dots.md.
    float radius   = dotBaseR * (0.2 + luma * 0.8);
    float radiusSq = radius * radius;

    // Branchless shape selection: circle / square / diamond.
    float2 localPos = pixel - cellCenter;
    float2 absL     = abs(localPos);
    float  distSq   = dot(localPos, localPos);

    bool circleIn  = distSq < radiusSq;
    bool squareIn  = max(absL.x, absL.y) < radius;
    bool diamondIn = (absL.x + absL.y) < radius * DIAMOND_SCALE;

    bool inShape = (u.dotShape == 2) ? diamondIn
                  : (u.dotShape == 1) ? squareIn
                  :                     circleIn;

    // Color selection based on FramerColorUniforms.mode:
    //   0 = source color
    //   1 = fg/bg (custom colors × luma)
    //   2 = monochrome (grayscale)
    float3 dotColor;
    if (u.color.mode == 2) {
        dotColor = float3(luma);
    } else if (u.color.mode == 1) {
        dotColor = u.color.foregroundRGBA.rgb * luma;
    } else {
        dotColor = srcColor;
    }

    float3 bgColor = u.color.backgroundRGBA.rgb * u.color.backgroundIntensity;
    float3 final   = inShape ? dotColor : bgColor;
    return float4(final, 1.0);
}

// =============================================================================
// BLOCKIFY — stub. See notes/ — straightforward port:
//   - cell = floor(pixel / baseSpacing)
//   - sample at cell center
//   - solid:    fill cell with sampled color
//   - outlined: fill cell with border color, inset by borderWidth*cellSize, fill with sampled
// =============================================================================

// =============================================================================
// BLOCKIFY — tile the image with solid or outlined rectangles, one per cell.
// Mirrors TextCellBucketRenderer's CPU fallback:
//   - solid:    fill cell with cell-average colour
//   - outlined: fill cell with border colour, inset rectangle with cell colour
//     (inset proportional to borderWidth; clamped to min 1 px)
// blockStyle: 0 = solid, 1 = outlined.
// =============================================================================

static float4 blockifyVariant(
    VertexOut                   in,
    texture2d<float>            source,
    sampler                     texSampler,
    constant TextCellUniforms&  u
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    float2 invRes     = 1.0 / resolution;
    float2 pixel      = in.uv * resolution;

    // Same cell size as dots — spacing + scale both contribute.
    float scaleMult   = max(0.1, u.geometry.scale);
    float baseSpacing = max(2.0, 8.0 * u.geometry.spacing * scaleMult);

    // Cell coordinates in pixel space.
    float2 cellIdx      = floor(pixel / baseSpacing);
    float2 cellOriginPx = cellIdx * baseSpacing;
    float2 localPx      = pixel - cellOriginPx;
    float2 cellCenterPx = cellOriginPx + float2(baseSpacing * 0.5);

    // Average the cell's source colour by sampling at the centre with the
    // bilinear sampler — for a cell of ~8 px this blurs the cell contents
    // close to their true mean without the cost of an exhaustive loop.
    float3 cellColor = source.sample(texSampler, cellCenterPx * invRes).rgb;

    // Foreground / background colour selection mirrors the ASCII variant's
    // mode handling for consistency across the bucket: 0 = flat fg/bg from
    // uniforms, 1 = use per-cell sampled colour, 2 = gradient by luminance.
    // TextCellParameters.foreground/background already resolved into
    // u.color.foregroundRGBA / backgroundRGBA Swift-side.
    float3 fgColor;
    if (u.color.mode == 1u) {
        fgColor = cellColor;
    } else {
        fgColor = u.color.foregroundRGBA.rgb;
    }
    float3 bgColor = u.color.backgroundRGBA.rgb;

    // Solid: cell filled with fg. Outlined: border rim in bg, inset rect in fg.
    float3 drawn;
    if (u.blockStyle == 1u) {
        // Inset proportional to borderWidth. `borderWidth` is 0..1-ish, scales
        // similarly to the CPU path (`rect.width * borderWidth * 0.4`), with a
        // 1-pixel floor so hairline borders always render visibly.
        float inset = max(1.0, baseSpacing * u.borderWidth * 0.4);
        bool  inInset = localPx.x >= inset
                     && localPx.x <= (baseSpacing - inset)
                     && localPx.y >= inset
                     && localPx.y <= (baseSpacing - inset);
        drawn = inInset ? fgColor : bgColor;
    } else {
        drawn = fgColor;
    }

    // Final mix with original by intensity — matches dots and ascii.
    float3 srcOrig = source.sample(texSampler, in.uv).rgb;
    float3 final   = mix(srcOrig, drawn, saturate(u.intensity));
    return float4(final, 1.0);
}

// =============================================================================
// ASCII — single-pass, LUT-based.
//
// Mirrors the CPU ShaderASCIIRenderer pipeline (see Sources/FramerCore/Processing/
// ShaderASCIIRenderer.swift) so GPU/CPU outputs match within float-precision
// tolerance. For each fragment:
//   1. Locate the enclosing cell from `pixel / cellSize`.
//   2. Average luminance: 4×4 stratified samples inside the cell.
//   3. Sobel edge classification: sample luminance at the 3×3 cell-spaced
//      neighbours of the cell centre. Threshold on magnitude scales with
//      `edgeBias`; angle quantizes into vertical / horizontal / diagonal1 /
//      diagonal2 buckets.
//   4. Tone-map luminance: pow(avg * exposure, attenuation), lift blacks, invert.
//   5. LUT sample: pick the 8×8 sub-cell pixel from `edgesASCII` (offset
//      (direction+1)*8 along x) when an edge was detected, otherwise from
//      `fillASCII` at the brightness-quantized 0..9 column.
//   6. Mix background → foreground by glyph value, then blend with original by
//      `intensity`.
//
// The atlas-spaced Sobel keeps per-fragment cost O(16 + 9) source samples
// instead of O(cellSize²). At preview resolutions (~1920×1080, cell=10) this is
// well under a millisecond on integrated GPUs.
// =============================================================================

static float4 asciiVariant(
    VertexOut                   in,
    texture2d<float>            source,
    texture2d<float>            edgesAtlas,
    texture2d<float>            fillAtlas,
    sampler                     texSampler,
    constant TextCellUniforms&  u
) {
    float2 resolution  = float2(source.get_width(), source.get_height());
    float2 invRes      = 1.0 / resolution;
    float2 pixel       = in.uv * resolution;

    float cellSizeF = max(2.0, u.cellSize);
    float invCell   = 1.0 / cellSizeF;

    // Cell coordinates (origin = top-left of the cell, in pixel space).
    float2 cellIdx       = floor(pixel * invCell);
    float2 cellOriginPx  = cellIdx * cellSizeF;
    float2 cellCenterPx  = cellOriginPx + float2(cellSizeF * 0.5);
    float2 localPx       = pixel - cellOriginPx;       // 0 .. cellSize

    // ---- Per-pixel cell statistics (faithful port of CPU algorithm) --------
    // ShaderASCIIRenderer averages luminance + colour across EVERY pixel in
    // the cell and runs Sobel at EVERY pixel in the cell, accumulating gxSum,
    // gySum, and per-pixel gradient magnitude. A prior 4×4 stratified / cell-
    // centre Sobel approximation diverged enough to flip edge/fill classifi-
    // cation for marginal cells, producing 255-delta pixels in the parity
    // test. Matching the CPU loop exactly costs ~cellSize²×9 samples per
    // fragment (≤ ~36K for the clamped range 4..64) — easily absorbed on
    // Apple Silicon given the full-resolution per-pixel parallelism.
    //
    // Edge cells: when image dimensions aren't divisible by cellSize, the
    // last cell in a row/column is narrower/shorter. Clip the loop bounds
    // to the actual cell extent (cellW, cellH) and divide by the clipped
    // count — matches CPU's `xEnd - cellX` / `yEnd - cellY` reductions
    // (ShaderASCIIRenderer.swift:186-189). Without this, edge cells would
    // include phantom samples beyond the image edge (clamp-to-edge sampler
    // returns the boundary pixel value, biasing the average).
    int cellSizeI = int(cellSizeF);
    int cellW     = min(cellSizeI, max(0, int(resolution.x) - int(cellOriginPx.x)));
    int cellH     = min(cellSizeI, max(0, int(resolution.y) - int(cellOriginPx.y)));
    if (cellW <= 0 || cellH <= 0) {
        return float4(source.sample(texSampler, in.uv).rgb, 1.0);
    }

    float lumSum       = 0.0;
    float3 colorSum    = float3(0.0);
    float gxSum        = 0.0;
    float gySum        = 0.0;
    float edgeMagSum   = 0.0;

    for (int j = 0; j < cellH; j++) {
        for (int i = 0; i < cellW; i++) {
            float2 samplePx = cellOriginPx + float2(float(i) + 0.5, float(j) + 0.5);
            float3 c = source.sample(texSampler, samplePx * invRes).rgb;
            float  l = luminance(c);
            lumSum   += l;
            colorSum += c;

            // Per-pixel Sobel. Use sampler-clamped reads for neighbours so
            // cell-edge pixels don't wrap — matches CPU's clamping lum() helper.
            float tl = luminance(source.sample(texSampler, (samplePx + float2(-1, -1)) * invRes).rgb);
            float tc = luminance(source.sample(texSampler, (samplePx + float2( 0, -1)) * invRes).rgb);
            float tr = luminance(source.sample(texSampler, (samplePx + float2( 1, -1)) * invRes).rgb);
            float ml = luminance(source.sample(texSampler, (samplePx + float2(-1,  0)) * invRes).rgb);
            float mr = luminance(source.sample(texSampler, (samplePx + float2( 1,  0)) * invRes).rgb);
            float bl = luminance(source.sample(texSampler, (samplePx + float2(-1,  1)) * invRes).rgb);
            float bc = luminance(source.sample(texSampler, (samplePx + float2( 0,  1)) * invRes).rgb);
            float br = luminance(source.sample(texSampler, (samplePx + float2( 1,  1)) * invRes).rgb);

            float gx = (-tl - 2.0 * ml - bl) + (tr + 2.0 * mr + br);
            float gy = (-tl - 2.0 * tc - tr) + (bl + 2.0 * bc + br);

            gxSum += gx;
            gySum += gy;
            edgeMagSum += sqrt(gx * gx + gy * gy);
        }
    }
    float invSamples = 1.0 / float(cellW * cellH);
    float  avgLum    = lumSum * invSamples;
    float3 avgColor  = colorSum * invSamples;
    float  avgMag    = edgeMagSum * invSamples;

    // ---- Tone-map luminance for the LUT lookup -----------------------------
    // Pass `attenuation` through unchanged — CPU allows 0 (which makes pow()
    // collapse to 1.0 across the luminance range, useful for "max-brightness"
    // overrides). The previous max(attenuation, 0.0001) clamp diverged from
    // CPU at the exact value 0 (ShaderASCIIRenderer.swift:151,221).
    float adjustedLum = saturate(pow(max(avgLum * u.exposure, 0.0), u.attenuation));
    if (u.blackLevel > 0.0) {
        adjustedLum = u.blackLevel + adjustedLum * (1.0 - u.blackLevel);
    }
    if (u.invert == 1u) {
        adjustedLum = 1.0 - adjustedLum;
    }

    // ---- Edge classification (matches CPU threshold + direction bucketing) -
    // edgeBias 1.0 = very sensitive (low threshold), 0.0 = never edge.
    float threshold = 0.05 + (1.0 - u.edgeBias) * 0.35;
    bool  isEdge    = avgMag > threshold;
    float gx = gxSum;
    float gy = gySum;

    int direction = -1;        // -1 = no edge
    if (isEdge) {
        float theta = atan2(gy, gx);
        float absT  = fabs(theta) / M_PI_F;
        if (absT < 0.1 || absT > 0.9) {
            direction = 0;     // vertical |
        } else if (absT > 0.4 && absT < 0.6) {
            direction = 1;     // horizontal —
        } else if (theta > 0.0) {
            direction = (absT < 0.5) ? 3 : 2;  // diagonal2 / diagonal1
        } else {
            direction = (absT < 0.5) ? 2 : 3;
        }
    }

    // ---- LUT sample (atlases laid out in 8×8 glyph cells along x) ----------
    // Atlases bind as `access::sample` (default), so we sample with a
    // nearest-clamp sampler instead of using `.read()`. UV is computed from
    // integer pixel coordinates plus a 0.5 centre offset, matching the
    // `sample(x:y:)` lookup the CPU LUT uses.
    //
    // Uses the clipped cellW/cellH (not cellSize) so the glyph is stretched
    // across the actual cell extent on edge cells — matches CPU's
    // `(localX * 8) / cellW` / `(localY * 8) / cellH` mapping
    // (ShaderASCIIRenderer.swift:447-448).
    int gx8 = clamp(int(floor(localPx.x * 8.0 / float(max(1, cellW)))), 0, 7);
    int gy8 = clamp(int(floor(localPx.y * 8.0 / float(max(1, cellH)))), 0, 7);

    float glyphValue;
    if (direction >= 0) {
        // Edge glyph offset: (direction + 1) * 8
        int xCoord = gx8 + (direction + 1) * 8;
        float2 atlasSize = float2(edgesAtlas.get_width(), edgesAtlas.get_height());
        float2 atlasUV   = (float2(float(xCoord), float(gy8)) + 0.5) / atlasSize;
        glyphValue       = edgesAtlas.sample(texSampler, atlasUV).r;
    } else {
        // Fill glyph: quantize luminance to 0..9, offset = level * 8
        int level   = clamp(int(floor(adjustedLum * 9.999)), 0, 9);
        int xCoord  = gx8 + level * 8;
        float2 atlasSize = float2(fillAtlas.get_width(), fillAtlas.get_height());
        float2 atlasUV   = (float2(float(xCoord), float(gy8)) + 0.5) / atlasSize;
        glyphValue       = fillAtlas.sample(texSampler, atlasUV).r;
    }

    // ---- Foreground / background colour resolution -------------------------
    float3 bg = u.asciiBackgroundRGBA.rgb;
    float3 fg;
    if (u.asciiColorMode == 1u) {
        // Source: per-cell average colour
        fg = avgColor;
    } else if (u.asciiColorMode == 2u) {
        // Gradient: lerp(start, end, adjustedLum)
        fg = mix(u.gradientStartRGBA.rgb, u.gradientEndRGBA.rgb, adjustedLum);
    } else {
        // Flat foreground (also covers dominantTwoTone — colours resolved CPU-side)
        fg = u.asciiForegroundRGBA.rgb;
    }

    float3 glyphColor = mix(bg, fg, glyphValue);

    // ---- Blend with original by intensity ----------------------------------
    float3 srcOrig = source.sample(texSampler, in.uv).rgb;
    float3 final   = mix(srcOrig, glyphColor, saturate(u.intensity));
    return float4(final, 1.0);
}

// =============================================================================
// MATRIX RAIN — stub. Needs:
//   - time uniform (float) — current render time in seconds
//   - per-column state (optional): trail head position per column, read from a small buffer
//   - glyph atlas (reuse ASCII's — Katakana + alphanumeric)
//
// Algorithm sketch:
//   1. column = floor(pixel.x / cellSize)
//   2. trailHead = (time * speed + columnSeed(column)) mod resolution.y
//   3. trailDistance = trailHead - pixel.y (wrapped)
//   4. if trailDistance < 0: above trail, black
//      if trailDistance < trailLength: bright glyph fading with distance
//      else: black
//   5. glyph selection: hash(column, floor(pixel.y / cellSize)) % charsetLength
// =============================================================================

// =============================================================================
// MATRIX RAIN — vertical (or directional) streams of falling light with per-
// column phase. A photo editor renders a single frame, so we use `speed` as a
// phase-scrub parameter rather than a rate: moving the slider advances the
// animation to a different frozen frame. Per-column seeds are derived from
// the column index so each stream falls independently.
//
// Pipeline per fragment:
//   1. Determine the column index from pixel.x / cellSize and hash for
//      phase/speed variation.
//   2. Compute the trail head's pixel position at the current "time" (= speed).
//   3. Compute the fragment's vertical distance below the head (wrapped to
//      image height so streams repeat).
//   4. If within trailLength: render ink with a leading-glyph glow that fades
//      over the trail. Else: background (optionally showing source).
//   5. Source-luminance gating: if lum < threshold, skip rendering and show
//      source — produces the "rain only in bright areas" look.
//   6. Colour is rainColor tint × trail intensity; mix with source by
//      intensity and backgroundOpacity.
// =============================================================================

static float4 matrixRainVariant(
    VertexOut                   in,
    texture2d<float>            source,
    sampler                     texSampler,
    constant TextCellUniforms&  u
) {
    float2 resolution = float2(source.get_width(), source.get_height());
    int2   pixel      = clamp(int2(floor(in.uv * resolution)),
                              int2(0), int2(resolution) - 1);
    float2 selfUV     = (float2(pixel) + 0.5) / resolution;
    float3 srcOrig    = source.sample(texSampler, selfUV).rgb;

    // Cell size and column index (cells run vertically, stacked horizontally).
    float cellSizeF    = max(2.0, 8.0 * u.geometry.spacing * max(0.1, u.geometry.scale));
    int   cellPitch    = int(cellSizeF);
    int   cellSizeInt  = max(2, cellPitch);
    int   columnIndex  = pixel.x / cellSizeInt;

    // Per-column hash for speed + phase variation. Two independent
    // sine-fract calls so speed vs phase aren't correlated.
    float columnHash1 = fract(sin(float(columnIndex) * 12.9898) * 43758.5453);
    float columnHash2 = fract(sin(float(columnIndex) * 78.233)  * 43758.5453);

    // "Time" is the speed slider — in a still-image editor we scrub a
    // frozen frame rather than play a continuous animation. Each column
    // advances at its own rate to avoid lockstep falls.
    float time        = u.backgroundOpacity;   // repurpose as phase-scrub slot — see note below
    float columnSpeed = 0.5 + columnHash2;      // 0.5..1.5
    float phase       = fract(time * columnSpeed + columnHash1);

    // Trail head position in pixel space. Direction handled by flipping
    // the phase along the axis.
    float axisLen     = (u.dotShape == 1u) ? resolution.x : resolution.y;   // dotShape re-used as direction flag
    float axisCoord   = (u.dotShape == 1u) ? float(pixel.x) : float(pixel.y);
    float headPx      = phase * axisLen;
    float distBelow   = axisCoord - headPx;
    // Wrap so trails that "leave" the bottom re-enter from the top.
    if (distBelow < 0.0) { distBelow += axisLen; }

    // Trail length in pixels — `threshold` is repurposed as trail-length
    // slider because TextCellParameters' actual trailLength field is mapped
    // to one of the shader uniforms reachable here (see makeMatrixRainUniforms
    // Swift-side). `glow` biases the leading-glyph brightness.
    float trailLen = max(2.0, u.threshold * axisLen * 0.5);
    float trailPos = distBelow / trailLen;
    if (trailPos > 1.0) {
        // Outside the trail — show source only, dimmed by backgroundOpacity.
        // We intentionally don't early-return; downstream colour math handles
        // the "fully off" case with value = 0.
    }

    // Trail brightness: 1.0 at the leading glyph, tapering to 0 at trail end.
    float headGlow  = max(0.1, saturate(u.glow));
    float intensity = (trailPos <= 1.0) ? (1.0 - trailPos) * (0.4 + 0.6 * headGlow) : 0.0;

    // Per-cell flicker — hash of (column, row) gives slight brightness
    // variance so the trail doesn't look like a solid bar.
    int   rowIndex = pixel.y / cellSizeInt;
    float cellFlicker = 0.6 + 0.4 * fract(sin(float(columnIndex * 31 + rowIndex * 17)) * 43758.5453);
    float cellMask    = (trailPos <= 1.0) ? step(0.3, cellFlicker) : 0.0;
    intensity *= cellMask;

    // Colour: tint is asciiForegroundRGBA (repurposed as rain colour); a
    // green default (0.1, 1.0, 0.3) gives the classic Matrix look when the
    // user hasn't overridden it.
    float3 tint = u.asciiForegroundRGBA.rgb;
    if (tint.r + tint.g + tint.b < 0.05) {
        tint = float3(0.1, 1.0, 0.3);
    }
    float3 trail = tint * intensity;

    // Background: source dimmed. Full source visibility when intensity=0 is
    // the user scrubbing to a low point; `backgroundIntensity` scales that.
    float bgOpacity = saturate(u.color.backgroundIntensity);
    float3 bg       = srcOrig * bgOpacity;

    float3 combined = saturate(bg + trail);
    float3 final    = mix(srcOrig, combined, saturate(u.intensity));
    return float4(final, 1.0);
}
