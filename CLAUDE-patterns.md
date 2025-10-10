# Code Patterns & Conventions

## Established Patterns

### Error Handling Pattern
**Current Standard** (needs improvement):
```go
// In processImage - log and return
if err != nil {
    log.Printf("Error opening file %s: %v", imagePath, err)
    return
}
```

**Preferred Pattern** (for new code):
```go
// Return errors to caller for better composability
func loadImage(path string) (image.Image, error) {
    file, err := os.Open(path)
    if err != nil {
        return nil, fmt.Errorf("opening file: %w", err)
    }
    defer file.Close()

    img, err := jpeg.Decode(file)
    if err != nil {
        return nil, fmt.Errorf("decoding JPEG: %w", err)
    }

    return img, nil
}
```

### Color Handling Pattern
**Standard**: All colors as hex strings, converted to `color.RGBA`
```go
// User input: "#FF0000"
// Conversion: hexToRGB("#FF0000") -> color.RGBA{R: 255, G: 0, B: 0, A: 255}
```

**Usage**:
```go
borderColor, err := hexToRGB(args.borderColor)
if err != nil {
    return fmt.Errorf("invalid border color: %w", err)
}
```

### Image Drawing Pattern
**Standard**: Use `image/draw` package for compositing
```go
// 1. Create new RGBA image
newImg := image.NewRGBA(image.Rect(0, 0, width, height))

// 2. Fill with background color
draw.Draw(newImg, newImg.Bounds(), &image.Uniform{bgColor}, image.Point{}, draw.Src)

// 3. Draw original image at position
draw.Draw(newImg, image.Rect(x, y, x+w, y+h), srcImg, image.Point{}, draw.Src)
```

### Font Loading Pattern
**Standard**: Try multiple extensions with fallback chain
```go
// 1. Try .ttf
fontData, err = Asset(fmt.Sprintf("fonts_data/%s.ttf", fontName))
if err == nil {
    foundFont = true
}

// 2. Try .ttc
if !foundFont {
    fontData, err = Asset(fmt.Sprintf("fonts_data/%s.ttc", fontName))
    if err == nil {
        foundFont = true
    }
}

// 3. Fall back to default font
if !foundFont && fontName != availableFonts[0] {
    // Load default...
}
```

## File Organization

### Single Package Structure
**Current**: Everything in `main` package
```
framer/
├── framer.go       # All application logic
├── fonts.go        # Generated embedded fonts (don't edit)
├── fonts_data/     # Source font files
└── go.mod
```

**Rationale**: Simple CLI tool doesn't require package separation yet

**Future Refactoring** (when >1000 LOC):
```
framer/
├── cmd/framer/
│   └── main.go           # CLI entry point
├── pkg/
│   ├── border/           # Border rendering
│   ├── caption/          # Caption rendering
│   ├── config/           # Configuration
│   └── image/            # Image processing
├── internal/
│   └── fonts/            # Font management
└── testdata/             # Test fixtures
```

## Naming Conventions

### Functions
- **Action-oriented**: `createSolidBorder`, `addCaption`, `generateCaptionFromDate`
- **Get prefix**: For simple accessors - `getExifDate`, `getAvailableFonts`
- **Avoid**: Generic names like `process`, `handle`, `do`

### Variables
- **Abbreviated dimensions**: `w`, `h` for width/height in image functions
- **Full names elsewhere**: `borderThickness`, `fontSize`, `captionText`
- **Config structs**: Use full field names - `BorderColor`, `FontName`

### Constants (to be established)
```go
const (
    // Use descriptive names with context
    DefaultJPEGQuality       = 100
    InstagramFrameWidth      = 1080
    InstagramFrameHeight     = 1350

    // Border styles
    BorderStyleSolid         = "solid"
    BorderStyleInstagram     = "instagram"
)
```

## Code Style

### Function Length
- **Target**: ≤50 lines per function
- **Maximum**: 100 lines before mandatory split
- **Current violation**: `processImage()` at 128 lines - needs refactoring

### Function Parameters
- **Maximum**: 5 parameters before using config struct
- **Current violation**: `addCaption()` has 9 parameters - needs config struct

**Refactor Example**:
```go
// Before
func addCaption(newImage *image.RGBA, captionText string, fontSize int,
    fontColor color.RGBA, imageSize image.Point, borderThickness int,
    padding int, imagePos *image.Point, fontName string) *image.RGBA

// After
type CaptionConfig struct {
    Text           string
    FontSize       int
    FontColor      color.RGBA
    FontName       string
    ImageSize      image.Point
    BorderThickness int
    Padding        int
    ImagePos       *image.Point
}

func addCaption(img *image.RGBA, config CaptionConfig) *image.RGBA
```

### Error Messages
- **Format**: Lowercase, no trailing punctuation
- **Include context**: What operation failed
- **Include specifics**: File names, values, etc.

```go
// Good
return fmt.Errorf("opening file %s: %w", path, err)
return fmt.Errorf("invalid hex color %q: must be 6 digits", hexColor)

// Avoid
return fmt.Errorf("Error: %v", err)
return errors.New("Something went wrong")
```

## Testing Patterns (To Be Established)

### Test File Naming
```
framer_test.go       # Tests for framer.go
font_test.go         # Future: tests for font handling
border_test.go       # Future: tests for border rendering
```

### Table-Driven Tests (Preferred)
```go
func TestHexToRGB(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    color.RGBA
        wantErr bool
    }{
        {
            name:  "valid black",
            input: "#000000",
            want:  color.RGBA{R: 0, G: 0, B: 0, A: 255},
        },
        {
            name:  "valid red",
            input: "#FF0000",
            want:  color.RGBA{R: 255, G: 0, B: 0, A: 255},
        },
        {
            name:    "invalid length",
            input:   "#FFF",
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := hexToRGB(tt.input)
            if (err != nil) != tt.wantErr {
                t.Errorf("hexToRGB() error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            if !tt.wantErr && got != tt.want {
                t.Errorf("hexToRGB() = %v, want %v", got, tt.want)
            }
        })
    }
}
```

### Test Helpers
```go
// Helper for creating test images
func createTestImage(t *testing.T, width, height int) image.Image {
    t.Helper()
    img := image.NewRGBA(image.Rect(0, 0, width, height))
    // Fill with test pattern...
    return img
}

// Helper for comparing images
func assertImageEquals(t *testing.T, got, want image.Image) {
    t.Helper()
    // Compare dimensions and pixels...
}
```

## Configuration Patterns

### CLI Flag Pattern (Current)
```go
// Define both long and short forms
flag.String("border-style", "solid", "Border style: 'solid' or 'instagram'")
flag.StringVar(borderStyle, "s", "solid", "Border style (shorthand)")
```

### Config Struct Pattern (Planned)
```go
type Config struct {
    // Input/Output
    InputPath  string
    OutputPath string

    // Border
    BorderStyle     string
    BorderThickness string  // "5" or "10%"
    BorderColor     string  // "#000000"

    // Caption
    Caption   string
    FontName  string
    FontSize  string
    FontColor string

    // Style-specific
    InstagramMaxSize int
    Padding          string
}

// Validation method
func (c *Config) Validate() error {
    if c.InputPath == "" {
        return errors.New("input path required")
    }
    // ... more validation
    return nil
}
```

## Concurrency Patterns (Future)

### Worker Pool for Batch Processing
```go
type job struct {
    inputPath  string
    outputPath string
    config     Config
}

func processBatch(jobs []job, numWorkers int) {
    jobChan := make(chan job, len(jobs))
    var wg sync.WaitGroup

    // Start workers
    for i := 0; i < numWorkers; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            for job := range jobChan {
                processImage(job.inputPath, job.outputPath, job.config)
            }
        }()
    }

    // Send jobs
    for _, j := range jobs {
        jobChan <- j
    }
    close(jobChan)

    wg.Wait()
}
```

## Documentation Patterns

### Function Comments
```go
// generateCaptionFromDate creates a vintage-style caption from a date.
// Format: " - MON 'YY -" (e.g., " - JAN '23 -")
// Returns " - --- -" if date is zero value.
func generateCaptionFromDate(dt time.Time) string {
    // ...
}
```

### Package-Level Documentation (Future)
```go
// Package border provides various border rendering styles for images.
//
// Supported styles:
//   - solid: Colored border with optional padding
//   - instagram: Fixed 4:5 ratio frame (1080x1350px)
//
// Example:
//   img := loadImage("photo.jpg")
//   bordered := border.CreateSolid(img, 20, color.Black, 100)
package border
```

## Anti-Patterns to Avoid

### ❌ Silent Failures
```go
// Bad: Swallowing errors
value, _ := strconv.Atoi(input)

// Good: Handle or propagate
value, err := strconv.Atoi(input)
if err != nil {
    return fmt.Errorf("invalid numeric value %q: %w", input, err)
}
```

### ❌ Magic Numbers
```go
// Bad: Unexplained constants
if t < 40 {
    fontSize = int(float64(t) * 0.5)
}

// Good: Named constants with context
const (
    SmallBorderThreshold = 40
    SmallBorderFontScale = 0.5
)
if t < SmallBorderThreshold {
    fontSize = int(float64(t) * SmallBorderFontScale)
}
```

### ❌ Deep Nesting
```go
// Bad: Nested conditions
if fileInfo.IsDir() {
    if !d.IsDir() {
        ext := filepath.Ext(path)
        if ext == ".jpg" || ext == ".jpeg" {
            // ... deep logic
        }
    }
}

// Good: Early returns
if !fileInfo.IsDir() {
    return // Single file path
}
if d.IsDir() {
    return // Skip directories
}
ext := filepath.Ext(path)
if ext != ".jpg" && ext != ".jpeg" {
    return // Skip non-JPEG
}
// ... main logic at readable depth
```

### ❌ God Functions
```go
// Bad: Function does everything
func processImage() {
    // 1. Open file
    // 2. Parse EXIF
    // 3. Calculate dimensions
    // 4. Apply border
    // 5. Render caption
    // 6. Save output
    // ... 150 lines later
}

// Good: Composed functions
func processImage() {
    img := loadImage()
    caption := extractCaption()
    bordered := applyBorder(img)
    withCaption := addCaption(bordered, caption)
    saveImage(withCaption)
}
```
