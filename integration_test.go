package main

import (
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// createTestImage creates a simple test image with the specified dimensions and color
func createTestImage(t *testing.T, width, height int, col color.Color) image.Image {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			img.Set(x, y, col)
		}
	}
	return img
}

// saveTestImage saves an image to a file
func saveTestImage(t *testing.T, img image.Image, path string, format string) {
	t.Helper()
	f, err := os.Create(path)
	if err != nil {
		t.Fatalf("Failed to create test image file: %v", err)
	}
	defer f.Close()

	if format == "jpeg" || format == "jpg" {
		err = jpeg.Encode(f, img, &jpeg.Options{Quality: 95})
	} else {
		err = png.Encode(f, img)
	}

	if err != nil {
		t.Fatalf("Failed to encode test image: %v", err)
	}
}

func TestProcessImageEndToEnd(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	t.Run("solid border with caption", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")

		// Create test image
		img := createTestImage(t, 800, 600, color.RGBA{100, 150, 200, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		// Create output directory
		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		// Process the image
		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#FFFFFF",
			BorderThickness: "50",
			FontColor:       "#000000",
			FontSize:        "30",
			FontName:        "CourierPrime-Bold",
			Caption:         "Test Caption",
			JPEGQuality:     95,
			OutputFormat:    "jpeg",
			Padding:         "0",
		}

		err := processImage(inputPath, outputDir, config)
		if err != nil {
			t.Fatalf("processImage() error = %v", err)
		}

		// Verify output file exists
		expectedOutput := filepath.Join(outputDir, "input_solid.jpg")
		if _, err := os.Stat(expectedOutput); os.IsNotExist(err) {
			t.Errorf("Output file not created: %s", expectedOutput)
		}

		// Verify output dimensions
		outputFile, err := os.Open(expectedOutput)
		if err != nil {
			t.Fatalf("Failed to open output file: %v", err)
		}
		defer outputFile.Close()

		outputImg, _, err := image.Decode(outputFile)
		if err != nil {
			t.Fatalf("Failed to decode output image: %v", err)
		}

		bounds := outputImg.Bounds()
		expectedWidth := 800 + 2*50 // Original + 2 * border
		expectedHeight := 600 + 2*50
		if bounds.Dx() != expectedWidth || bounds.Dy() != expectedHeight {
			t.Errorf("Expected dimensions %dx%d, got %dx%d",
				expectedWidth, expectedHeight, bounds.Dx(), bounds.Dy())
		}
	})

	t.Run("instagram frame", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")

		// Create test image (landscape)
		img := createTestImage(t, 1600, 1000, color.RGBA{200, 100, 150, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		config := ProcessingConfig{
			BorderStyle:      "instagram",
			BorderColor:      "#FFFFFF",
			BorderThickness:  "50",
			FontColor:        "#000000",
			FontSize:         "40",
			FontName:         "CourierPrime-Bold",
			Caption:          "Instagram Test",
			InstagramMaxSize: 1000,
			JPEGQuality:      95,
			OutputFormat:     "jpeg",
			Padding:          "0",
		}

		err := processImage(inputPath, outputDir, config)
		if err != nil {
			t.Fatalf("processImage() error = %v", err)
		}

		expectedOutput := filepath.Join(outputDir, "input_instagram.jpg")
		if _, err := os.Stat(expectedOutput); os.IsNotExist(err) {
			t.Errorf("Output file not created: %s", expectedOutput)
		}

		// Verify instagram frame maintains 4:5 aspect ratio
		outputFile, err := os.Open(expectedOutput)
		if err != nil {
			t.Fatalf("Failed to open output file: %v", err)
		}
		defer outputFile.Close()

		outputImg, _, err := image.Decode(outputFile)
		if err != nil {
			t.Fatalf("Failed to decode output image: %v", err)
		}

		bounds := outputImg.Bounds()
		aspectRatio := float64(bounds.Dx()) / float64(bounds.Dy())
		expectedRatio := 4.0 / 5.0
		if aspectRatio < expectedRatio-0.01 || aspectRatio > expectedRatio+0.01 {
			t.Errorf("Expected aspect ratio ~%.2f (4:5), got %.2f", expectedRatio, aspectRatio)
		}
	})

	t.Run("no caption", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")

		img := createTestImage(t, 600, 400, color.RGBA{50, 50, 50, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#000000",
			BorderThickness: "30",
			NoCaption:       true,
			JPEGQuality:     90,
			OutputFormat:    "jpeg",
			Padding:         "0",
		}

		err := processImage(inputPath, outputDir, config)
		if err != nil {
			t.Fatalf("processImage() error = %v", err)
		}

		expectedOutput := filepath.Join(outputDir, "input_solid.jpg")
		if _, err := os.Stat(expectedOutput); os.IsNotExist(err) {
			t.Errorf("Output file not created: %s", expectedOutput)
		}
	})

	t.Run("PNG output format", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")

		img := createTestImage(t, 400, 300, color.RGBA{255, 0, 0, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#FFFFFF",
			BorderThickness: "20",
			Caption:         "PNG Test",
			FontColor:       "#000000",
			FontSize:        "20",
			FontName:        "CourierPrime-Bold",
			OutputFormat:    "png",
			Padding:         "0",
		}

		err := processImage(inputPath, outputDir, config)
		if err != nil {
			t.Fatalf("processImage() error = %v", err)
		}

		expectedOutput := filepath.Join(outputDir, "input_solid.png")
		if _, err := os.Stat(expectedOutput); os.IsNotExist(err) {
			t.Errorf("Output file not created: %s", expectedOutput)
		}

		// Verify it's actually a PNG
		outputFile, err := os.Open(expectedOutput)
		if err != nil {
			t.Fatalf("Failed to open output file: %v", err)
		}
		defer outputFile.Close()

		_, format, err := image.DecodeConfig(outputFile)
		if err != nil {
			t.Fatalf("Failed to decode output format: %v", err)
		}

		if format != "png" {
			t.Errorf("Expected PNG format, got %s", format)
		}
	})

	t.Run("percentage border thickness", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")

		img := createTestImage(t, 1000, 800, color.RGBA{0, 255, 0, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#000000",
			BorderThickness: "5%", // 5% of 800 (min dimension) = 40px
			Caption:         "Percentage Test",
			FontColor:       "#FFFFFF",
			FontName:        "CourierPrime-Bold",
			JPEGQuality:     95,
			OutputFormat:    "jpeg",
			Padding:         "0",
		}

		err := processImage(inputPath, outputDir, config)
		if err != nil {
			t.Fatalf("processImage() error = %v", err)
		}

		expectedOutput := filepath.Join(outputDir, "input_solid.jpg")
		outputFile, err := os.Open(expectedOutput)
		if err != nil {
			t.Fatalf("Failed to open output file: %v", err)
		}
		defer outputFile.Close()

		outputImg, _, err := image.Decode(outputFile)
		if err != nil {
			t.Fatalf("Failed to decode output image: %v", err)
		}

		bounds := outputImg.Bounds()
		expectedWidth := 1000 + 2*40 // 5% of 800 = 40
		expectedHeight := 800 + 2*40
		if bounds.Dx() != expectedWidth || bounds.Dy() != expectedHeight {
			t.Errorf("Expected dimensions %dx%d, got %dx%d",
				expectedWidth, expectedHeight, bounds.Dx(), bounds.Dy())
		}
	})

	t.Run("explicit output file path", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")
		explicitOutputPath := filepath.Join(outputDir, "custom_name.jpg")

		img := createTestImage(t, 600, 400, color.RGBA{150, 75, 200, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#FFFFFF",
			BorderThickness: "25",
			Caption:         "Explicit Path Test",
			FontColor:       "#000000",
			FontSize:        "30",
			FontName:        "CourierPrime-Bold",
			JPEGQuality:     95,
			OutputFormat:    "jpeg",
			Padding:         "0",
		}

		// Pass explicit output file path instead of directory
		err := processImage(inputPath, explicitOutputPath, config)
		if err != nil {
			t.Fatalf("processImage() error = %v", err)
		}

		// Verify output file exists at the explicit path
		if _, err := os.Stat(explicitOutputPath); os.IsNotExist(err) {
			t.Errorf("Output file not created at explicit path: %s", explicitOutputPath)
		}

		// Verify default generated file was NOT created
		defaultOutput := filepath.Join(outputDir, "input_solid.jpg")
		if _, err := os.Stat(defaultOutput); !os.IsNotExist(err) {
			t.Errorf("Default output file should not exist when using explicit path: %s", defaultOutput)
		}

		// Verify output dimensions
		outputFile, err := os.Open(explicitOutputPath)
		if err != nil {
			t.Fatalf("Failed to open output file: %v", err)
		}
		defer outputFile.Close()

		outputImg, _, err := image.Decode(outputFile)
		if err != nil {
			t.Fatalf("Failed to decode output image: %v", err)
		}

		bounds := outputImg.Bounds()
		expectedWidth := 600 + 2*25
		expectedHeight := 400 + 2*25
		if bounds.Dx() != expectedWidth || bounds.Dy() != expectedHeight {
			t.Errorf("Expected dimensions %dx%d, got %dx%d",
				expectedWidth, expectedHeight, bounds.Dx(), bounds.Dy())
		}
	})

	t.Run("explicit output file path with PNG", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")
		explicitOutputPath := filepath.Join(outputDir, "output.png")

		img := createTestImage(t, 500, 500, color.RGBA{255, 128, 0, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		config := ProcessingConfig{
			BorderStyle:     "instagram",
			BorderColor:     "#000000",
			BorderThickness: "30",
			Caption:         "PNG Output Test",
			FontColor:       "#FFFFFF",
			FontSize:        "28",
			FontName:        "CourierPrime-Bold",
			InstagramMaxSize: 900,
			// Note: OutputFormat is ignored when explicit path has .png extension
			OutputFormat:    "jpeg",
			Padding:         "0",
		}

		// Pass explicit output file path with .png extension
		err := processImage(inputPath, explicitOutputPath, config)
		if err != nil {
			t.Fatalf("processImage() error = %v", err)
		}

		// Verify output file exists
		if _, err := os.Stat(explicitOutputPath); os.IsNotExist(err) {
			t.Errorf("Output file not created: %s", explicitOutputPath)
		}

		// Verify it's actually a PNG (format derived from file extension)
		outputFile, err := os.Open(explicitOutputPath)
		if err != nil {
			t.Fatalf("Failed to open output file: %v", err)
		}
		defer outputFile.Close()

		_, format, err := image.DecodeConfig(outputFile)
		if err != nil {
			t.Fatalf("Failed to decode output format: %v", err)
		}

		if format != "png" {
			t.Errorf("Expected PNG format (derived from .png extension), got %s", format)
		}
	})
}

func TestBatchProcessing(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	t.Run("multiple images", func(t *testing.T) {
		tmpDir := t.TempDir()
		outputDir := filepath.Join(tmpDir, "output")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		// Create 3 test images with different sizes
		testCases := []struct {
			name   string
			width  int
			height int
		}{
			{"image1.jpg", 800, 600},
			{"image2.jpg", 1024, 768},
			{"image3.jpg", 640, 480},
		}

		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#FFFFFF",
			BorderThickness: "30",
			Caption:         "Batch Test",
			FontColor:       "#000000",
			FontSize:        "25",
			FontName:        "CourierPrime-Bold",
			JPEGQuality:     95,
			OutputFormat:    "jpeg",
			Padding:         "0",
		}

		// Process each image individually (simulating batch processing)
		successCount := 0
		for _, tc := range testCases {
			img := createTestImage(t, tc.width, tc.height, color.RGBA{100, 100, 100, 255})
			inputPath := filepath.Join(tmpDir, tc.name)
			saveTestImage(t, img, inputPath, "jpeg")

			err := processImage(inputPath, outputDir, config)
			if err != nil {
				t.Errorf("Failed to process %s: %v", tc.name, err)
			} else {
				successCount++
			}
		}

		if successCount != len(testCases) {
			t.Errorf("Expected %d successes, got %d", len(testCases), successCount)
		}

		// Verify all output files were created
		for _, tc := range testCases {
			baseName := strings.TrimSuffix(tc.name, ".jpg")
			expectedOutput := filepath.Join(outputDir, baseName+"_solid.jpg")
			if _, err := os.Stat(expectedOutput); os.IsNotExist(err) {
				t.Errorf("Output file not created: %s", expectedOutput)
			}
		}
	})
}

func TestPostProcessIntegration(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	t.Run("post-process hook creates marker file", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")

		img := createTestImage(t, 400, 300, color.RGBA{100, 150, 200, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#000000",
			BorderThickness: "20",
			NoCaption:       true,
			JPEGQuality:     95,
			OutputFormat:    "jpeg",
			Padding:         "0",
			PostProcess:     "touch {file}.processed",
		}

		err := processImage(inputPath, outputDir, config)
		if err != nil {
			t.Fatalf("processImage() error = %v", err)
		}

		// Verify output file exists
		expectedOutput := filepath.Join(outputDir, "input_solid.jpg")
		if _, err := os.Stat(expectedOutput); os.IsNotExist(err) {
			t.Errorf("Output file not created: %s", expectedOutput)
		}

		// Verify post-process marker file exists
		markerFile := expectedOutput + ".processed"
		if _, err := os.Stat(markerFile); os.IsNotExist(err) {
			t.Errorf("Post-process marker file not created: %s", markerFile)
		}
	})

	t.Run("post-process hook modifies file", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")
		logFile := filepath.Join(tmpDir, "post_process.log")

		img := createTestImage(t, 400, 300, color.RGBA{50, 100, 150, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		// Post-process that writes the file path to a log
		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#FFFFFF",
			BorderThickness: "10",
			NoCaption:       true,
			JPEGQuality:     90,
			OutputFormat:    "jpeg",
			Padding:         "0",
			PostProcess:     "echo {file} >> " + logFile,
		}

		err := processImage(inputPath, outputDir, config)
		if err != nil {
			t.Fatalf("processImage() error = %v", err)
		}

		// Verify log file contains the output path
		logContent, err := os.ReadFile(logFile)
		if err != nil {
			t.Fatalf("Failed to read log file: %v", err)
		}

		expectedOutput := filepath.Join(outputDir, "input_solid.jpg")
		if !strings.Contains(string(logContent), expectedOutput) {
			t.Errorf("Log file should contain %q, got %q", expectedOutput, string(logContent))
		}
	})

	t.Run("post-process failure logs warning but continues", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")

		img := createTestImage(t, 400, 300, color.RGBA{200, 50, 100, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		// Post-process command that will fail
		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#000000",
			BorderThickness: "15",
			NoCaption:       true,
			JPEGQuality:     85,
			OutputFormat:    "jpeg",
			Padding:         "0",
			PostProcess:     "exit 1", // Command that fails
		}

		// Should not return an error even though post-process fails
		err := processImage(inputPath, outputDir, config)
		if err != nil {
			t.Fatalf("processImage() should not fail when post-process fails, got error = %v", err)
		}

		// Output file should still exist
		expectedOutput := filepath.Join(outputDir, "input_solid.jpg")
		if _, err := os.Stat(expectedOutput); os.IsNotExist(err) {
			t.Errorf("Output file not created despite post-process failure: %s", expectedOutput)
		}
	})

	t.Run("batch processing with post-process", func(t *testing.T) {
		tmpDir := t.TempDir()
		outputDir := filepath.Join(tmpDir, "output")
		logFile := filepath.Join(tmpDir, "batch.log")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		// Create test images
		imageNames := []string{"img1.jpg", "img2.jpg", "img3.jpg"}
		for _, name := range imageNames {
			img := createTestImage(t, 300, 200, color.RGBA{100, 100, 100, 255})
			saveTestImage(t, img, filepath.Join(tmpDir, name), "jpeg")
		}

		// Post-process appends to log file
		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#FFFFFF",
			BorderThickness: "5",
			NoCaption:       true,
			JPEGQuality:     90,
			OutputFormat:    "jpeg",
			Padding:         "0",
			PostProcess:     "echo {file} >> " + logFile,
		}

		// Process each image
		for _, name := range imageNames {
			inputPath := filepath.Join(tmpDir, name)
			err := processImage(inputPath, outputDir, config)
			if err != nil {
				t.Errorf("processImage() error for %s = %v", name, err)
			}
		}

		// Verify log file contains all output paths
		logContent, err := os.ReadFile(logFile)
		if err != nil {
			t.Fatalf("Failed to read log file: %v", err)
		}

		for _, name := range imageNames {
			baseName := strings.TrimSuffix(name, ".jpg")
			expectedOutput := filepath.Join(outputDir, baseName+"_solid.jpg")
			if !strings.Contains(string(logContent), expectedOutput) {
				t.Errorf("Log file should contain %q", expectedOutput)
			}
		}
	})
}

func TestErrorHandling(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	t.Run("missing input file", func(t *testing.T) {
		tmpDir := t.TempDir()
		outputDir := filepath.Join(tmpDir, "output")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		inputPath := filepath.Join(tmpDir, "nonexistent.jpg")
		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#FFFFFF",
			BorderThickness: "30",
			JPEGQuality:     95,
			OutputFormat:    "jpeg",
			Padding:         "0",
		}

		err := processImage(inputPath, outputDir, config)
		if err == nil {
			t.Error("Expected error for missing input file, got nil")
		}
	})

	t.Run("invalid border thickness", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")

		img := createTestImage(t, 400, 300, color.RGBA{128, 128, 128, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "#FFFFFF",
			BorderThickness: "invalid",
			JPEGQuality:     95,
			OutputFormat:    "jpeg",
			Padding:         "0",
		}

		err := processImage(inputPath, outputDir, config)
		if err == nil {
			t.Error("Expected error for invalid border thickness, got nil")
		}
	})

	t.Run("invalid color code", func(t *testing.T) {
		tmpDir := t.TempDir()
		inputPath := filepath.Join(tmpDir, "input.jpg")
		outputDir := filepath.Join(tmpDir, "output")

		img := createTestImage(t, 400, 300, color.RGBA{128, 128, 128, 255})
		saveTestImage(t, img, inputPath, "jpeg")

		if err := os.MkdirAll(outputDir, 0755); err != nil {
			t.Fatalf("Failed to create output directory: %v", err)
		}

		config := ProcessingConfig{
			BorderStyle:     "solid",
			BorderColor:     "invalid",
			BorderThickness: "30",
			JPEGQuality:     95,
			OutputFormat:    "jpeg",
			Padding:         "0",
		}

		err := processImage(inputPath, outputDir, config)
		if err == nil {
			t.Error("Expected error for invalid color code, got nil")
		}
	})
}
