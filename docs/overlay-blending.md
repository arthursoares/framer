# Texture Overlay Blending

## How It Works

Framer supports texture overlays — artistic effects that composite film borders, dust, light leaks, and wet plate textures over your photos. The overlays are standard image files (JPEG/PNG/TIFF) that use a **luminance-deviation-from-gray** alpha blending technique.

### The Algorithm

```
For each pixel in the overlay image:
  1. Compute luminance:  L = 0.299 × R + 0.587 × G + 0.114 × B
  2. Compute alpha:      α = |L - 0.5| × 2.0 × opacity
  3. Premultiply:        R' = R × α,  G' = G × α,  B' = B × α
  4. Composite over the original photo using standard alpha blending
```

### What This Means

| Overlay pixel color | Luminance | Alpha | Effect |
|---|---|---|---|
| Mid-gray (128, 128, 128) | 0.5 | 0.0 | Fully transparent — photo shows through |
| Pure white (255, 255, 255) | 1.0 | 1.0 | Fully opaque — white overlay visible |
| Pure black (0, 0, 0) | 0.0 | 1.0 | Fully opaque — black overlay visible |
| Light gray (192, 192, 192) | ~0.75 | ~0.5 | Semi-transparent light effect |
| Dark gray (64, 64, 64) | ~0.25 | ~0.5 | Semi-transparent dark effect |

This allows a single image to encode both the overlay pattern and its transparency:
- **Gray centers** = invisible (photo shows through)
- **Bright/dark edges** = visible overlay (frame texture, dust specks, light leaks)

### Processing Pipeline

```
┌─────────────────┐
│  Load overlay    │  (from ~/Library/Application Support/Framer/overlays/
│  image file      │   or Nik Collection directory)
└────────┬────────┘
         │
┌────────▼────────┐
│  Scale to match  │  Resize overlay to exact dimensions of current image
│  photo size      │  (bicubic interpolation)
└────────┬────────┘
         │
┌────────▼────────┐
│  Compute per-    │  For each of W×H pixels:
│  pixel alpha     │  - Read RGB from overlay
│  from luminance  │  - L = 0.299R + 0.587G + 0.114B
│                  │  - α = |L - 0.5| × 2.0 × opacity
│                  │  - Premultiply RGB by α
└────────┬────────┘
         │
┌────────▼────────┐
│  Composite       │  Draw original photo, then draw
│  overlay on top  │  alpha-masked overlay on top
└────────┬────────┘
         │
┌────────▼────────┐
│  Result: photo   │
│  with texture    │
└─────────────────┘
```

## Overlay Categories

Overlays are automatically categorized by filename prefix:

| Prefix | Category | Description |
|---|---|---|
| `frame_*`, `frame__*` | **Frame** | Film borders, Polaroid edges, darkroom frames. Affect the edges of the image (gray center, textured borders). |
| `dirt__*` | **Dust & Scratches** | Surface textures — film dust particles, scratches, grime. Cover the entire image surface. |
| `leak__*` | **Light Leak** | Light leak effects — bright streaks and color shifts simulating film camera light leaks. |
| `plate__*` | **Wet Plate** | Tintype and wet plate collodion effects — chemical stains, uneven coating, edge artifacts. |

## Overlay Sources

Framer discovers overlays from these directories:

1. **User overlays:** `~/Library/Application Support/Framer/overlays/`
   - Place your own overlay images here (any name, any format)
   - Create overlays using the mid-gray = transparent convention

2. **Nik Collection:** `/Library/Application Support/DxO/Frameworks/data/NikEfex/AnalogEfex/`
   - Automatically discovered if Nik Collection is installed
   - 72 frames + 50 dust + 56 light leaks + 21 wet plates = 199 overlays

## Creating Custom Overlays

To create your own overlay:

1. Start with a mid-gray image (RGB 128, 128, 128)
2. Paint your effect — the further from gray, the more opaque:
   - White areas → bright overlay (highlights, light leaks)
   - Black areas → dark overlay (shadows, burn edges, vignettes)
   - Gray areas → transparent (photo shows through)
3. Save as JPEG or PNG
4. Place in `~/Library/Application Support/Framer/overlays/`
5. Name with a prefix to categorize: `frame_`, `dirt__`, `leak__`, or `plate__`

## Layer Stack Integration

Overlays work as layers in the composition stack. They can be placed at any position:

```yaml
layers:
  - type: border
    thickness: "20"
    color: "#FFFFFF"
  - type: overlay
    overlay_name: "frame__fls130916_pola55-2"
    overlay_kind: "frame"
    opacity: 80
  - type: padding
    thickness: "100"
    fill: color
    fill_color: "#FFFFFF"
```

The overlay composites onto whatever the current image state is at that point in the layer stack. This means:
- **Before borders/padding:** overlay applies to the raw photo
- **After borders/padding:** overlay covers the framed result (including borders)
