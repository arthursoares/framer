package main

import (
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"image/png"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/disintegration/imaging"
	"github.com/golang/freetype"
	"github.com/golang/freetype/truetype"
	"github.com/rwcarlsen/goexif/exif"
	"golang.org/x/image/math/fixed"
	"gopkg.in/yaml.v3"
)

// Available fonts embedded in the binary
var availableFonts = []string{
	"CourierPrime-Bold",
	"BigBlueTermPlusNerdFont-Regular",
	"HeavyDataNerdFont-Regular",
}

// ProcessingConfig holds all configuration options for image processing
type ProcessingConfig struct {
	Caption          string
	CaptionTemplate  string
	NoCaption        bool
	BorderThickness  string
	Padding          string
	BorderStyle      string
	BorderColor      string
	FontName         string
	FontSize         string
	FontColor        string
	InstagramMaxSize int
	JPEGQuality      int
	OutputFormat     string
}

// ExifData holds extracted EXIF metadata
type ExifData struct {
	DateTime     time.Time
	Camera       string
	Lens         string
	ISO          string
	Aperture     string
	ShutterSpeed string
	FocalLength  string
}

// ConfigFile represents a YAML configuration file
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

// Constants for image processing
const (
	// Instagram frame dimensions (4:5 aspect ratio)
	InstagramFrameWidth  = 1080
	InstagramFrameHeight = 1350

	// Font size calculation thresholds and scaling factors
	SmallBorderThreshold  = 40
	MediumBorderThreshold = 80
	SmallFontScale        = 0.5
	MediumFontScale       = 0.7
	LargeFontScale        = 0.9

	// Image encoding
	DefaultJPEGQuality = 100
	MinJPEGQuality     = 60
	MaxJPEGQuality     = 100

	// Font rendering
	DefaultDPI = 72

	// Color values
	AlphaOpaque = 255
)

// Helper functions
func hexToRGB(hexColor string) (color.RGBA, error) {
	hexColor = strings.TrimPrefix(hexColor, "#")
	if len(hexColor) != 6 {
		return color.RGBA{}, fmt.Errorf("hex color must be 6 digits")
	}

	r, err := strconv.ParseUint(hexColor[0:2], 16, 8)
	if err != nil {
		return color.RGBA{}, err
	}
	g, err := strconv.ParseUint(hexColor[2:4], 16, 8)
	if err != nil {
		return color.RGBA{}, err
	}
	b, err := strconv.ParseUint(hexColor[4:6], 16, 8)
	if err != nil {
		return color.RGBA{}, err
	}

	return color.RGBA{R: uint8(r), G: uint8(g), B: uint8(b), A: AlphaOpaque}, nil
}

// Config file management functions

// loadConfigFile reads and parses a YAML config file
func loadConfigFile(path string) (*ConfigFile, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var config ConfigFile
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("parsing YAML: %w", err)
	}

	return &config, nil
}

// getConfigDir returns the user's config directory for framer
func getConfigDir() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(homeDir, ".config", "framer"), nil
}

// ensureConfigDir creates the config directory and presets subdirectory if they don't exist
func ensureConfigDir() error {
	configDir, err := getConfigDir()
	if err != nil {
		return err
	}

	presetsDir := filepath.Join(configDir, "presets")
	return os.MkdirAll(presetsDir, 0755)
}

// initializeDefaultPresets creates default preset files if they don't exist
func initializeDefaultPresets() error {
	configDir, err := getConfigDir()
	if err != nil {
		return err
	}

	presetsDir := filepath.Join(configDir, "presets")

	presets := map[string]string{
		"vintage.yaml": `# Vintage film style with date stamp
border_style: solid
border_thickness: "20"
border_color: "#000000"
padding: "150"
font_name: CourierPrime-Bold
font_size: "50"
font_color: "#000000"
# Uses default vintage date format: " - MON 'YY -"
`,
		"instagram.yaml": `# Instagram 4:5 frame with date
border_style: instagram
border_thickness: "5"
border_color: "#000000"
padding: "0"
font_size: "20"
caption_template: "{{mon}} '{{year2}}"
`,
		"minimal.yaml": `# Minimal thin border, no caption
border_style: solid
border_thickness: "10"
border_color: "#FFFFFF"
padding: "0"
no_caption: true
`,
	}

	for filename, content := range presets {
		path := filepath.Join(presetsDir, filename)
		// Only create if doesn't exist
		if _, err := os.Stat(path); os.IsNotExist(err) {
			if err := os.WriteFile(path, []byte(content), 0644); err != nil {
				return fmt.Errorf("writing preset %s: %w", filename, err)
			}
		}
	}

	return nil
}

// validateFontName checks if font exists in embedded fonts, returns default if not
func validateFontName(fontName string) string {
	if fontName == "" {
		return availableFonts[0]
	}

	for _, available := range availableFonts {
		if fontName == available {
			return fontName
		}
	}

	log.Printf("Warning: Font %q not found in embedded fonts, using default %q", fontName, availableFonts[0])
	return availableFonts[0]
}

// mergeConfig merges config file with CLI flags (CLI flags take precedence)
func mergeConfig(configFile *ConfigFile, cliConfig ProcessingConfig) ProcessingConfig {
	result := cliConfig

	// Only use config file values if CLI didn't provide them
	if result.Caption == "" && configFile.Caption != "" {
		result.Caption = configFile.Caption
	}
	if result.CaptionTemplate == "" && configFile.CaptionTemplate != "" {
		result.CaptionTemplate = configFile.CaptionTemplate
	}
	if !result.NoCaption && configFile.NoCaption {
		result.NoCaption = configFile.NoCaption
	}
	if result.BorderStyle == "solid" && configFile.BorderStyle != "" {
		// "solid" is the default, so if it's still solid, use config
		result.BorderStyle = configFile.BorderStyle
	}
	if result.BorderThickness == "" && configFile.BorderThickness != "" {
		result.BorderThickness = configFile.BorderThickness
	}
	if result.BorderColor == "#000000" && configFile.BorderColor != "" {
		// "#000000" is the default
		result.BorderColor = configFile.BorderColor
	}
	if result.Padding == "" && configFile.Padding != "" {
		result.Padding = configFile.Padding
	}
	if result.FontName == "" && configFile.FontName != "" {
		result.FontName = validateFontName(configFile.FontName)
	}
	if result.FontSize == "" && configFile.FontSize != "" {
		result.FontSize = configFile.FontSize
	}
	if result.FontColor == "#000000" && configFile.FontColor != "" {
		result.FontColor = configFile.FontColor
	}
	if result.JPEGQuality == 0 && configFile.JPEGQuality != 0 {
		result.JPEGQuality = configFile.JPEGQuality
	}
	if result.OutputFormat == "jpeg" && configFile.OutputFormat != "" {
		result.OutputFormat = configFile.OutputFormat
	}

	// Validate font name
	if result.FontName != "" {
		result.FontName = validateFontName(result.FontName)
	}

	return result
}

// getExifData extracts comprehensive EXIF metadata from an image file
func getExifData(file *os.File) (*ExifData, error) {
	// Reset file pointer to the beginning
	_, err := file.Seek(0, 0)
	if err != nil {
		return nil, err
	}

	// Decode exif
	x, err := exif.Decode(file)
	if err != nil {
		return nil, err
	}

	data := &ExifData{}

	// Get DateTime
	if dt, err := x.DateTime(); err == nil {
		data.DateTime = dt
	}

	// Get Camera (Make + Model)
	make, _ := x.Get(exif.Make)
	model, _ := x.Get(exif.Model)
	if make != nil && model != nil {
		makeStr, _ := make.StringVal()
		modelStr, _ := model.StringVal()
		data.Camera = strings.TrimSpace(makeStr + " " + modelStr)
	} else if model != nil {
		data.Camera, _ = model.StringVal()
	}

	// Get Lens
	if lens, err := x.Get(exif.LensModel); err == nil {
		data.Lens, _ = lens.StringVal()
	}

	// Get ISO
	if iso, err := x.Get(exif.ISOSpeedRatings); err == nil {
		if isoVal, err := iso.Int(0); err == nil {
			data.ISO = fmt.Sprintf("ISO %d", isoVal)
		}
	}

	// Get Aperture (F-Number)
	if fnumber, err := x.Get(exif.FNumber); err == nil {
		if num, denom, err := fnumber.Rat2(0); err == nil && denom != 0 {
			fstop := float64(num) / float64(denom)
			data.Aperture = fmt.Sprintf("f/%.1f", fstop)
		}
	}

	// Get Shutter Speed
	if expTime, err := x.Get(exif.ExposureTime); err == nil {
		if num, denom, err := expTime.Rat2(0); err == nil && denom != 0 {
			if num < denom {
				data.ShutterSpeed = fmt.Sprintf("1/%d", denom/num)
			} else {
				data.ShutterSpeed = fmt.Sprintf("%.1fs", float64(num)/float64(denom))
			}
		}
	}

	// Get Focal Length
	if focal, err := x.Get(exif.FocalLength); err == nil {
		if num, denom, err := focal.Rat2(0); err == nil && denom != 0 {
			fl := float64(num) / float64(denom)
			data.FocalLength = fmt.Sprintf("%.0fmm", fl)
		}
	}

	return data, nil
}

// Legacy function for backwards compatibility
func getExifDate(file *os.File) (time.Time, error) {
	data, err := getExifData(file)
	if err != nil {
		return time.Time{}, err
	}
	return data.DateTime, nil
}

func generateCaptionFromDate(dt time.Time) string {
	if dt.IsZero() {
		return " - --- -"
	}
	month := dt.Format("Jan")
	year := dt.Format("06")
	return fmt.Sprintf(" - %s '%s -", strings.ToUpper(month), year)
}

// applyTemplate replaces {{field}} placeholders with EXIF data values
func applyTemplate(template string, data *ExifData) string {
	result := template

	// Date/time fields
	if !data.DateTime.IsZero() {
		result = strings.ReplaceAll(result, "{{year}}", data.DateTime.Format("2006"))
		result = strings.ReplaceAll(result, "{{year2}}", data.DateTime.Format("06"))
		result = strings.ReplaceAll(result, "{{month}}", data.DateTime.Format("January"))
		result = strings.ReplaceAll(result, "{{mon}}", strings.ToUpper(data.DateTime.Format("Jan")))
		result = strings.ReplaceAll(result, "{{day}}", data.DateTime.Format("02"))
		result = strings.ReplaceAll(result, "{{date}}", data.DateTime.Format("2006-01-02"))
	} else {
		result = strings.ReplaceAll(result, "{{year}}", "")
		result = strings.ReplaceAll(result, "{{year2}}", "")
		result = strings.ReplaceAll(result, "{{month}}", "")
		result = strings.ReplaceAll(result, "{{mon}}", "")
		result = strings.ReplaceAll(result, "{{day}}", "")
		result = strings.ReplaceAll(result, "{{date}}", "")
	}

	// Camera/lens fields
	result = strings.ReplaceAll(result, "{{camera}}", data.Camera)
	result = strings.ReplaceAll(result, "{{lens}}", data.Lens)

	// Exposure fields
	result = strings.ReplaceAll(result, "{{iso}}", data.ISO)
	result = strings.ReplaceAll(result, "{{aperture}}", data.Aperture)
	result = strings.ReplaceAll(result, "{{shutter}}", data.ShutterSpeed)
	result = strings.ReplaceAll(result, "{{focal}}", data.FocalLength)

	// Clean up extra spaces from empty fields
	result = strings.Join(strings.Fields(result), " ")

	return strings.TrimSpace(result)
}

// determineCaption extracts or generates caption text from config and file EXIF data
func determineCaption(file *os.File, config ProcessingConfig) string {
	// If no caption requested, return empty
	if config.NoCaption {
		return ""
	}

	// If explicit caption text provided, use it
	if config.Caption != "" {
		return config.Caption
	}

	// Extract EXIF data
	exifData, err := getExifData(file)
	if err != nil {
		// Use placeholder if EXIF data not available
		if config.CaptionTemplate != "" {
			return ""  // Don't show caption if template requires EXIF but none available
		}
		return " - --- -"
	}

	// If template provided, apply it
	if config.CaptionTemplate != "" {
		return applyTemplate(config.CaptionTemplate, exifData)
	}

	// Default: use vintage date format
	return generateCaptionFromDate(exifData.DateTime)
}

// calculateBorderThickness converts border thickness string to pixels
func calculateBorderThickness(thicknessStr string, imageSize image.Point) (int, error) {
	if strings.HasSuffix(thicknessStr, "%") {
		percentage, err := strconv.ParseFloat(strings.TrimSuffix(thicknessStr, "%"), 64)
		if err != nil {
			return 0, fmt.Errorf("invalid border thickness percentage %q: %w", thicknessStr, err)
		}
		minDim := imageSize.X
		if imageSize.Y < minDim {
			minDim = imageSize.Y
		}
		return int(float64(minDim) * (percentage / 100.0)), nil
	}

	thickness, err := strconv.Atoi(thicknessStr)
	if err != nil {
		return 0, fmt.Errorf("invalid border thickness %q: must be a number or percentage (e.g., '10' or '5%%')", thicknessStr)
	}
	return thickness, nil
}

// calculateFontSize determines font size based on config or border thickness
func calculateFontSize(fontSizeStr string, borderThickness int) (int, error) {
	if fontSizeStr != "" {
		size, err := strconv.Atoi(fontSizeStr)
		if err != nil {
			return 0, fmt.Errorf("invalid font size %q: must be a number", fontSizeStr)
		}
		return size, nil
	}

	// Auto-calculate based on border thickness
	if borderThickness < SmallBorderThreshold {
		return int(float64(borderThickness) * SmallFontScale), nil
	} else if borderThickness < MediumBorderThreshold {
		return int(float64(borderThickness) * MediumFontScale), nil
	}
	return int(float64(borderThickness) * LargeFontScale), nil
}

func createInstagramFrame(img image.Image, maxSize int, borderThickness int, borderColor color.RGBA, padding int) (image.Image, image.Point, image.Point) {
	// Fixed dimensions for Instagram (4:5 ratio)
	frameW, frameH := InstagramFrameWidth, InstagramFrameHeight

	// Calculate scaling factor to fit image within max_size
	origW, origH := img.Bounds().Dx(), img.Bounds().Dy()
	scaleW := float64(maxSize) / float64(origW)
	scaleH := float64(maxSize) / float64(origH)
	scale := scaleW
	if scaleH < scaleW {
		scale = scaleH
	}

	// Resize image while maintaining aspect ratio
	newW := int(float64(origW) * scale)
	newH := int(float64(origH) * scale)
	resizedImg := imaging.Resize(img, newW, newH, imaging.Lanczos)

	// Add padding if specified
	if padding > 0 {
		paddedW := newW + 2*padding
		paddedH := newH + 2*padding
		paddedImg := image.NewRGBA(image.Rect(0, 0, paddedW, paddedH))
		draw.Draw(paddedImg, paddedImg.Bounds(), &image.Uniform{color.RGBA{AlphaOpaque, AlphaOpaque, AlphaOpaque, AlphaOpaque}}, image.Point{}, draw.Src)
		draw.Draw(paddedImg, image.Rect(padding, padding, padding+newW, padding+newH), resizedImg, image.Point{}, draw.Src)

		// Convert to Image interface to avoid type issues
		resizedImg = imaging.Clone(paddedImg)
		newW = paddedW
		newH = paddedH
	}

	// Create white background
	newImage := image.NewRGBA(image.Rect(0, 0, frameW, frameH))
	draw.Draw(newImage, newImage.Bounds(), &image.Uniform{color.RGBA{AlphaOpaque, AlphaOpaque, AlphaOpaque, AlphaOpaque}}, image.Point{}, draw.Src)

	// Create a new image with border
	borderedW := resizedImg.Bounds().Dx() + 2*borderThickness
	borderedH := resizedImg.Bounds().Dy() + 2*borderThickness
	borderedImg := image.NewRGBA(image.Rect(0, 0, borderedW, borderedH))
	draw.Draw(borderedImg, borderedImg.Bounds(), &image.Uniform{borderColor}, image.Point{}, draw.Src)
	draw.Draw(borderedImg, image.Rect(borderThickness, borderThickness,
		borderThickness+resizedImg.Bounds().Dx(), borderThickness+resizedImg.Bounds().Dy()),
		resizedImg, image.Point{}, draw.Src)

	// Calculate position to center the bordered image
	x := (frameW - borderedImg.Bounds().Dx()) / 2
	y := (frameH - borderedImg.Bounds().Dy()) / 2

	// Paste bordered image onto white background
	draw.Draw(newImage, image.Rect(x, y, x+borderedImg.Bounds().Dx(), y+borderedImg.Bounds().Dy()),
		borderedImg, image.Point{}, draw.Src)

	// Return the final image, the size of the resized image (without border),
	// and the position where the actual image (not border) starts
	return newImage, image.Point{newW, newH}, image.Point{x + borderThickness + padding, y + borderThickness + padding}
}

func createSolidBorder(img image.Image, borderThickness int, borderColor color.RGBA, padding int) image.Image {
	imgW, imgH := img.Bounds().Dx(), img.Bounds().Dy()

	// First, add the colored border around the image
	borderedW := imgW + 2*borderThickness
	borderedH := imgH + 2*borderThickness
	borderedImg := image.NewRGBA(image.Rect(0, 0, borderedW, borderedH))
	draw.Draw(borderedImg, borderedImg.Bounds(), &image.Uniform{borderColor}, image.Point{}, draw.Src)
	draw.Draw(borderedImg, image.Rect(borderThickness, borderThickness,
		borderThickness+imgW, borderThickness+imgH), img, image.Point{}, draw.Src)

	// Then, add padding if specified (white border outside the colored border)
	if padding > 0 {
		finalW := borderedW + 2*padding
		finalH := borderedH + 2*padding
		finalImg := image.NewRGBA(image.Rect(0, 0, finalW, finalH))
		draw.Draw(finalImg, finalImg.Bounds(), &image.Uniform{color.RGBA{AlphaOpaque, AlphaOpaque, AlphaOpaque, AlphaOpaque}}, image.Point{}, draw.Src)
		draw.Draw(finalImg, image.Rect(padding, padding, padding+borderedW, padding+borderedH),
			borderedImg, image.Point{}, draw.Src)
		return finalImg
	}

	return borderedImg
}

// loadFont loads and parses a font by name from embedded data
func loadFont(fontName string) (*truetype.Font, error) {
    if fontName == "" {
        fontName = availableFonts[0] // Default to first font
    }

    // Try to find the font in our embedded assets
    var fontData []byte
    var foundFont bool
    var err error

    // Check if it's a TTF
    assetName := fmt.Sprintf("fonts_data/%s.ttf", fontName)
    fontData, err = Asset(assetName)
    if err == nil {
        foundFont = true
    }

    // If not found, check for TTC
    if !foundFont {
        assetName = fmt.Sprintf("fonts_data/%s.ttc", fontName)
        fontData, err = Asset(assetName)
        if err == nil {
            foundFont = true
        }
    }

    // If not found, try the default font
    if !foundFont && fontName != availableFonts[0] {
        assetName = fmt.Sprintf("fonts_data/%s.ttf", availableFonts[0])
        fontData, err = Asset(assetName)
        if err != nil {
            return nil, fmt.Errorf("error loading font '%s' and default fallback: %v", fontName, err)
        }
    } else if !foundFont {
        return nil, fmt.Errorf("error loading font '%s': %v", fontName, err)
    }

    // Parse the font data
    f, err := truetype.Parse(fontData)
    if err != nil {
        return nil, fmt.Errorf("error parsing font '%s': %v", fontName, err)
    }

    return f, nil
}

// Returns a list of available fonts
func getAvailableFonts() []string {
    return availableFonts
}

func addCaption(newImage *image.RGBA, captionText string, fontSize int, fontColor color.RGBA, imageSize image.Point, borderThickness int, padding int, imagePos *image.Point, fontName string) *image.RGBA {
	// Load the requested font
	font, err := loadFont(fontName)
	if err != nil {
		// If we can't load the font, fall back to a simpler approach
		log.Printf("Warning: Could not load font '%s': %v. Using fallback font.", fontName, err)
		return fallbackAddCaption(newImage, captionText, fontSize, fontColor, imageSize, borderThickness, padding, imagePos)
	}

	// Calculate position
	imgW, imgH := imageSize.X, imageSize.Y

	// Create FreeType context
	c := freetype.NewContext()
	c.SetDPI(DefaultDPI)
	c.SetFont(font)
	c.SetFontSize(float64(fontSize))
	c.SetClip(newImage.Bounds())
	c.SetDst(newImage)
	c.SetSrc(&image.Uniform{fontColor})

	// Measure text size
	opts := truetype.Options{
		Size: float64(fontSize),
		DPI:  DefaultDPI,
	}
	face := truetype.NewFace(font, &opts)

	// Measure text width by summing the advance of each character
	var totalWidth fixed.Int26_6
	for _, r := range captionText {
		awidth, _ := face.GlyphAdvance(r)
		totalWidth += awidth
	}

	// Convert to pixels
	approxTextWidth := totalWidth.Ceil()

	// Approximate text height
	fontHeight := face.Metrics().Height.Ceil()

	// Calculate position
	var x, y int
	if imagePos != nil { // Instagram style
		x = imagePos.X + (imgW-approxTextWidth)/2
		y = imagePos.Y + imgH + borderThickness + fontHeight // Center in border area
	} else { // Other styles
		totalBorder := borderThickness + padding
		x = totalBorder + (imgW-approxTextWidth)/2
		y = totalBorder + imgH + (borderThickness+padding-fontHeight)/2 + fontHeight
	}

	// Draw text
	pt := freetype.Pt(x, y)
	_, err = c.DrawString(captionText, pt)
	if err != nil {
		log.Printf("Warning: Error drawing text: %v", err)
		return fallbackAddCaption(newImage, captionText, fontSize, fontColor, imageSize, borderThickness, padding, imagePos)
	}

	return newImage
}

// fallbackAddCaption is a simplified version that works without freetype
func fallbackAddCaption(newImage *image.RGBA, captionText string, fontSize int, fontColor color.RGBA, imageSize image.Point, borderThickness int, padding int, imagePos *image.Point) *image.RGBA {
	// Basic settings - more enhanced fallback method
	charWidth := fontSize / 2
	textW := len(captionText) * charWidth
	textH := fontSize
	imgW, imgH := imageSize.X, imageSize.Y

	// Calculate position
	var x, y int
	if imagePos != nil { // Instagram style
		x = imagePos.X + (imgW-textW)/2
		y = imagePos.Y + imgH + borderThickness + textH // Center in border area
	} else { // Other styles
		totalBorder := borderThickness + padding
		x = totalBorder + (imgW-textW)/2
		y = totalBorder + imgH + (borderThickness+padding-textH)/2 + textH
	}

	// Create a larger font representation by drawing filled rectangles for each character
	for i, char := range captionText {
		// Skip spaces with a narrower width
		if char == ' ' {
			continue
		}

		// Position for this character
		charX := x + i*charWidth

		// Character dimensions
		charHeight := fontSize
		charW := int(float64(charWidth) * 0.8) // slightly narrower than spacing

		// Draw a filled rectangle for each character
		// Drawing different shapes based on the character to make it more readable
		switch {
		case char == '-':
			// Draw a horizontal line
			for dx := 0; dx < charW; dx++ {
				for dy := -2; dy < 3; dy++ {
					py := y + dy + charHeight/2 - fontSize/2
					newImage.Set(charX+dx, py, fontColor)
				}
			}
		case char == '\'':
			// Draw an apostrophe (small vertical line at the top)
			for dx := charW/3; dx < 2*charW/3; dx++ {
				for dy := 0; dy < charHeight/3; dy++ {
					py := y - charHeight/2 + dy
					newImage.Set(charX+dx, py, fontColor)
				}
			}
		default:
			// For normal characters - draw a vertical rectangle
			for dx := 0; dx < charW; dx++ {
				for dy := 0; dy < charHeight; dy++ {
					py := y - charHeight/2 + dy
					newImage.Set(charX+dx, py, fontColor)
				}
			}
		}
	}

	return newImage
}

func processImage(imagePath string, outputPath string, config ProcessingConfig) {
	// Open the image file
	file, err := os.Open(imagePath)
	if err != nil {
		log.Printf("Error opening file %s: %v", imagePath, err)
		return
	}
	defer file.Close()

	// Decode image
	img, err := jpeg.Decode(file)
	if err != nil {
		log.Printf("Error decoding JPEG %s: %v", imagePath, err)
		return
	}

	// Determine caption text
	captionText := determineCaption(file, config)

	// Calculate border thickness in pixels
	borderThickness, err := calculateBorderThickness(config.BorderThickness, img.Bounds().Size())
	if err != nil {
		log.Printf("Error: %v", err)
		return
	}

	// Parse padding value
	padding, err := strconv.Atoi(config.Padding)
	if err != nil {
		log.Printf("Error: invalid padding value %q: must be a number", config.Padding)
		return
	}

	// Parse border color
	borderColor, err := hexToRGB(config.BorderColor)
	if err != nil {
		log.Printf("Error: invalid border color %q: %v (use format #RRGGBB, e.g., #000000)", config.BorderColor, err)
		return
	}

	// Apply border based on style
	var newImage image.Image
	var resizedSize image.Point
	var imagePos *image.Point

	switch strings.ToLower(config.BorderStyle) {
	case "instagram":
		var imgPos image.Point
		newImage, resizedSize, imgPos = createInstagramFrame(img, config.InstagramMaxSize, borderThickness, borderColor, padding)
		imagePos = &imgPos
	case "solid":
		newImage = createSolidBorder(img, borderThickness, borderColor, padding)
		resizedSize = image.Point{img.Bounds().Dx(), img.Bounds().Dy()}
	default:
		log.Printf("Unknown border style %s. Using solid border.", config.BorderStyle)
		newImage = createSolidBorder(img, borderThickness, borderColor, padding)
		resizedSize = image.Point{img.Bounds().Dx(), img.Bounds().Dy()}
	}

	// Add caption if specified
	if captionText != "" {
		// Convert to RGBA for drawing
		rgba := image.NewRGBA(newImage.Bounds())
		draw.Draw(rgba, rgba.Bounds(), newImage, image.Point{}, draw.Src)

		// Calculate font size
		fontSize, err := calculateFontSize(config.FontSize, borderThickness)
		if err != nil {
			log.Printf("Error: %v", err)
			return
		}

		// Parse font color
		fontColor, err := hexToRGB(config.FontColor)
		if err != nil {
			log.Printf("Error: invalid font color %q: %v (use format #RRGGBB, e.g., #000000)", config.FontColor, err)
			return
		}

		// Add caption with appropriate positioning
		newImage = addCaption(rgba, captionText, fontSize, fontColor, resizedSize, borderThickness, padding, imagePos, config.FontName)
	}

	// Save the result
	baseName := filepath.Base(imagePath)
	ext := filepath.Ext(baseName)
	name := strings.TrimSuffix(baseName, ext)
	suffix := "_instagram"
	if strings.ToLower(config.BorderStyle) != "instagram" {
		suffix = "_solid"
	}

	// Determine output format and extension
	outputFormat := strings.ToLower(config.OutputFormat)
	if outputFormat == "" {
		outputFormat = "jpeg"
	}
	outputExt := ".jpg"
	if outputFormat == "png" {
		outputExt = ".png"
	}
	outFile := filepath.Join(outputPath, fmt.Sprintf("%s%s%s", name, suffix, outputExt))

	// Create output file
	out, err := os.Create(outFile)
	if err != nil {
		log.Printf("Error creating output file %s: %v", outFile, err)
		return
	}
	defer out.Close()

	// Encode in the appropriate format
	switch outputFormat {
	case "png":
		err = png.Encode(out, newImage)
		if err != nil {
			log.Printf("Error encoding PNG %s: %v", outFile, err)
			return
		}
	case "jpeg", "jpg":
		quality := config.JPEGQuality
		if quality == 0 {
			quality = DefaultJPEGQuality
		}
		err = jpeg.Encode(out, newImage, &jpeg.Options{Quality: quality})
		if err != nil {
			log.Printf("Error encoding JPEG %s: %v", outFile, err)
			return
		}
	default:
		log.Printf("Unknown output format %q. Using JPEG.", config.OutputFormat)
		quality := config.JPEGQuality
		if quality == 0 {
			quality = DefaultJPEGQuality
		}
		err = jpeg.Encode(out, newImage, &jpeg.Options{Quality: quality})
		if err != nil {
			log.Printf("Error encoding JPEG %s: %v", outFile, err)
			return
		}
	}

	fmt.Printf("Processed '%s' -> '%s'\n", imagePath, outFile)
}

func main() {
	// Parse command line arguments
	inputPath := flag.String("input", "", "Path to a JPEG file or a folder containing JPEG files")
	flag.StringVar(inputPath, "i", "", "Path to a JPEG file or a folder containing JPEG files (shorthand)")

	outputPath := flag.String("output", "", "Output folder where processed images will be saved")
	flag.StringVar(outputPath, "o", "", "Output folder where processed images will be saved (shorthand)")

	borderThickness := flag.String("border-thickness", "", "Border thickness in pixels or as a percentage (e.g. '10%')")
	flag.StringVar(borderThickness, "t", "", "Border thickness in pixels or as a percentage (shorthand)")

	borderStyle := flag.String("border-style", "solid", "Border style: 'solid' or 'instagram' (4:5 ratio, 1080x1350px)")
	flag.StringVar(borderStyle, "s", "solid", "Border style (shorthand)")

	borderColor := flag.String("border-color", "#000000", "Border color in hex (default: '#000000')")
	caption := flag.String("caption", "", "Override the caption text (if empty, EXIF date is used)")
	captionTemplate := flag.String("caption-template", "", "Caption template with {{field}} placeholders (e.g., '{{camera}} • {{iso}} {{aperture}} {{shutter}}')")
	noCaption := flag.Bool("no-caption", false, "Disable caption entirely")
	fontName := flag.String("font-name", "", "Name of the font to use for captions")
	fontSize := flag.String("font-size", "", "Font size in pixels")
	fontColor := flag.String("font-color", "#000000", "Font color in hex (default: '#000000')")
	instagramMaxSize := flag.Int("instagram-max-size", 0, "Maximum width/height for the image in Instagram style")
	padding := flag.String("padding", "", "Additional padding around the image in pixels")
	quality := flag.Int("quality", 0, fmt.Sprintf("JPEG output quality (%d-%d, default: %d)", MinJPEGQuality, MaxJPEGQuality, DefaultJPEGQuality))
	flag.IntVar(quality, "q", 0, "JPEG output quality (shorthand)")
	outputFormat := flag.String("output-format", "jpeg", "Output image format: 'jpeg' or 'png' (default: 'jpeg')")
	flag.StringVar(outputFormat, "f", "jpeg", "Output image format (shorthand)")
	configFile := flag.String("config", "", "Path to YAML config file")
	preset := flag.String("preset", "", "Named preset from ~/.config/framer/presets/ (e.g., 'vintage', 'instagram', 'minimal')")
	listFonts := flag.Bool("list-fonts", false, "List available fonts and exit")

	flag.Parse()

	// Initialize config directory and default presets
	if err := ensureConfigDir(); err != nil {
		log.Printf("Warning: Could not create config directory: %v", err)
	} else {
		if err := initializeDefaultPresets(); err != nil {
			log.Printf("Warning: Could not initialize default presets: %v", err)
		}
	}

	// Load config file based on priority order
	var loadedConfig *ConfigFile

	// Priority 1: --config flag
	if *configFile != "" {
		if cfg, err := loadConfigFile(*configFile); err == nil {
			loadedConfig = cfg
			log.Printf("Loaded config from: %s", *configFile)
		} else {
			log.Printf("Warning: Could not load config file %s: %v", *configFile, err)
		}
	}

	// Priority 2: --preset flag
	if loadedConfig == nil && *preset != "" {
		configDir, err := getConfigDir()
		if err == nil {
			presetPath := filepath.Join(configDir, "presets", *preset+".yaml")
			if cfg, err := loadConfigFile(presetPath); err == nil {
				loadedConfig = cfg
				log.Printf("Loaded preset: %s", *preset)
			} else {
				log.Printf("Warning: Could not load preset %s: %v", *preset, err)
			}
		}
	}

	// Priority 3: ./.framer.yaml in current directory
	if loadedConfig == nil {
		if cfg, err := loadConfigFile(".framer.yaml"); err == nil {
			loadedConfig = cfg
			log.Printf("Loaded config from: .framer.yaml")
		}
	}

	// Priority 4: ~/.config/framer/default.yaml
	if loadedConfig == nil {
		configDir, err := getConfigDir()
		if err == nil {
			defaultPath := filepath.Join(configDir, "default.yaml")
			if cfg, err := loadConfigFile(defaultPath); err == nil {
				loadedConfig = cfg
				log.Printf("Loaded default config from: %s", defaultPath)
			}
		}
	}

	// Check if user wants to list available fonts
	if *listFonts {
		fmt.Println("Available fonts:")
		for _, font := range getAvailableFonts() {
			fmt.Println("  -", font)
		}
		os.Exit(0)
	}

	// Validate required arguments
	if *inputPath == "" || *outputPath == "" {
		fmt.Println("Input and output paths are required")
		flag.Usage()
		os.Exit(1)
	}

	// Validate quality if provided
	if *quality != 0 && (*quality < MinJPEGQuality || *quality > MaxJPEGQuality) {
		log.Fatalf("JPEG quality must be between %d and %d", MinJPEGQuality, MaxJPEGQuality)
	}

	// Validate output format
	validFormats := map[string]bool{"jpeg": true, "jpg": true, "png": true}
	if !validFormats[strings.ToLower(*outputFormat)] {
		log.Fatalf("Invalid output format %q. Supported formats: jpeg, jpg, png", *outputFormat)
	}

	// Build initial config from CLI flags
	config := ProcessingConfig{
		Caption:          *caption,
		CaptionTemplate:  *captionTemplate,
		NoCaption:        *noCaption,
		BorderThickness:  *borderThickness,
		Padding:          *padding,
		BorderStyle:      *borderStyle,
		BorderColor:      *borderColor,
		FontName:         *fontName,
		FontSize:         *fontSize,
		FontColor:        *fontColor,
		InstagramMaxSize: *instagramMaxSize,
		JPEGQuality:      *quality,
		OutputFormat:     *outputFormat,
	}

	// Merge with loaded config file (if any) - CLI flags take precedence
	if loadedConfig != nil {
		config = mergeConfig(loadedConfig, config)
	}

	// Set style-specific defaults if not provided
	if config.BorderStyle == "instagram" {
		if config.BorderThickness == "" {
			config.BorderThickness = "5"
		}
		if config.InstagramMaxSize == 0 {
			config.InstagramMaxSize = 1000
		}
		if config.FontSize == "" {
			config.FontSize = "20"
		}
		if config.Padding == "" {
			config.Padding = "0"
		}
	} else { // solid and vintage styles
		if config.BorderThickness == "" {
			config.BorderThickness = "20"
		}
		if config.FontSize == "" {
			config.FontSize = "50"
		}
		if config.Padding == "" {
			if *borderStyle == "solid" {
				config.Padding = "150"
			} else {
				config.Padding = "0"
			}
		}
		if config.InstagramMaxSize == 0 {
			config.InstagramMaxSize = 900
		}
	}

	// Convert to absolute paths for comparison
	absInputPath, err := filepath.Abs(*inputPath)
	if err != nil {
		log.Fatalf("Error resolving input path: %v", err)
	}
	absOutputPath, err := filepath.Abs(*outputPath)
	if err != nil {
		log.Fatalf("Error resolving output path: %v", err)
	}

	// Verify output folder exists (or create it)
	if _, err := os.Stat(absOutputPath); os.IsNotExist(err) {
		err := os.MkdirAll(absOutputPath, 0755)
		if err != nil {
			log.Fatalf("Could not create output directory: %v", err)
		}
	}

	// Process either a single file or all JPEGs in a folder
	fileInfo, err := os.Stat(absInputPath)
	if err != nil {
		log.Fatalf("Error accessing input path: %v", err)
	}

	if fileInfo.IsDir() {
		// Warn if output is a subdirectory of input
		if strings.HasPrefix(absOutputPath+string(filepath.Separator), absInputPath+string(filepath.Separator)) {
			log.Printf("Warning: Output directory is a subdirectory of input directory")
			log.Printf("  Input:  %s", absInputPath)
			log.Printf("  Output: %s", absOutputPath)
			log.Printf("This may cause nested output directories. Collecting files before processing...")
		}

		// Collect all JPEG files first to avoid processing newly created files
		var filesToProcess []string
		err := filepath.WalkDir(absInputPath, func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if !d.IsDir() {
				ext := strings.ToLower(filepath.Ext(path))
				if ext == ".jpg" || ext == ".jpeg" {
					filesToProcess = append(filesToProcess, path)
				}
			}
			return nil
		})
		if err != nil {
			log.Fatalf("Error walking directory: %v", err)
		}

		// Now process the collected files
		fmt.Printf("Found %d JPEG file(s) to process\n", len(filesToProcess))
		for _, filePath := range filesToProcess {
			processImage(filePath, absOutputPath, config)
		}
	} else {
		// Single file
		processImage(absInputPath, absOutputPath, config)
	}
}