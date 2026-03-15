# Video Support Design

## Overview

Add video processing support to Framer — apply the full layer pipeline (borders, padding, captions, dithering, overlays) to every frame of a video, with optional trimming and codec selection.

## Pipeline

```
Input Video (any AVFoundation-decodable format)
    ↓
AVAssetReader (decode frames as CVPixelBuffer)
    ↓
Optional trim (CMTimeRange from timecode in/out)
    ↓
CIImage per frame
    ↓
CIFilter chain (layer stack: borders, padding, resize, overlay, dither, caption)
    ↓
AVAssetWriter (H.264 or H.265, with passthrough audio)
    ↓
Output Video (.mp4)
```

## New Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `VideoProcessor` (actor) | `FramerCore/Processing/` | Orchestrates read → process → write loop, manages progress |
| `CIFilterPipeline` | `FramerCore/Processing/` | Converts `[CompositionLayer]` → `CIFilter` chain |
| `DitherCIKernel` | `FramerCore/Processing/Kernels/` | Custom Metal kernel for dithering algorithms |
| `VideoCodec` (enum) | `FramerCore/Models/` | `.h264` / `.h265` with AVFoundation mapping |
| `TrimRange` (struct) | `FramerCore/Models/` | Start/end timecodes, parses `HH:MM:SS.mmm` |

## Core Image Migration

The `CIFilterPipeline` replaces the current `CGImage` path for both stills and video, so both share the same GPU-accelerated rendering.

### Layer Mapping to CIFilter Chain

| Layer | CI Strategy |
|-------|-------------|
| **Border** | `CIFilter.compositeSourceOver` — render frame onto larger solid-color `CIImage` |
| **Padding** | Same as border — composite onto padded canvas with fill color/gradient |
| **Canvas** | Generate `CIImage` at fixed size, composite source centered |
| **Resize** | `CIFilter.lanczosScaleTransform` with aspect ratio preservation |
| **Overlay** | `CIFilter.sourceOverCompositing` with blend mode kernels (screen, soft light, multiply) |
| **Orientation** | `CIImage.transformed(by:)` with affine rotation |
| **Caption** | Render text to `CIImage` via CoreText, composite onto frame |
| **Dither** | Custom `CIColorKernel` / `CIKernel` in Metal Shading Language |

### Custom Metal Kernels

1. **DitherKernel** — Bayer matrix, ordered dithering (GPU)
2. **ErrorDiffusionKernel** — Approximated with blue noise dithering on GPU for video; CPU error diffusion (Floyd-Steinberg, Atkinson, Stucki) remains available for stills when exact algorithm is requested
3. **OverlayBlendKernel** — Luminance-deviation alpha blending (custom normal mode)

## Output Dimension Preview

`CIFilterPipeline` exposes `outputSize(for inputSize: CGSize) -> CGSize` that walks the layer stack and computes final dimensions without rendering. Available for both video and image previews. Displayed as a badge in the preview panel.

## Data Model Changes

### New Types

```swift
enum VideoCodec: String, Codable, Sendable {
    case h264
    case h265
}

struct TrimRange: Codable, Sendable {
    let start: TimeInterval  // parsed from HH:MM:SS.mmm
    let end: TimeInterval
}

struct VideoExportConfig: Codable, Sendable {
    var codec: VideoCodec = .h264
    var trim: TrimRange? = nil  // nil = full video
}
```

### Changes to Existing Types

| Type | Change |
|------|--------|
| `ProcessingConfig` | Add optional `videoExport: VideoExportConfig?` |
| `OutputFormat` | Add `.mp4(VideoExportConfig)` case |
| `YAMLConfig` | Add `codec` and `trim` fields |
| `FrameProcessor` | Detect video input, delegate to `VideoProcessor` |

No changes to `CompositionLayer` — the layer stack is media-agnostic.

## CLI Integration

Single `process` command auto-detects image vs video by file extension/UTI. Video-specific flags are ignored for images.

```
--trim 00:00:05.000-00:00:30.000   # optional timecode range
--codec h264|h265                   # default: h264
```

- Batch: video files processed sequentially, frames pipelined within each video. Images continue parallel processing.
- Progress: frame counter with percentage — `Processing: frame 120/3600 (3%)`

## SwiftUI App Integration

| Element | Description |
|---------|-------------|
| **Timeline scrubber** | iMovie-style bar with draggable in/out handles, frame thumbnail strip, playhead |
| **Video preview** | Single frame at playhead processed through CI pipeline (full render on export only) |
| **Output dimensions badge** | Shows computed `WxH` for both images and video, updates live as layers change |
| **Codec picker** | Dropdown in export settings: H.264 / H.265 |
| **Progress indicator** | Frame-level progress bar during export |

Timeline thumbnails generated via `AVAssetImageGenerator` at regular intervals.

## Audio

Original audio track passed through (re-muxed), trimmed to match video trim range. If no audio track exists, proceed silently without audio.

## Error Handling

| Scenario | Handling |
|----------|----------|
| Unsupported input format | Fail early with clear error |
| Trim range exceeds duration | Clamp to actual duration, warn user |
| Trim start >= trim end | Validation error |
| No video track | Error: "File contains no video track" |
| No audio track | Proceed without audio passthrough |
| Export cancelled | Clean up partial output file |
| Memory pressure | AVAssetReader/Writer stream frame-by-frame, no buffering |
| HEVC not available | Check `VTIsHardwareDecodeSupported`, fall back to H.264 with warning |
