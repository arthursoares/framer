# Metal GPU Dithering — Implementation Plan

> **Status:** Planned
> **Branch:** `feat/metal-dither` (not yet created)
> **Scope:** Move ordered dithering algorithms to Metal compute shaders

---

## Why

The 4 ordered dithering algorithms (Bayer, blue noise, halftone, white noise) are embarrassingly parallel — each pixel's threshold is independent of its neighbors. Metal compute shaders can process millions of pixels simultaneously on the GPU, providing 10-50× speedup over CPU for large images.

Error diffusion algorithms (Floyd-Steinberg, Atkinson, Stucki, artistic drip, Riemersma) are inherently sequential and stay on CPU.

---

## Architecture

```
DitherRenderer.apply()
  ├── GPU path (ordered algorithms)
  │   └── MetalDitherPipeline
  │       ├── Upload: CGImage → MTLTexture
  │       ├── Dispatch 1: Sharpen + Contrast (optional)
  │       ├── Dispatch 2: Ordered dither (Bayer/BlueNoise/Halftone/WhiteNoise)
  │       ├── Dispatch 3: Color mapping (two-tone, dominant)
  │       └── Readback: MTLTexture → CGImage
  │
  └── CPU path (error diffusion — unchanged)
      └── Existing DitherRenderer code
```

Single GPU pipeline avoids CPU↔GPU round-trips. All preprocessing (sharpen, contrast LUT) and postprocessing (two-tone mapping) happen on-device.

---

## Files to Create

| File | Purpose |
|------|---------|
| `Sources/FramerCore/Processing/Metal/DitherShaders.metal` | Compute kernels for all 4 ordered algorithms + sharpen + contrast + color mapping |
| `Sources/FramerCore/Processing/Metal/MetalDitherPipeline.swift` | Pipeline setup, texture management, dispatch, readback |

## Files to Modify

| File | Changes |
|------|---------|
| `Sources/FramerCore/Processing/DitherRenderer.swift` | Route ordered algorithms to `MetalDitherPipeline`, keep error diffusion on CPU |
| `Package.swift` | No changes needed — Metal is a system framework |
| `project.yml` | Add `.metal` files to FramerCore sources |

---

## Metal Shader Design

### Kernel 1: `dither_sharpen`
- Input: RGBA texture
- 3×3 box convolution + unsharp mask in a single pass
- Output: sharpened RGBA texture (in-place or separate)

### Kernel 2: `dither_contrast`
- Input: RGBA texture + 256-entry LUT buffer
- Apply S-curve LUT to R, G, B channels
- Output: contrast-enhanced RGBA texture

### Kernel 3: `dither_ordered` (parameterized)
- Input: RGBA texture + threshold matrix buffer + params buffer
- Params: algorithm type, matrix size, levels count, color mode (BW/color)
- For BW: compute luminance → compare against threshold → output 0 or 255
- For color: compare each channel against threshold → quantize to N levels
- Threshold matrices passed as MTLBuffer:
  - Bayer: level 1-4 matrices (4×4 to 32×32), tiled via `gid % size`
  - Blue noise: 64×64 R2 texture, tiled via `gid & 63`
  - Halftone: 6×6 clustered dot, tiled via `gid % 6`
  - White noise: GPU-side hash function (no matrix needed)

### Kernel 4: `dither_twotone_map`
- Input: dithered BW texture + foreground RGBA + background RGBA
- Map 0→background, 255→foreground
- Branchless: `color = bg + (fg - bg) * (pixel >> 7)`

### Fused kernel: `dither_ordered_full`
- Combines sharpen + contrast + dither + color mapping in one dispatch
- Reduces memory bandwidth by avoiding intermediate texture writes
- Thread group size: 16×16 (256 threads, fits in one SIMD group on Apple Silicon)

---

## Pipeline Management

```swift
actor MetalDitherPipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private var pipelineStates: [String: MTLComputePipelineState]
    
    // Pre-uploaded threshold matrices (persistent)
    private var bayerBuffers: [MTLBuffer]  // levels 1-4
    private var blueNoiseBuffer: MTLBuffer  // 64×64
    private var halftoneBuffer: MTLBuffer   // 6×6
    
    func apply(to image: CGImage, params: DitherLayerParams, ...) throws -> CGImage
}
```

- `MTLDevice` and `MTLCommandQueue` created once, reused across calls
- Threshold matrices uploaded once at init, never re-uploaded
- Contrast LUT uploaded per-call (depends on `amount` parameter)
- Texture allocation via `MTLTextureDescriptor` with `.storageModeShared` for zero-copy on Apple Silicon

---

## Fallback Strategy

```swift
// In DitherRenderer.apply()
let isOrdered = [.bayer, .blueNoise, .halftone, .whiteNoise].contains(algorithm)

if isOrdered, let pipeline = MetalDitherPipeline.shared {
    return try pipeline.apply(to: image, params: params, ...)
} else {
    // CPU fallback (existing code)
    return try applyCPU(to: image, params: params, ...)
}
```

Metal is optional — if `MTLCreateSystemDefaultDevice()` returns nil (e.g., in tests, CI without GPU), the CPU path runs unchanged.

---

## Performance Expectations

| Image Size | CPU (current) | GPU (expected) | Speedup |
|-----------|---------------|----------------|---------|
| 1200×800 (preview) | ~15ms | ~2ms | ~7× |
| 4000×3000 (export) | ~120ms | ~5ms | ~24× |
| 6000×4000 (hi-res) | ~300ms | ~8ms | ~37× |

Estimates based on Apple Silicon GPU throughput for simple per-pixel operations. The bottleneck shifts to texture upload/readback at small sizes.

---

## Implementation Order

1. Create `MetalDitherPipeline` with device/queue setup and texture conversion helpers
2. Implement `dither_ordered` kernel for Bayer (simplest — fixed matrix, power-of-2 tiling)
3. Wire up in `DitherRenderer` with CPU fallback
4. Benchmark: verify correctness (pixel-identical output) and measure speedup
5. Add blue noise, halftone, white noise kernels
6. Add sharpen + contrast kernels
7. Create fused `dither_ordered_full` kernel
8. Add color mode support (quantized levels)
9. Add two-tone color mapping kernel

Each step should be a separate commit with the app remaining functional throughout.

---

## Risks

- **Visual parity**: GPU floating-point precision differs from CPU Double. Need to verify output matches within ±1 per channel.
- **Metal shader compilation**: `.metal` files in a Swift Package require special handling — may need to embed as a string or use a `.metallib` bundle resource.
- **Memory pressure on iOS**: large textures on older devices. The `.storageModeShared` on Apple Silicon avoids copies, but `.storageModeManaged` is needed on Intel Macs.
- **Thread group size**: must be tuned per device. 16×16 is safe for all Apple GPUs but may not be optimal.
