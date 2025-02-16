package main

import (
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"io/fs"
	"log"
	"math/rand"
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
)

// Available fonts embedded in the binary
var availableFonts = []string{
	"CourierPrime-Bold",
	"AmericanTypewriter",
	"BigBlueTermPlusNerdFont-Regular",
	"HeavyDataNerdFont-Regular",
}

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

	return color.RGBA{R: uint8(r), G: uint8(g), B: uint8(b), A: 255}, nil
}

func getExifDate(file *os.File) (time.Time, error) {
	// Reset file pointer to the beginning
	_, err := file.Seek(0, 0)
	if err != nil {
		return time.Time{}, err
	}

	// Decode exif
	x, err := exif.Decode(file)
	if err != nil {
		return time.Time{}, err
	}

	// Get DateTimeOriginal
	dt, err := x.DateTime()
	if err != nil {
		return time.Time{}, err
	}

	return dt, nil
}

func generateCaptionFromDate(dt time.Time) string {
	if dt.IsZero() {
		return " - --- -"
	}
	month := dt.Format("Jan")
	year := dt.Format("06")
	return fmt.Sprintf(" - %s '%s -", strings.ToUpper(month), year)
}

// padWithBorder adds a border to an image
func padWithBorder(img image.Image, width, height int, borderColor color.RGBA) *image.RGBA {
	newImg := image.NewRGBA(image.Rect(0, 0, width, height))
	
	// Fill the entire image with the border color
	draw.Draw(newImg, newImg.Bounds(), &image.Uniform{borderColor}, image.Point{}, draw.Src)
	
	// Calculate position to center the original image
	x := (width - img.Bounds().Dx()) / 2
	y := (height - img.Bounds().Dy()) / 2
	
	// Draw the original image centered on the new image
	draw.Draw(newImg, image.Rect(x, y, x+img.Bounds().Dx(), y+img.Bounds().Dy()), 
		img, img.Bounds().Min, draw.Src)
	
	return newImg
}

func createInstagramFrame(img image.Image, maxSize int, borderThickness int, borderColor color.RGBA, padding int) (image.Image, image.Point, image.Point) {
	// Fixed dimensions for Instagram (4:5 ratio)
	frameW, frameH := 1080, 1350

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
		draw.Draw(paddedImg, paddedImg.Bounds(), &image.Uniform{color.RGBA{255, 255, 255, 255}}, image.Point{}, draw.Src)
		draw.Draw(paddedImg, image.Rect(padding, padding, padding+newW, padding+newH), resizedImg, image.Point{}, draw.Src)
		
		// Convert to Image interface to avoid type issues
		resizedImg = imaging.Clone(paddedImg)
		newW = paddedW
		newH = paddedH
	}

	// Create white background
	newImage := image.NewRGBA(image.Rect(0, 0, frameW, frameH))
	draw.Draw(newImage, newImage.Bounds(), &image.Uniform{color.RGBA{255, 255, 255, 255}}, image.Point{}, draw.Src)

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
		draw.Draw(finalImg, finalImg.Bounds(), &image.Uniform{color.RGBA{255, 255, 255, 255}}, image.Point{}, draw.Src)
		draw.Draw(finalImg, image.Rect(padding, padding, padding+borderedW, padding+borderedH), 
			borderedImg, image.Point{}, draw.Src)
		return finalImg
	}
	
	return borderedImg
}

// blur function removed as it's no longer needed

// Vintage border style has been removed

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
	c.SetDPI(72)
	c.SetFont(font)
	c.SetFontSize(float64(fontSize))
	c.SetClip(newImage.Bounds())
	c.SetDst(newImage)
	c.SetSrc(&image.Uniform{fontColor})
	
	// Measure text size
	opts := truetype.Options{
		Size: float64(fontSize),
		DPI:  72,
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

func processImage(imagePath string, outputPath string, args struct {
	caption          string
	borderThickness  string
	padding          string
	borderStyle      string
	borderColor      string
	fontName         string
	fontSize         string
	fontColor        string
	instagramMaxSize int
}) {
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
	var captionText string
	if args.caption != "" {
		captionText = args.caption
	} else {
		dt, err := getExifDate(file)
		if err != nil {
			// Use placeholder if EXIF data not available
			captionText = " - --- -"
		} else {
			captionText = generateCaptionFromDate(dt)
		}
	}

	// Compute actual border thickness in pixels
	var t int
	origSize := img.Bounds().Size()
	if strings.HasSuffix(args.borderThickness, "%") {
		percentage, _ := strconv.ParseFloat(strings.TrimSuffix(args.borderThickness, "%"), 64)
		minDim := origSize.X
		if origSize.Y < minDim {
			minDim = origSize.Y
		}
		t = int(float64(minDim) * (percentage / 100.0))
	} else {
		t, _ = strconv.Atoi(args.borderThickness)
	}

	// Get padding value
	p, _ := strconv.Atoi(args.padding)

	// Create the image based on style
	borderColor, _ := hexToRGB(args.borderColor)
	var newImage image.Image
	var resizedSize image.Point
	var imagePos *image.Point

	switch strings.ToLower(args.borderStyle) {
	case "instagram":
		var imgPos image.Point
		newImage, resizedSize, imgPos = createInstagramFrame(img, args.instagramMaxSize, t, borderColor, p)
		imagePos = &imgPos
	case "solid":
		newImage = createSolidBorder(img, t, borderColor, p)
		resizedSize = image.Point{img.Bounds().Dx(), img.Bounds().Dy()}
	default:
		log.Printf("Unknown border style %s. Using solid border.", args.borderStyle)
		newImage = createSolidBorder(img, t, borderColor, p)
		resizedSize = image.Point{img.Bounds().Dx(), img.Bounds().Dy()}
	}

	// Add caption for all styles
	if captionText != "" {
		// Convert to RGBA for drawing
		rgba := image.NewRGBA(newImage.Bounds())
		draw.Draw(rgba, rgba.Bounds(), newImage, image.Point{}, draw.Src)

		// Use provided font size or compute based on border thickness
		computedFontSize := 0
		if args.fontSize != "" {
			computedFontSize, _ = strconv.Atoi(args.fontSize)
		} else {
			if t < 40 {
				computedFontSize = int(float64(t) * 0.5)
			} else if t < 80 {
				computedFontSize = int(float64(t) * 0.7)
			} else {
				computedFontSize = int(float64(t) * 0.9)
			}
		}

		fontColor, _ := hexToRGB(args.fontColor)
		// Add caption with appropriate positioning
		newImage = addCaption(rgba, captionText, computedFontSize, fontColor, resizedSize, t, p, imagePos, args.fontName)
	}

	// Save the result
	baseName := filepath.Base(imagePath)
	ext := filepath.Ext(baseName)
	name := strings.TrimSuffix(baseName, ext)
	suffix := "_instagram"
	if strings.ToLower(args.borderStyle) != "instagram" {
		suffix = "_framed"
	}
	outFile := filepath.Join(outputPath, fmt.Sprintf("%s%s.jpg", name, suffix))

	// Create output file
	out, err := os.Create(outFile)
	if err != nil {
		log.Printf("Error creating output file %s: %v", outFile, err)
		return
	}
	defer out.Close()

	// Encode as JPEG
	err = jpeg.Encode(out, newImage, &jpeg.Options{Quality: 100})
	if err != nil {
		log.Printf("Error encoding JPEG %s: %v", outFile, err)
		return
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
	fontName := flag.String("font-name", "", "Name of the font to use for captions")
	fontSize := flag.String("font-size", "", "Font size in pixels")
	fontColor := flag.String("font-color", "#000000", "Font color in hex (default: '#000000')")
	instagramMaxSize := flag.Int("instagram-max-size", 0, "Maximum width/height for the image in Instagram style")
	padding := flag.String("padding", "", "Additional padding around the image in pixels")
	listFonts := flag.Bool("list-fonts", false, "List available fonts and exit")

	flag.Parse()
	
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

	// Set style-specific defaults if not provided
	args := struct {
		caption          string
		borderThickness  string
		padding          string
		borderStyle      string
		borderColor      string
		fontName         string
		fontSize         string
		fontColor        string
		instagramMaxSize int
	}{
		caption:          *caption,
		borderThickness:  *borderThickness,
		padding:          *padding,
		borderStyle:      *borderStyle,
		borderColor:      *borderColor,
		fontName:         *fontName,
		fontSize:         *fontSize,
		fontColor:        *fontColor,
		instagramMaxSize: *instagramMaxSize,
	}

	if *borderStyle == "instagram" {
		if args.borderThickness == "" {
			args.borderThickness = "5"
		}
		if args.instagramMaxSize == 0 {
			args.instagramMaxSize = 1000
		}
		if args.fontSize == "" {
			args.fontSize = "20"
		}
		if args.padding == "" {
			args.padding = "0"
		}
	} else { // solid and vintage styles
		if args.borderThickness == "" {
			args.borderThickness = "20"
		}
		if args.fontSize == "" {
			args.fontSize = "50"
		}
		if args.padding == "" {
			if *borderStyle == "solid" {
				args.padding = "150"
			} else {
				args.padding = "0"
			}
		}
		if args.instagramMaxSize == 0 {
			args.instagramMaxSize = 900
		}
	}

	// Verify output folder exists (or create it)
	if _, err := os.Stat(*outputPath); os.IsNotExist(err) {
		err := os.MkdirAll(*outputPath, 0755)
		if err != nil {
			log.Fatalf("Could not create output directory: %v", err)
		}
	}

	// Process either a single file or all JPEGs in a folder
	fileInfo, err := os.Stat(*inputPath)
	if err != nil {
		log.Fatalf("Error accessing input path: %v", err)
	}

	if fileInfo.IsDir() {
		// Process all JPEGs in directory
		err := filepath.WalkDir(*inputPath, func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if !d.IsDir() {
				ext := strings.ToLower(filepath.Ext(path))
				if ext == ".jpg" || ext == ".jpeg" {
					processImage(path, *outputPath, args)
				}
			}
			return nil
		})
		if err != nil {
			log.Fatalf("Error walking directory: %v", err)
		}
	} else {
		// Single file
		processImage(*inputPath, *outputPath, args)
	}
}