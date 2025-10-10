# Architecture Decisions & Rationale

## Design Philosophy

### Single Binary Approach
**Decision**: Embed all fonts and resources into single executable using go-bindata
**Rationale**:
- Simplifies distribution (no external dependencies)
- No installation required beyond copying binary
- Fonts guaranteed available at runtime
- Aligns with Go's philosophy of static compilation

**Trade-offs**:
- ✅ Easy deployment
- ✅ No missing resource errors
- ❌ Larger binary size (~5MB with fonts)
- ❌ Must recompile to add fonts

### CLI-First Design
**Decision**: Command-line interface as primary interaction method
**Rationale**:
- Target users: photographers processing Lightroom exports
- Batch processing is primary use case
- Scriptable and automatable workflows
- Fits Unix philosophy: do one thing well

**Future**: Web interface could be added without changing core logic

## Image Processing Architecture

### Two-Style Border System
**Decision**: Implement separate functions for "solid" and "instagram" borders
**Rationale**:
- Different rendering strategies required
- Instagram needs fixed aspect ratio (4:5) and centering
- Solid preserves original dimensions
- Clean separation of concerns

**Current Implementation**:
```go
createSolidBorder()     // Preserves original size
createInstagramFrame()  // Fixed 1080x1350 frame
```

**Future Consideration**: Style registry pattern for extensibility:
```go
type BorderStyle interface {
    Render(img image.Image, config BorderConfig) (image.Image, error)
}
```

### Caption Rendering Strategy
**Decision**: Use TrueType fonts with pixel-based fallback
**Rationale**:
- TrueType provides high-quality text rendering
- Fallback ensures graceful degradation if font loading fails
- Pixel-based rendering simple but readable for short captions

**Implementation Details**:
- Primary: `github.com/golang/freetype` for TrueType rendering
- Fallback: Manual pixel drawing with character-specific shapes
- Both use same positioning logic for consistency

## Configuration Management

### Flag-Based Configuration (Current)
**Decision**: Use Go's `flag` package for CLI arguments
**Rationale**:
- Standard library, no external dependencies
- Simple for basic use cases
- Self-documenting via `flag.Usage()`

**Limitations Identified**:
- No preset/config file support
- Verbose for complex configurations
- No validation layer

**Planned Evolution**: Add config file support while maintaining flag compatibility:
```bash
# Current
./framer -i img.jpg -o out/ -t 5% --border-color "#000" --font-size 50

# Future (backwards compatible)
./framer -i img.jpg -o out/ --preset vintage.yaml
```

### Style-Specific Defaults
**Decision**: Apply different default values based on selected border style
**Location**: framer.go:567-597
**Rationale**:
- Instagram style needs smaller borders (5px vs 20px)
- Instagram needs smaller fonts (20px vs 50px)
- Solid style benefits from padding (150px), Instagram doesn't

**Current Logic**:
```go
if borderStyle == "instagram" {
    defaultBorderThickness = "5"
    defaultFontSize = "20"
    defaultPadding = "0"
} else {
    defaultBorderThickness = "20"
    defaultFontSize = "50"
    defaultPadding = "150"
}
```

**Improvement Needed**: Extract to style configuration structs

## Error Handling Philosophy

### Current Approach (Needs Improvement)
**Decision**: Log errors and continue processing
**Location**: `processImage()` function
**Rationale**:
- Batch processing shouldn't fail entirely on one bad image
- User gets feedback via logs for each file
- Partial success better than complete failure

**Issues**:
- Silent failures for parsing errors (ignored `strconv` errors)
- No error summary at end of batch
- No way to distinguish warnings from failures

### Planned Improvement
**Decision**: Implement tiered error handling:
1. **Fatal errors**: Stop processing (missing input path, can't create output dir)
2. **File errors**: Skip file, log error, continue batch (corrupt JPEG, missing EXIF)
3. **Warnings**: Process with fallback, log warning (font not found, invalid color)
4. **Summary**: Report statistics at end (X succeeded, Y failed, Z warnings)

## EXIF Handling

### Date Extraction Only
**Decision**: Currently only extract DateTimeOriginal field
**Rationale**:
- Primary use case: vintage-style date stamps
- Matches inspiration from grandfather's photos
- Simple, focused feature

**Future Expansion**:
- Camera model
- Exposure settings (ISO, aperture, shutter speed)
- Location data (GPS)
- Custom template system: `"{{camera}} • {{iso}} • {{location}}"`

## Font Management

### Embedded Font List
**Decision**: Maintain explicit `availableFonts` array in code
**Location**: framer.go:26-31
**Rationale**:
- Clear source of truth for available fonts
- Easy to validate user input
- Powers `--list-fonts` feature

**Problem Identified**:
- Array can drift from actual files in `fonts_data/`
- Manual sync required when adding fonts
- `AmericanTypewriter` listed but missing

**Future Solution**: Auto-discover fonts from embedded assets:
```go
func getAvailableFonts() []string {
    fonts := []string{}
    for _, name := range AssetNames() {
        if strings.HasPrefix(name, "fonts_data/") {
            // Extract font name from path
            fonts = append(fonts, ...)
        }
    }
    return fonts
}
```

## File Format Support

### JPEG-Only Input (Current)
**Decision**: Only support JPEG input files
**Location**: framer.go:393, 620-621
**Rationale**:
- Target use case: Lightroom exports (typically JPEG)
- Simplifies decoding logic
- Project scope: quick personal tool

**Identified Limitation**:
- Cannot process PNG, TIFF, or RAW files
- Hardcoded `jpeg.Decode()` prevents format expansion

**Migration Path**:
```go
// Current
img, err := jpeg.Decode(file)

// Future (format-agnostic)
img, _, err := image.Decode(file)
```

### JPEG-Only Output (Current)
**Decision**: Always output JPEG at quality 100
**Location**: framer.go:494
**Rationale**:
- Maintains compatibility with input format
- Quality 100 preserves maximum detail
- Simple implementation

**Planned Enhancement**:
- Add PNG output for lossless quality
- Make JPEG quality configurable (60-100 range)
- Add `--output-format` and `--quality` flags

## Performance Decisions

### Sequential Processing (Current)
**Decision**: Process images one at a time
**Rationale**:
- Simple implementation
- Predictable behavior
- Lower memory usage

**When to Parallelize** (Future):
- Benefit significant for >10 images
- Use worker pool pattern (limit concurrency)
- Add `--workers N` flag (default: NumCPU)

### Quality Over Speed
**Decision**: Use Lanczos resampling for Instagram resizing
**Location**: framer.go:121
**Rationale**:
- Highest quality resize algorithm
- Acceptable speed for intended use case (manual processing)
- Aligns with photography/quality focus

**Alternative Considered**: `imaging.NearestNeighbor` for speed, rejected for quality loss

## Testing Strategy (Planned)

### Test Data Approach
**Decision**: Use `testdata/` directory with sample images
**Rationale**:
- Go convention for test fixtures
- Allows visual verification
- Supports integration tests
- Can include various aspect ratios, sizes, EXIF scenarios

### What to Test
**Priority 1**: Pure functions without I/O
- `hexToRGB()` - color parsing
- `generateCaptionFromDate()` - date formatting
- Border calculation logic

**Priority 2**: Integration tests
- Full pipeline with sample images
- Verify output dimensions and file creation

**Priority 3**: Benchmarks
- Image processing throughput
- Memory allocation patterns

## Extensibility Considerations

### Plugin Architecture (Future)
Not currently needed, but design could evolve toward:
```go
type BorderRenderer interface {
    Name() string
    Render(img image.Image, config Config) (image.Image, error)
}

// Register custom border styles
RegisterBorderStyle("filmstrip", &FilmStripRenderer{})
RegisterBorderStyle("double", &DoubleBorderRenderer{})
```

### Template System (Future)
Caption customization via templates:
```go
type CaptionTemplate struct {
    Format   string // "{{month}} '{{year}} • {{camera}}"
    Position string // "bottom", "top", "left", "right"
    Style    CaptionStyle
}
```

## Migration Safety

### Breaking Changes to Avoid
- CLI flag names (maintain compatibility)
- Output filename format (predictable for automation)
- Default behavior (users rely on current defaults)

### Safe Evolution Path
1. Add new flags with sensible defaults
2. Deprecate old behavior with warnings
3. Remove after grace period (major version bump)
4. Always maintain backwards compatibility within major version
