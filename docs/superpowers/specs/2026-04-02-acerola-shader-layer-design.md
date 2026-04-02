# Acerola-Inspired Shader Layer Design

## Goal

Add a new Framer-native `shader` composition layer that provides six curated, Acerola-inspired looks as a single layer with a small control surface per style.

The goal is visual faithfulness to the reference looks, not literal parity with AcerolaFX internals. The layer must apply in both preview and final render. Preview-only effects are out of scope.

## User Outcome

Users can add one `Shader` layer to a composition, choose a named style, and tweak a few controls without needing to stack several lower-level layers manually.

Initial styles:

- `ASCII`
- `Crimewave`
- `Narc`
- `Shiba`
- `Pixel Sort`
- `Distant Past`

These styles are Framer-native looks inspired by AcerolaFX releases and examples. They are not imported AcerolaFX presets.

## Product Shape

### New layer type

Add `CompositionLayer.shader(ShaderLayerParams)`.

`ShaderLayerParams` includes:

- `id: UUID`
- `enabled: Bool`
- `style: ShaderStyle`
- `intensity: Double`
- `styleParams: ShaderStyleParams`

`ShaderStyle` is an enum with the six initial styles.

`intensity` is a top-level wet/dry control shared by all styles. It allows users to back off a look without understanding the internal parameters.

`ShaderStyleParams` is a tagged payload keyed by `style`, similar to how existing layer params are modeled elsewhere in the app. Each style has its own compact parameter struct.

### User-facing controls

Each style exposes 2-5 controls max. Strong defaults are mandatory.

Initial control sets:

- `ASCII`
  - `cellSize`
  - `edgeBias`
  - `foreground`
  - `background`
  - `invert`
- `Crimewave`
  - `neon`
  - `softness`
  - `contrast`
  - `grain`
- `Narc`
  - `contrast`
  - `crush`
  - `temperature`
  - `grain`
- `Shiba`
  - `warmth`
  - `softness`
  - `saturation`
  - `grain`
- `Pixel Sort`
  - `threshold`
  - `direction`
  - `span`
  - `amount`
- `Distant Past`
  - `paletteDepth`
  - `fade`
  - `softness`
  - `grain`

The exact numeric ranges may shift during implementation, but the control count and intent should remain stable.

## Rendering Model

### High-level approach

Implement the layer as a Framer-native composite renderer. Each style is a curated mini-pipeline made of shared internal image operations plus a few bespoke effects.

This is not a literal port of AcerolaFX preset files. The implementation targets the same visual result using Framer-controlled rendering steps.

### Rendering contract

- The layer must render in preview and export.
- Export parity is required.
- The same logical style recipe must be used for both preview and export.
- Small differences due to resolution scaling are acceptable. Large aesthetic differences are not.

### CPU vs GPU

The system should be renderer-agnostic at the layer model level.

Implementation direction:

- prefer GPU-backed rendering for effects that are naturally screen-space and sampling-heavy
- allow CPU implementations or CPU fallbacks where needed for correctness, portability, or testability
- do not ship any style that only works in preview

The architecture must allow a style to choose the best renderer internally while preserving one user-facing layer contract.

## Internal effect library

To avoid implementing six disconnected pipelines, the shader layer should be backed by a reusable internal effect library.

Shared primitives:

- tonal shaping and contrast curve adjustment
- saturation and temperature shifts
- blur and softening
- vignette
- procedural grain
- channel offset / chromatic separation
- quantization and palette remap
- scanlines / CRT mask

Bespoke primitives:

- ASCII cell renderer
- pixel sorting span processor
- CRT curvature and phosphor-style presentation

The shared library is an internal implementation detail, not a user-visible layer graph.

## Style intent

### ASCII

Primary signature:

- glyph-based rendering over luminance and edge structure
- strong graphic simplification

Implementation notes:

- needs a bespoke cell renderer
- should bias glyph selection with both brightness and edge direction so shapes read better than a pure luminance-only ASCII effect

### Crimewave

Primary signature:

- neon-heavy stylization
- softened glow
- aggressive contrast and nightlife palette bias

Implementation notes:

- composite look built from contrast, color shaping, softness, and grain
- no promise of identical internal pass order to AcerolaFX

### Narc

Primary signature:

- harsher tonal shaping
- crushed values and stylized grading
- gritty texture presence

Implementation notes:

- built from contrast curve shaping, palette bias, and grain

### Shiba

Primary signature:

- warm, soft, pleasant stylization
- less aggressive than Narc or Crimewave

Implementation notes:

- built from warmth, softness, and saturation shaping with restrained grain

### Pixel Sort

Primary signature:

- directional span sorting in selected regions
- obvious digital corruption aesthetic

Implementation notes:

- requires a bespoke implementation
- sort mask should be based on thresholded image properties rather than arbitrary random spans alone

### Distant Past

Primary signature:

- reduced palette
- faded, aged, low-fi image treatment
- optional softness and grain

Implementation notes:

- should be achievable as a compact composite using quantization, color shaping, fade, and texture

## Presets

Framer should ship curated built-in presets using the new `shader` layer rather than importing AcerolaFX preset files.

Preset requirements:

- each shipped look should have at least one built-in preset matching its default style tuning
- preset naming should be Framer-native and avoid implying official AcerolaFX file compatibility
- preset previews must render the shader layer, not bypass it

## Data model and serialization

The new layer must round-trip through:

- `CompositionLayer` codable serialization
- preset JSON serialization
- YAML config encoding/decoding

Backward compatibility rules:

- configs without shader layers continue decoding unchanged
- unknown shader styles should fail safely rather than silently mapping to the wrong look
- disabled shader layers must remain disabled after round-trip

## UI and editing

### Layer creation

Add `Shader` to the add-layer menus on macOS and iOS.

### Layer editing

Both platforms need editors for:

- style selection
- shared `intensity`
- style-specific controls
- enable/disable behavior consistent with the other layer types

### Preset previews

Preset preview generation must include shader layers so the built-in presets read correctly in the strip/grid.

If preview generation becomes too slow, optimize implementation details rather than removing shader support from previews.

## Performance expectations

This feature is preview-sensitive. The UI must remain usable when a shader layer is present and preset previews are regenerated.

Performance principles:

- default parameters should be chosen with preview cost in mind
- expensive styles like `ASCII` and `Pixel Sort` may use scaled preview rendering as long as the final look remains faithful
- export can be slower than preview, but should remain practical for normal single-image use

## Testing

Required test coverage:

- `CompositionLayer` codable round-trip for `shader`
- YAML encode/decode for shader layers
- preset store round-trip preserving shader layers and enabled state
- renderer tests for each style asserting deterministic output properties
- preview/export parity tests at a coarse image-difference level for the shader styles

For styles where exact pixel snapshots are brittle, test stable structural properties instead:

- output dimensions unchanged when expected
- palette count reduction
- presence of sorted spans
- glyph-cell behavior
- measurable scanline or grain characteristics

## Non-goals

- importing AcerolaFX preset files
- exact pixel parity with AcerolaFX
- exposing the full internal shader graph to users
- shipping styles that only work in preview
- depth-buffer-dependent AcerolaFX looks in this phase

## Risks

- `ASCII` and `Pixel Sort` are materially harder than the grading-oriented looks
- some reference looks may depend on subtle AcerolaFX HDR interactions that Framer will only approximate
- preset preview cost may rise sharply if style pipelines are not designed carefully

## Rollout recommendation

Implement the feature as one `Shader` layer type with all six named styles in the first release. Internally, prioritize shared primitives so `Crimewave`, `Narc`, `Shiba`, and `Distant Past` do not become four entirely separate renderers.

The acceptance bar is visual recognizability and export parity, not source-level parity with AcerolaFX.
