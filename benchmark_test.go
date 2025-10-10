package main

import (
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Benchmark color parsing
func BenchmarkHexToRGB(b *testing.B) {
	testCases := []string{
		"#FFFFFF",
		"#000000",
		"#FF5733",
		"#123456",
		"ABCDEF",
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for _, hex := range testCases {
			_, _ = hexToRGB(hex)
		}
	}
}

// Benchmark border thickness calculation
func BenchmarkCalculateBorderThickness(b *testing.B) {
	imageSize := image.Point{1920, 1080}

	b.Run("absolute pixels", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_, _ = calculateBorderThickness("50", imageSize)
		}
	})

	b.Run("percentage", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_, _ = calculateBorderThickness("5%", imageSize)
		}
	})
}

// Benchmark font size calculation
func BenchmarkCalculateFontSize(b *testing.B) {
	b.Run("explicit size", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_, _ = calculateFontSize("50", 100)
		}
	})

	b.Run("auto size small border", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_, _ = calculateFontSize("", 30)
		}
	})

	b.Run("auto size medium border", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_, _ = calculateFontSize("", 60)
		}
	})

	b.Run("auto size large border", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_, _ = calculateFontSize("", 100)
		}
	})
}

// Benchmark caption generation
func BenchmarkGenerateCaptionFromDate(b *testing.B) {
	testDate := time.Date(2024, time.March, 15, 14, 30, 0, 0, time.UTC)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = generateCaptionFromDate(testDate)
	}
}

// Benchmark template application
func BenchmarkApplyTemplate(b *testing.B) {
	testDate := time.Date(2024, time.March, 15, 14, 30, 0, 0, time.UTC)
	exifData := &ExifData{
		DateTime:     testDate,
		Camera:       "Canon EOS R5",
		Lens:         "RF 24-70mm f/2.8L IS USM",
		ISO:          "ISO 400",
		Aperture:     "f/2.8",
		ShutterSpeed: "1/500",
		FocalLength:  "50mm",
	}

	b.Run("simple date template", func(b *testing.B) {
		template := "{{mon}} '{{year2}}"
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			_ = applyTemplate(template, exifData)
		}
	})

	b.Run("complex exposure template", func(b *testing.B) {
		template := "{{camera}} • {{lens}} • {{iso}} {{aperture}} {{shutter}} {{focal}}"
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			_ = applyTemplate(template, exifData)
		}
	})

	b.Run("mixed date and camera template", func(b *testing.B) {
		template := "{{camera}} • {{mon}} '{{year2}} • {{iso}} {{aperture}}"
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			_ = applyTemplate(template, exifData)
		}
	})
}

// Benchmark font validation
func BenchmarkValidateFontName(b *testing.B) {
	fonts := []string{
		"CourierPrime-Bold",
		"BigBlueTermPlusNerdFont-Regular",
		"HeavyDataNerdFont-Regular",
		"InvalidFont",
		"",
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for _, font := range fonts {
			_ = validateFontName(font)
		}
	}
}

// Benchmark EXIF reading
func BenchmarkGetExifData(b *testing.B) {
	// Use the existing test image
	testImage := "testdata/sample_800x600.jpg"
	if _, err := os.Stat(testImage); os.IsNotExist(err) {
		b.Skip("Test image not found")
	}

	file, err := os.Open(testImage)
	if err != nil {
		b.Skip("Could not open test image")
	}
	defer file.Close()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		file.Seek(0, 0)
		_, _ = getExifData(file)
	}
}

// Benchmark full image processing
func BenchmarkProcessImage(b *testing.B) {
	tmpDir := b.TempDir()
	inputPath := filepath.Join(tmpDir, "input.jpg")
	outputDir := filepath.Join(tmpDir, "output")

	// Create a test image once
	img := image.NewRGBA(image.Rect(0, 0, 1920, 1080))
	for y := 0; y < 1080; y++ {
		for x := 0; x < 1920; x++ {
			img.Set(x, y, color.RGBA{100, 150, 200, 255})
		}
	}

	f, err := os.Create(inputPath)
	if err != nil {
		b.Fatalf("Failed to create test image: %v", err)
	}
	if err := jpeg.Encode(f, img, &jpeg.Options{Quality: 95}); err != nil {
		b.Fatalf("Failed to encode test image: %v", err)
	}
	f.Close()

	if err := os.MkdirAll(outputDir, 0755); err != nil {
		b.Fatalf("Failed to create output directory: %v", err)
	}

	config := ProcessingConfig{
		BorderStyle:     "solid",
		BorderColor:     "#FFFFFF",
		BorderThickness: "50",
		FontColor:       "#000000",
		FontSize:        "40",
		FontName:        "CourierPrime-Bold",
		Caption:         "Benchmark Test",
		JPEGQuality:     95,
		OutputFormat:    "jpeg",
		Padding:         "0",
	}

	b.Run("solid border with caption", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_ = processImage(inputPath, outputDir, config)
		}
	})

	b.Run("instagram frame", func(b *testing.B) {
		configInstagram := config
		configInstagram.BorderStyle = "instagram"
		configInstagram.InstagramMaxSize = 1000
		for i := 0; i < b.N; i++ {
			_ = processImage(inputPath, outputDir, configInstagram)
		}
	})

	b.Run("no caption", func(b *testing.B) {
		configNoCaption := config
		configNoCaption.NoCaption = true
		for i := 0; i < b.N; i++ {
			_ = processImage(inputPath, outputDir, configNoCaption)
		}
	})

	b.Run("PNG output", func(b *testing.B) {
		configPNG := config
		configPNG.OutputFormat = "png"
		for i := 0; i < b.N; i++ {
			_ = processImage(inputPath, outputDir, configPNG)
		}
	})
}

// Benchmark different image sizes
func BenchmarkProcessImageSizes(b *testing.B) {
	sizes := []struct {
		name   string
		width  int
		height int
	}{
		{"small_640x480", 640, 480},
		{"medium_1920x1080", 1920, 1080},
		{"large_3840x2160", 3840, 2160},
		{"portrait_1080x1920", 1080, 1920},
	}

	for _, size := range sizes {
		b.Run(size.name, func(b *testing.B) {
			tmpDir := b.TempDir()
			inputPath := filepath.Join(tmpDir, "input.jpg")
			outputDir := filepath.Join(tmpDir, "output")

			// Create test image
			img := image.NewRGBA(image.Rect(0, 0, size.width, size.height))
			for y := 0; y < size.height; y++ {
				for x := 0; x < size.width; x++ {
					img.Set(x, y, color.RGBA{100, 150, 200, 255})
				}
			}

			f, err := os.Create(inputPath)
			if err != nil {
				b.Fatalf("Failed to create test image: %v", err)
			}
			if err := jpeg.Encode(f, img, &jpeg.Options{Quality: 95}); err != nil {
				b.Fatalf("Failed to encode test image: %v", err)
			}
			f.Close()

			if err := os.MkdirAll(outputDir, 0755); err != nil {
				b.Fatalf("Failed to create output directory: %v", err)
			}

			config := ProcessingConfig{
				BorderStyle:     "solid",
				BorderColor:     "#FFFFFF",
				BorderThickness: "50",
				FontColor:       "#000000",
				FontSize:        "40",
				FontName:        "CourierPrime-Bold",
				Caption:         "Benchmark",
				JPEGQuality:     95,
				OutputFormat:    "jpeg",
				Padding:         "0",
			}

			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				_ = processImage(inputPath, outputDir, config)
			}
		})
	}
}

// Benchmark batch processing
func BenchmarkBatchProcessing(b *testing.B) {
	fileCounts := []int{5, 10, 20}

	for _, count := range fileCounts {
		b.Run(b.Name()+string(rune('0'+count))+"_files", func(b *testing.B) {
			tmpDir := b.TempDir()
			inputDir := filepath.Join(tmpDir, "input")
			outputDir := filepath.Join(tmpDir, "output")

			if err := os.MkdirAll(inputDir, 0755); err != nil {
				b.Fatalf("Failed to create input directory: %v", err)
			}
			if err := os.MkdirAll(outputDir, 0755); err != nil {
				b.Fatalf("Failed to create output directory: %v", err)
			}

			// Create test images
			// Create test images
			var imagePaths []string
			for i := 0; i < count; i++ {
				img := image.NewRGBA(image.Rect(0, 0, 1024, 768))
				for y := 0; y < 768; y++ {
					for x := 0; x < 1024; x++ {
						img.Set(x, y, color.RGBA{100, 100, 100, 255})
					}
				}

				imagePath := filepath.Join(inputDir, fmt.Sprintf("image%d.jpg", i))
				f, err := os.Create(imagePath)
				if err != nil {
					b.Fatalf("Failed to create test image: %v", err)
				}
				if err := jpeg.Encode(f, img, &jpeg.Options{Quality: 95}); err != nil {
					b.Fatalf("Failed to encode test image: %v", err)
				}
				f.Close()
				imagePaths = append(imagePaths, imagePath)
			}

			config := ProcessingConfig{
				BorderStyle:     "solid",
				BorderColor:     "#FFFFFF",
				BorderThickness: "50",
				Caption:         "Benchmark",
				FontColor:       "#000000",
				FontSize:        "30",
				FontName:        "CourierPrime-Bold",
				JPEGQuality:     95,
				OutputFormat:    "jpeg",
				Padding:         "0",
			}

			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				for _, imagePath := range imagePaths {
					_ = processImage(imagePath, outputDir, config)
				}
			}
		})
	}
}

// Benchmark ProcessingStats operations
func BenchmarkProcessingStats(b *testing.B) {
	b.Run("RecordSuccess", func(b *testing.B) {
		stats := &ProcessingStats{Total: 1000}
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			stats.RecordSuccess()
		}
	})

	b.Run("RecordFailure", func(b *testing.B) {
		stats := &ProcessingStats{Total: 1000}
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			stats.RecordFailure()
		}
	})

	b.Run("Duration", func(b *testing.B) {
		stats := &ProcessingStats{
			StartTime: time.Now().Add(-10 * time.Second),
			EndTime:   time.Now(),
		}
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			_ = stats.Duration()
		}
	})

	b.Run("Rate", func(b *testing.B) {
		stats := &ProcessingStats{
			Total:     100,
			StartTime: time.Now().Add(-10 * time.Second),
			EndTime:   time.Now(),
		}
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			_ = stats.Rate()
		}
	})
}

// Benchmark config loading and merging
func BenchmarkConfigOperations(b *testing.B) {
	b.Run("loadConfigFile", func(b *testing.B) {
		tmpDir := b.TempDir()
		configPath := filepath.Join(tmpDir, "test.yaml")

		content := `border_style: instagram
border_thickness: "15"
border_color: "#123456"
padding: "100"
font_name: CourierPrime-Bold
font_size: "50"
font_color: "#FFFFFF"
caption: "Test Caption"
jpeg_quality: 95
output_format: png
`
		if err := os.WriteFile(configPath, []byte(content), 0644); err != nil {
			b.Fatalf("Failed to create test config: %v", err)
		}

		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			_, _ = loadConfigFile(configPath)
		}
	})

	b.Run("mergeConfig", func(b *testing.B) {
		configFile := &ConfigFile{
			BorderStyle:     "instagram",
			BorderColor:     "#FF0000",
			BorderThickness: "10",
			Padding:         "50",
			FontName:        "CourierPrime-Bold",
			FontSize:        "40",
		}
		cliConfig := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#000000",
			BorderThickness: "20",
			Padding:         "100",
		}

		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			_ = mergeConfig(configFile, cliConfig)
		}
	})
}
