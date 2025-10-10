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

### YAML Config File Pattern (Current)
**Location**: ConfigFile struct in framer.go:62-76

**Standard Structure**:
```go
type ConfigFile struct {
    Caption         string `yaml:"caption,omitempty"`
    CaptionTemplate string `yaml:"caption_template,omitempty"`
    NoCaption       bool   `yaml:"no_caption,omitempty"`
    BorderStyle     string `yaml:"border_style,omitempty"`
    BorderThickness string `yaml:"border_thickness,omitempty"`
    BorderColor     string `yaml:"border_color,omitempty"`
    Padding         string `yaml:"padding,omitempty"`
    FontName        string `yaml:"font_name,omitempty"`
    FontSize        string `yaml:"font_size,omitempty"`
    FontColor       string `yaml:"font_color,omitempty"`
    JPEGQuality     int    `yaml:"jpeg_quality,omitempty"`
    OutputFormat    string `yaml:"output_format,omitempty"`
}
```

**Usage**:
- Use `yaml:"field_name,omitempty"` tags for optional fields
- Snake_case in YAML matches CLI flag style with underscores
- Empty/zero values omitted from output (allows partial configs)

### Config Loading Pattern (Current)
**Location**: main() in framer.go:932-977

**Priority-based loading**:
```go
var loadedConfig *ConfigFile

// Priority 1: --config flag
if *configFile != "" {
    if cfg, err := loadConfigFile(*configFile); err == nil {
        loadedConfig = cfg
        log.Printf("Loaded config from: %s", *configFile)
    }
}

// Priority 2: --preset flag
if loadedConfig == nil && *preset != "" {
    configDir, _ := getConfigDir()
    presetPath := filepath.Join(configDir, "presets", *preset+".yaml")
    if cfg, err := loadConfigFile(presetPath); err == nil {
        loadedConfig = cfg
    }
}

// Priority 3: ./.framer.yaml
if loadedConfig == nil {
    if cfg, err := loadConfigFile(".framer.yaml"); err == nil {
        loadedConfig = cfg
    }
}

// Priority 4: ~/.config/framer/default.yaml
if loadedConfig == nil {
    configDir, _ := getConfigDir()
    defaultPath := filepath.Join(configDir, "default.yaml")
    if cfg, err := loadConfigFile(defaultPath); err == nil {
        loadedConfig = cfg
    }
}
```

**Key Pattern**: Use `if err == nil` (success case first) for cleaner chaining

### Config Merging Pattern (Current)
**Location**: mergeConfig() in framer.go:229-279

**Standard Merge Logic**:
```go
func mergeConfig(configFile *ConfigFile, cliConfig ProcessingConfig) ProcessingConfig {
    result := cliConfig

    // Only use config file value if CLI didn't provide it
    if result.Caption == "" && configFile.Caption != "" {
        result.Caption = configFile.Caption
    }
    // ... repeat for all fields

    return result
}
```

**Key Principles**:
- Start with CLI config as base
- Only apply config file values if CLI value is empty/default
- For strings: check `""`
- For ints: check `0`
- For bools: special logic (prefer CLI true over config false)
- Return new struct (immutability)

### Config Directory Management Pattern (Current)
**Location**: framer.go:143-211

**Standard Approach**:
```go
// Get config directory
func getConfigDir() (string, error) {
    homeDir, err := os.UserHomeDir()
    if err != nil {
        return "", err
    }
    return filepath.Join(homeDir, ".config", "framer"), nil
}

// Ensure directory exists
func ensureConfigDir() error {
    configDir, err := getConfigDir()
    if err != nil {
        return err
    }
    presetsDir := filepath.Join(configDir, "presets")
    return os.MkdirAll(presetsDir, 0755)
}

// Initialize default files
func initializeDefaultPresets() error {
    // Only create if doesn't exist
    if _, err := os.Stat(path); os.IsNotExist(err) {
        if err := os.WriteFile(path, []byte(content), 0644); err != nil {
            return fmt.Errorf("writing preset %s: %w", filename, err)
        }
    }
    return nil
}
```

**Key Pattern**: Check `os.IsNotExist(err)` before creating to preserve user modifications

### Validation with Fallback Pattern (Current)
**Location**: validateFontName() in framer.go:213-227

**Standard Approach**:
```go
func validateFontName(fontName string) string {
    if fontName == "" {
        return availableFonts[0]
    }

    for _, available := range availableFonts {
        if fontName == available {
            return fontName
        }
    }

    log.Printf("Warning: Font %q not found, using default %q", fontName, availableFonts[0])
    return availableFonts[0]
}
```

**Key Principles**:
- Always return a valid value (never return invalid input)
- Log warning for user feedback
- Prefer graceful degradation over errors
- Use for non-critical validation (fonts, colors with fallbacks)

## Concurrency Patterns (Current)

### Worker Pool for Batch Processing (Implemented)
**Location**: processBatchConcurrent() and worker() in framer.go:945-1033

**Pattern Structure**:
```go
func processBatchConcurrent(files []string, outputPath string, config ProcessingConfig, numWorkers int) *ProcessingStats {
    // 1. Create buffered channels
    jobs := make(chan string, len(files))
    results := make(chan ProcessingResult, len(files))

    // 2. Create progress bar (thread-safe)
    bar := progressbar.NewOptions(len(files), /* options */)

    // 3. Initialize statistics
    stats := &ProcessingStats{
        Total:     len(files),
        StartTime: time.Now(),
    }

    // 4. Start worker goroutines
    var wg sync.WaitGroup
    for i := 0; i < numWorkers; i++ {
        wg.Add(1)
        go worker(i, jobs, results, outputPath, config, &wg, bar)
    }

    // 5. Send all jobs to workers
    for _, file := range files {
        jobs <- file
    }
    close(jobs)

    // 6. Collect results in background
    go func() {
        for range files {
            result := <-results
            if result.Success {
                stats.RecordSuccess()
            } else {
                stats.RecordFailure()
            }
        }
        close(results)
    }()

    // 7. Wait for all workers to complete
    wg.Wait()
    stats.EndTime = time.Now()

    return stats
}

func worker(id int, jobs <-chan string, results chan<- ProcessingResult, outputPath string, config ProcessingConfig, wg *sync.WaitGroup, bar *progressbar.ProgressBar) {
    defer wg.Done()

    for filePath := range jobs {
        start := time.Now()
        err := processImage(filePath, outputPath, config)

        result := ProcessingResult{
            FilePath:  filePath,
            Success:   err == nil,
            Error:     err,
            StartTime: start,
            Duration:  time.Since(start),
        }

        results <- result
        bar.Add(1)  // Thread-safe progress update

        if err != nil {
            log.Printf("Error processing %s: %v", filepath.Base(filePath), err)
        }
    }
}
```

**Key Principles**:
- **Buffered channels**: Size = number of jobs prevents blocking
- **WaitGroup**: Ensures all workers complete before returning
- **Progress bar thread safety**: `bar.Add(1)` called from multiple goroutines safely
- **Background result collection**: Doesn't block workers
- **Error logging**: Immediate feedback in workers, summary at end
- **Graceful cleanup**: Close channels after sending all jobs

### Error Handling in Concurrent Context
**Pattern**: Return errors, log immediately, collect statistics

```go
// Worker logs errors immediately for visibility
if err != nil {
    log.Printf("Error processing %s: %v", filepath.Base(filePath), err)
}

// But also records in result for statistics
result := ProcessingResult{
    Success: err == nil,
    Error:   err,
}
results <- result
```

**Why both?**:
- Immediate logging: User sees errors as they happen
- Result collection: Enables statistics summary
- No lost errors: Even if collection fails, error is logged

### Progress Bar Integration Pattern
**Location**: processBatchConcurrent() in framer.go:977-989

**Standard Configuration**:
```go
bar := progressbar.NewOptions(totalItems,
    progressbar.OptionSetDescription("Processing images"),
    progressbar.OptionShowCount(),        // Shows "X/Y"
    progressbar.OptionShowIts(),          // Shows "N it/s"
    progressbar.OptionSetWidth(40),       // Bar width
    progressbar.OptionSetTheme(progressbar.Theme{
        Saucer:        "=",
        SaucerPadding: "-",
        BarStart:      "[",
        BarEnd:        "]",
    }),
)
```

**Update Pattern**:
```go
// Thread-safe - can be called from multiple goroutines
bar.Add(1)
```

**Key Features**:
- Auto-updates ETA and rate
- Thread-safe for concurrent updates
- Clears properly on completion
- Shows real-time progress

### Statistics Collection Pattern
**Location**: ProcessingStats type and methods in framer.go:88-162

**Pattern**:
```go
// Define statistics struct
type ProcessingStats struct {
    Total     int
    Succeeded int
    Failed    int
    StartTime time.Time
    EndTime   time.Time
}

// Implement accumulation methods
func (s *ProcessingStats) RecordSuccess() {
    s.Succeeded++
}

func (s *ProcessingStats) RecordFailure() {
    s.Failed++
}

// Implement computed properties
func (s *ProcessingStats) Duration() time.Duration {
    return s.EndTime.Sub(s.StartTime)
}

func (s *ProcessingStats) Rate() float64 {
    return float64(s.Total) / s.Duration().Seconds()
}

// Implement formatted output
func (s *ProcessingStats) PrintSummary() {
    fmt.Printf("Total:     %d\n", s.Total)
    fmt.Printf("Succeeded: %d\n", s.Succeeded)
    fmt.Printf("Failed:    %d\n", s.Failed)
    fmt.Printf("Rate:      %.2f files/sec\n", s.Rate())
}
```

**Usage Pattern**:
```go
stats := &ProcessingStats{Total: len(files), StartTime: time.Now()}
// ... process files ...
stats.EndTime = time.Now()
stats.PrintSummary()
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
