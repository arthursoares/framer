# Troubleshooting & Known Issues

## Current Technical Debt

### Dead Code
**Location**: framer.go:188-190
**Issue**: Leftover comments about removed blur/vintage functions
**Impact**: Code clarity
**Fix**: Delete commented lines

**Location**: framer.go:87-103
**Function**: `padWithBorder()`
**Issue**: Function defined but never called anywhere in codebase
**Impact**: Maintenance overhead, confusion
**Fix**: Either remove if truly unused, or integrate into border rendering pipeline

### Missing Resources
**Location**: framer.go:28
**Issue**: `AmericanTypewriter` font listed in `availableFonts` array but missing from `fonts_data/` directory
**Impact**: Will cause runtime error if user selects this font
**Fix**: Either add the font file or remove from array

### Error Handling Gaps

**Location**: framer.go:424
**Code**: `t, _ = strconv.Atoi(args.borderThickness)`
**Issue**: Ignored error could cause silent failures with invalid input
**Impact**: Invalid border thickness (e.g., "abc") results in 0, not user-friendly error
**Fix**: Handle error and provide clear validation message

**Location**: framer.go:428
**Code**: `p, _ = strconv.Atoi(args.padding)`
**Issue**: Same as above for padding value
**Impact**: Invalid padding silently becomes 0
**Fix**: Validate and provide error message

**Location**: framer.go:459
**Code**: `computedFontSize, _ = strconv.Atoi(args.fontSize)`
**Issue**: Same as above for font size
**Impact**: Invalid font size silently becomes 0, may cause rendering issues
**Fix**: Validate numeric input with proper bounds checking

**Location**: framer.go:431, 470
**Code**: `borderColor, _ = hexToRGB(args.borderColor)`
**Issue**: Ignored error from color parsing
**Impact**: Invalid hex color (e.g., "#zzz") fails silently, results in black (zero value)
**Fix**: Return error to user with example of valid format

## Code Structure Issues

### Anonymous Struct Anti-pattern
**Location**: framer.go:545-555, 373-383
**Issue**: Processing configuration defined as anonymous struct, duplicated in function signature
**Impact**:
- Cannot reuse type definition
- No type safety
- Harder to test
- Unclear API boundaries

**Fix**: Extract to named type:
```go
type ProcessingConfig struct {
    Caption          string
    BorderThickness  string
    Padding          string
    BorderStyle      string
    BorderColor      string
    FontName         string
    FontSize         string
    FontColor        string
    InstagramMaxSize int
}
```

### Long Function
**Location**: framer.go:373-501
**Function**: `processImage()`
**Issue**: 128 lines, does too many things (opening, parsing, EXIF extraction, border creation, caption rendering, saving)
**Impact**: Hard to test, modify, and understand
**Fix**: Split into focused functions:
- `loadImage(path string) (image.Image, error)`
- `extractCaption(file *os.File, config ProcessingConfig) string`
- `calculateBorderThickness(size image.Point, thickness string) (int, error)`
- `calculateFontSize(borderThickness int, fontSize string) (int, error)`
- `applyBorder(img image.Image, config ProcessingConfig) (image.Image, image.Point, *image.Point)`
- `saveImage(img image.Image, path string, quality int) error`

## Configuration Issues

### ✅ Magic Numbers (RESOLVED)
**Location**: Various
**Issue**: Hardcoded values scattered throughout code
**Status**: ✅ **RESOLVED** in Branch 3 (refactor/constants-config)

**Solution Implemented**:
```go
const (
    InstagramFrameWidth  = 1080
    InstagramFrameHeight = 1350
    DefaultJPEGQuality   = 100
    MinJPEGQuality       = 60
    MaxJPEGQuality       = 100
    DefaultDPI           = 72
    SmallFontScale       = 0.5
    MediumFontScale      = 0.7
    LargeFontScale       = 0.9
    SmallBorderThreshold  = 40
    MediumBorderThreshold = 80
    AlphaOpaque          = 255
)
```

### ✅ Hardcoded Caption Format (RESOLVED)
**Location**: Previously framer.go:84
**Issue**: Caption format was hardcoded, users could not customize
**Status**: ✅ **RESOLVED** in Branch 6 (feature/caption-templates)

**Solution Implemented**:
- Added `--caption-template` flag with {{field}} placeholder system
- Template supports: {{year}}, {{year2}}, {{month}}, {{mon}}, {{day}}, {{date}}, {{camera}}, {{lens}}, {{iso}}, {{aperture}}, {{shutter}}, {{focal}}
- Comprehensive EXIF extraction (getExifData) for metadata
- Default vintage format preserved: " - MON 'YY -"

**Example Usage**:
```bash
./framer -i photo.jpg -o out/ --caption-template "{{camera}} • {{iso}} {{aperture}} {{shutter}}"
```

### ✅ No Config File Support (RESOLVED)
**Issue**: Complex configurations required many CLI flags
**Status**: ✅ **RESOLVED** in Branch 7 (feature/config-presets)

**Solution Implemented**:
- YAML config file support with priority-based loading
- Auto-created presets directory: ~/.config/framer/presets/
- Three default presets: vintage, instagram, minimal
- CLI flags override config values (explicit > implicit)
- Automatic .framer.yaml loading from current directory

**Priority Order**:
1. `--config` flag
2. `--preset` flag
3. `./.framer.yaml`
4. `~/.config/framer/default.yaml`

**Example Preset**:
```yaml
# ~/.config/framer/presets/vintage.yaml
border_style: solid
border_thickness: "20"
border_color: "#000000"
padding: "150"
font_name: CourierPrime-Bold
font_size: "50"
caption_template: " - {{mon}} '{{year2}} -"
```

## Performance Considerations

### No Concurrent Processing
**Location**: framer.go:615-626
**Issue**: Directory processing is sequential, one image at a time
**Impact**: Slow for large batches, doesn't utilize multi-core systems
**Fix**: Implement worker pool with goroutines:
```go
// Process images concurrently with worker pool
jobs := make(chan string, numWorkers)
var wg sync.WaitGroup
for i := 0; i < numWorkers; i++ {
    wg.Add(1)
    go worker(jobs, &wg, config)
}
```

### No Progress Indication
**Location**: Batch processing
**Issue**: No feedback during long-running batch operations
**Impact**: Poor user experience, appears frozen
**Fix**: Add progress bar using `github.com/schollz/progressbar/v3`

## Testing Gaps

### No Unit Tests
**Issue**: Zero test coverage for any functionality
**Impact**:
- Risk of regressions when refactoring
- Unclear if edge cases are handled
- Hard to validate fixes

**Fix**: Start with critical functions:
- `hexToRGB()` - color parsing
- `generateCaptionFromDate()` - date formatting
- `loadFont()` - font loading with fallbacks
- Border calculation logic

### No Integration Tests
**Issue**: No tests with actual image processing
**Impact**: Cannot verify end-to-end functionality
**Fix**: Create test suite with sample images in `testdata/` directory

### No Benchmarks
**Issue**: No performance baselines
**Impact**: Cannot measure optimization improvements
**Fix**: Add benchmarks for image processing pipeline

## Config System Considerations (New)

### Config File Discovery
**Behavior**: Multiple config files can exist, priority determines which loads
**Potential Issue**: User may not realize which config file is being used
**Mitigation**: Log message shows which config was loaded
**Example**:
```
2025/10/11 00:19:08 Loaded preset: vintage
```

**Tips for Users**:
- Use `--config` flag to be explicit about config source
- Delete/rename `.framer.yaml` to prevent auto-loading
- Check log output to confirm which config loaded

### Font Validation
**Behavior**: Invalid font names automatically fall back to default with warning
**Potential Issue**: User may not notice their font choice was ignored
**Mitigation**: Clear warning logged to console
**Example**:
```
Warning: Font "InvalidFont" not found in embedded fonts, using default "CourierPrime-Bold"
```

**Solution**: Use `./framer --list-fonts` to see available options

### CLI Override Behavior
**Behavior**: CLI flags override config file values
**Potential Issue**: Default CLI values (e.g., `--border-style solid`) override config
**Current Limitation**: Cannot distinguish "user specified solid" from "defaulted to solid"
**Workaround**: Config file values only used when CLI value exactly matches default

**Example**:
```bash
# Config has border_style: instagram
./framer -i photo.jpg -o out/  # Uses instagram from config ✓
./framer -i photo.jpg -o out/ --border-style solid  # Uses CLI solid ✓
```

### Preset Modification
**Behavior**: Default presets only created if they don't exist
**Benefit**: User modifications preserved across runs
**Consideration**: Deleted presets won't auto-restore
**Solution**: Delete `~/.config/framer/` directory to reset all presets

### YAML Syntax Errors
**Behavior**: Invalid YAML causes config loading to fail silently
**Current Behavior**: Falls through to next priority level or defaults
**Example**:
```
Warning: Could not load config file my-config.yaml: parsing YAML: ...
```

**Common YAML Mistakes**:
- Missing quotes around hex colors: `border_color: #FF0000` (wrong)
- Correct: `border_color: "#FF0000"`
- Wrong indentation (YAML is whitespace-sensitive)
- Mixing tabs and spaces

## Common User Issues (Anticipated)

### Issue: "Font not found" errors
**Cause**: Font name doesn't match embedded fonts (case-sensitive)
**Solution**: Run `./framer --list-fonts` to see available options

### Issue: Caption doesn't appear
**Cause**: Border too thin for calculated font size
**Solution**: Increase border thickness or manually set `--font-size`

### Issue: Invalid color format
**Cause**: Hex color format incorrect (missing #, wrong length)
**Solution**: Use format `#RRGGBB` (e.g., `#FF0000` for red)

### Issue: Output quality looks compressed
**Cause**: JPEG quality hardcoded to 100
**Solution**: (Future) Add `--quality` flag once implemented

## Proven Solutions

### Font Loading Fallback Chain
The `loadFont()` function implements a robust fallback:
1. Try requested font as .ttf
2. Try requested font as .ttc
3. Fall back to default font
4. If all fail, use pixel-based fallback rendering

This prevents crashes but could be improved with better error messages to users.

### Percentage-based Border Thickness
Using percentage (e.g., "5%") works well for different image sizes:
```bash
./framer -i image.jpg -o output/ -t 5%
```
Calculates based on minimum dimension, maintaining proportions.
