# Caption as Composition Layer

## Summary

Refactor the caption system from a special-case post-processing step into a `CompositionLayer` variant, making it part of the layer-based composition pipeline.

## Data Model

New case on `CompositionLayer`:

```swift
case caption(CaptionLayerParams)
```

`CaptionLayerParams` holds all caption configuration:
- `mode: CaptionMode` — .template(String), .custom(String), .none
- `fontName: String`
- `fontSize: FontSize`
- `fontStyle: FontStyle`
- `fontColor: CodableColor`
- `alignment: CaptionAlignment`
- `position: CaptionPosition`
- `offsetX: Int`
- `offsetY: Int`

## Rendering

- `BorderRenderer.applyLayers` signature gains an `exif: ExifData` parameter
- `.caption` case calls `CaptionRenderer` to draw text onto the current image
- `FrameProcessor` no longer calls `CaptionRenderer` separately — it's handled in the layer loop
- `CaptionRenderer` simplified: no longer needs `imageOrigin`/`imageSize` canvas awareness (caption layer renders on whatever image the pipeline gives it; font auto-size uses current image dimensions)

## Config Cleanup

Remove from `ProcessingConfig`:
- `captionMode`, `fontName`, `fontSize`, `fontStyle`, `fontColor`
- `captionAlignment`, `captionPosition`, `captionOffsetX`, `captionOffsetY`, `captionPadding`

Delete `fromLegacyConfig()` — no backward compatibility needed.

## UI Changes

- Remove Caption and Font sections from `SettingsPanel`
- Add `CaptionLayerControls` in `LayerListSection` with: mode picker, template field, token bar, font picker, style toggles, size, color, alignment, position, offsets
- Move `TemplateTokenBar` from `SettingsPanel` to `LayerListSection` (or shared file)

## Default Layers

`CompositionLayer.defaultLayers()` includes `.caption(CaptionLayerParams())` at the end of the stack.

## CLI

Update `ProcessCommand` to build caption params into the layer stack instead of config fields.
