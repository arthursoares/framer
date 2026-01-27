package main

import (
	"image"
	"image/color"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestHexToRGB(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    color.RGBA
		wantErr bool
	}{
		{"valid black", "#000000", color.RGBA{0, 0, 0, 255}, false},
		{"valid white", "#FFFFFF", color.RGBA{255, 255, 255, 255}, false},
		{"valid red", "#FF0000", color.RGBA{255, 0, 0, 255}, false},
		{"without hash", "FF0000", color.RGBA{255, 0, 0, 255}, false},
		{"lowercase", "#ff00aa", color.RGBA{255, 0, 170, 255}, false},
		{"mixed case", "#FfAa00", color.RGBA{255, 170, 0, 255}, false},
		{"too short", "#FFF", color.RGBA{}, true},
		{"too long", "#FFFFFFF", color.RGBA{}, true},
		{"invalid chars", "#GGGGGG", color.RGBA{}, true},
		{"empty", "", color.RGBA{}, true},
		{"only hash", "#", color.RGBA{}, true},
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

func TestGenerateCaptionFromDate(t *testing.T) {
	tests := []struct {
		name string
		date time.Time
		want string
	}{
		{
			name: "valid january date",
			date: time.Date(2024, time.January, 15, 0, 0, 0, 0, time.UTC),
			want: " - JAN '24 -",
		},
		{
			name: "december date",
			date: time.Date(2023, time.December, 25, 0, 0, 0, 0, time.UTC),
			want: " - DEC '23 -",
		},
		{
			name: "march date",
			date: time.Date(2022, time.March, 1, 0, 0, 0, 0, time.UTC),
			want: " - MAR '22 -",
		},
		{
			name: "zero time",
			date: time.Time{},
			want: " - --- -",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := generateCaptionFromDate(tt.date)
			if got != tt.want {
				t.Errorf("generateCaptionFromDate() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestApplyTemplate(t *testing.T) {
	testDate := time.Date(2024, time.March, 15, 14, 30, 0, 0, time.UTC)

	tests := []struct {
		name     string
		template string
		data     *ExifData
		want     string
	}{
		{
			name:     "all date fields",
			template: "{{year}}-{{month}}-{{day}}",
			data:     &ExifData{DateTime: testDate},
			want:     "2024-March-15",
		},
		{
			name:     "short date format",
			template: "{{mon}} '{{year2}}",
			data:     &ExifData{DateTime: testDate},
			want:     "MAR '24",
		},
		{
			name:     "camera and exposure",
			template: "{{camera}} • {{iso}} {{aperture}} {{shutter}}",
			data: &ExifData{
				Camera:       "Canon EOS R5",
				ISO:          "ISO 400",
				Aperture:     "f/2.8",
				ShutterSpeed: "1/500",
			},
			want: "Canon EOS R5 • ISO 400 f/2.8 1/500",
		},
		{
			name:     "camera and lens",
			template: "{{camera}} + {{lens}}",
			data: &ExifData{
				Camera: "Nikon Z9",
				Lens:   "NIKKOR Z 85mm f/1.8 S",
			},
			want: "Nikon Z9 + NIKKOR Z 85mm f/1.8 S",
		},
		{
			name:     "empty fields cleaned up",
			template: "{{camera}} • {{lens}} • {{iso}}",
			data: &ExifData{
				Camera: "Sony A7 IV",
				ISO:    "ISO 800",
			},
			want: "Sony A7 IV • • ISO 800",
		},
		{
			name:     "no date zero time",
			template: "{{year}} {{mon}}",
			data:     &ExifData{},
			want:     "",
		},
		{
			name:     "focal length",
			template: "{{focal}} at {{aperture}}",
			data: &ExifData{
				FocalLength: "50mm",
				Aperture:    "f/1.4",
			},
			want: "50mm at f/1.4",
		},
		{
			name:     "complete exposure info",
			template: "{{iso}} • {{shutter}} • {{aperture}} • {{focal}}",
			data: &ExifData{
				ISO:          "ISO 200",
				ShutterSpeed: "1/250",
				Aperture:     "f/5.6",
				FocalLength:  "35mm",
			},
			want: "ISO 200 • 1/250 • f/5.6 • 35mm",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := applyTemplate(tt.template, tt.data)
			if got != tt.want {
				t.Errorf("applyTemplate() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestCalculateBorderThickness(t *testing.T) {
	tests := []struct {
		name      string
		thickness string
		imageSize image.Point
		want      int
		wantErr   bool
	}{
		{
			name:      "absolute pixels",
			thickness: "50",
			imageSize: image.Point{1000, 800},
			want:      50,
			wantErr:   false,
		},
		{
			name:      "percentage 5% of min dimension",
			thickness: "5%",
			imageSize: image.Point{1000, 800},
			want:      40, // 5% of 800 (min)
			wantErr:   false,
		},
		{
			name:      "percentage 10% vertical image",
			thickness: "10%",
			imageSize: image.Point{800, 1000},
			want:      80, // 10% of 800 (min)
			wantErr:   false,
		},
		{
			name:      "percentage 2.5%",
			thickness: "2.5%",
			imageSize: image.Point{2000, 1500},
			want:      37, // 2.5% of 1500 (min)
			wantErr:   false,
		},
		{
			name:      "zero pixels",
			thickness: "0",
			imageSize: image.Point{1000, 800},
			want:      0,
			wantErr:   false,
		},
		{
			name:      "large border",
			thickness: "200",
			imageSize: image.Point{1000, 800},
			want:      200,
			wantErr:   false,
		},
		{
			name:      "invalid string",
			thickness: "abc",
			imageSize: image.Point{1000, 800},
			want:      0,
			wantErr:   true,
		},
		{
			name:      "invalid percentage",
			thickness: "abc%",
			imageSize: image.Point{1000, 800},
			want:      0,
			wantErr:   true,
		},
		{
			name:      "empty string",
			thickness: "",
			imageSize: image.Point{1000, 800},
			want:      0,
			wantErr:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := calculateBorderThickness(tt.thickness, tt.imageSize)
			if (err != nil) != tt.wantErr {
				t.Errorf("calculateBorderThickness() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && got != tt.want {
				t.Errorf("calculateBorderThickness() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestCalculateFontSize(t *testing.T) {
	tests := []struct {
		name            string
		fontSizeStr     string
		borderThickness int
		want            int
		wantErr         bool
	}{
		{
			name:            "explicit size",
			fontSizeStr:     "50",
			borderThickness: 100,
			want:            50,
			wantErr:         false,
		},
		{
			name:            "auto small border",
			fontSizeStr:     "",
			borderThickness: 30,
			want:            15, // 30 * 0.5
			wantErr:         false,
		},
		{
			name:            "auto medium border",
			fontSizeStr:     "",
			borderThickness: 60,
			want:            42, // 60 * 0.7
			wantErr:         false,
		},
		{
			name:            "auto large border",
			fontSizeStr:     "",
			borderThickness: 100,
			want:            90, // 100 * 0.9
			wantErr:         false,
		},
		{
			name:            "auto at small threshold",
			fontSizeStr:     "",
			borderThickness: SmallBorderThreshold,
			want:            int(float64(SmallBorderThreshold) * MediumFontScale),
			wantErr:         false,
		},
		{
			name:            "auto at medium threshold",
			fontSizeStr:     "",
			borderThickness: MediumBorderThreshold,
			want:            int(float64(MediumBorderThreshold) * LargeFontScale),
			wantErr:         false,
		},
		{
			name:            "zero border auto",
			fontSizeStr:     "",
			borderThickness: 0,
			want:            0,
			wantErr:         false,
		},
		{
			name:            "explicit zero size",
			fontSizeStr:     "0",
			borderThickness: 100,
			want:            0,
			wantErr:         false,
		},
		{
			name:            "invalid string",
			fontSizeStr:     "abc",
			borderThickness: 100,
			want:            0,
			wantErr:         true,
		},
		{
			name:            "explicit large size",
			fontSizeStr:     "120",
			borderThickness: 50,
			want:            120,
			wantErr:         false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := calculateFontSize(tt.fontSizeStr, tt.borderThickness)
			if (err != nil) != tt.wantErr {
				t.Errorf("calculateFontSize() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && got != tt.want {
				t.Errorf("calculateFontSize() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestValidateFontName(t *testing.T) {
	tests := []struct {
		name     string
		fontName string
		want     string
	}{
		{
			name:     "valid font 1",
			fontName: "CourierPrime-Bold",
			want:     "CourierPrime-Bold",
		},
		{
			name:     "valid font 2",
			fontName: "BigBlueTermPlusNerdFont-Regular",
			want:     "BigBlueTermPlusNerdFont-Regular",
		},
		{
			name:     "valid font 3",
			fontName: "HeavyDataNerdFont-Regular",
			want:     "HeavyDataNerdFont-Regular",
		},
		{
			name:     "invalid font",
			fontName: "NonExistent",
			want:     "CourierPrime-Bold", // Falls back to default
		},
		{
			name:     "empty string",
			fontName: "",
			want:     "CourierPrime-Bold", // Falls back to default
		},
		{
			name:     "case sensitive check",
			fontName: "courierprime-bold",
			want:     "CourierPrime-Bold", // Falls back due to case mismatch
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := validateFontName(tt.fontName)
			if got != tt.want {
				t.Errorf("validateFontName() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestProcessingStats(t *testing.T) {
	t.Run("RecordSuccess increments counter", func(t *testing.T) {
		stats := &ProcessingStats{Total: 10}
		stats.RecordSuccess()
		stats.RecordSuccess()
		stats.RecordSuccess()

		if stats.Succeeded != 3 {
			t.Errorf("Expected 3 successes, got %d", stats.Succeeded)
		}
		if stats.Failed != 0 {
			t.Errorf("Expected 0 failures, got %d", stats.Failed)
		}
	})

	t.Run("RecordFailure increments counter", func(t *testing.T) {
		stats := &ProcessingStats{Total: 10}
		stats.RecordFailure()
		stats.RecordFailure()

		if stats.Failed != 2 {
			t.Errorf("Expected 2 failures, got %d", stats.Failed)
		}
		if stats.Succeeded != 0 {
			t.Errorf("Expected 0 successes, got %d", stats.Succeeded)
		}
	})

	t.Run("Duration calculates correctly", func(t *testing.T) {
		start := time.Now()
		stats := &ProcessingStats{StartTime: start}
		time.Sleep(50 * time.Millisecond)
		stats.EndTime = time.Now()

		duration := stats.Duration()
		if duration < 50*time.Millisecond {
			t.Errorf("Expected duration >= 50ms, got %v", duration)
		}
		if duration > 200*time.Millisecond {
			t.Errorf("Expected duration < 200ms, got %v", duration)
		}
	})

	t.Run("Duration with zero EndTime uses current time", func(t *testing.T) {
		start := time.Now().Add(-1 * time.Second)
		stats := &ProcessingStats{StartTime: start}

		duration := stats.Duration()
		if duration < 1*time.Second {
			t.Errorf("Expected duration >= 1s, got %v", duration)
		}
	})

	t.Run("Rate calculates files per second", func(t *testing.T) {
		stats := &ProcessingStats{
			Total:     100,
			StartTime: time.Now().Add(-10 * time.Second),
			EndTime:   time.Now(),
		}

		rate := stats.Rate()
		if rate < 9 || rate > 11 {
			t.Errorf("Expected rate ~10 files/sec, got %.2f", rate)
		}
	})

	t.Run("Rate with zero duration returns 0", func(t *testing.T) {
		now := time.Now()
		stats := &ProcessingStats{
			Total:     10,
			StartTime: now,
			EndTime:   now,
		}

		rate := stats.Rate()
		if rate != 0 {
			t.Errorf("Expected rate 0 for zero duration, got %.2f", rate)
		}
	})

	t.Run("Rate with no EndTime calculates from current time", func(t *testing.T) {
		stats := &ProcessingStats{
			Total:     50,
			StartTime: time.Now().Add(-5 * time.Second),
		}

		rate := stats.Rate()
		if rate < 9 || rate > 11 {
			t.Errorf("Expected rate ~10 files/sec, got %.2f", rate)
		}
	})

	t.Run("Complete workflow", func(t *testing.T) {
		stats := &ProcessingStats{
			Total:     10,
			StartTime: time.Now(),
		}

		// Simulate processing
		for i := 0; i < 7; i++ {
			stats.RecordSuccess()
		}
		for i := 0; i < 3; i++ {
			stats.RecordFailure()
		}

		stats.EndTime = time.Now()

		if stats.Succeeded != 7 {
			t.Errorf("Expected 7 successes, got %d", stats.Succeeded)
		}
		if stats.Failed != 3 {
			t.Errorf("Expected 3 failures, got %d", stats.Failed)
		}
		if stats.Total != 10 {
			t.Errorf("Expected total 10, got %d", stats.Total)
		}
	})
}

func TestGetAvailableFonts(t *testing.T) {
	fonts := getAvailableFonts()

	if len(fonts) == 0 {
		t.Error("Expected at least one font, got none")
	}

	// Check that default font exists
	found := false
	for _, font := range fonts {
		if font == "CourierPrime-Bold" {
			found = true
			break
		}
	}

	if !found {
		t.Error("Expected default font 'CourierPrime-Bold' in available fonts")
	}
}

func TestRunPostProcess(t *testing.T) {
	t.Run("empty command does nothing", func(t *testing.T) {
		err := runPostProcess("", "/some/file.jpg")
		if err != nil {
			t.Errorf("Expected no error for empty command, got %v", err)
		}
	})

	t.Run("placeholder replacement", func(t *testing.T) {
		tmpDir := t.TempDir()
		markerFile := filepath.Join(tmpDir, "marker.txt")
		testFile := filepath.Join(tmpDir, "test.jpg")

		// Create a test file
		err := os.WriteFile(testFile, []byte("test"), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		// Run a command that creates a marker file with the path
		// Note: {file} gets auto-quoted, so echo outputs the path correctly
		cmd := "echo {file} > " + markerFile
		err = runPostProcess(cmd, testFile)
		if err != nil {
			t.Fatalf("runPostProcess() error = %v", err)
		}

		// Verify marker file contains the correct path
		content, err := os.ReadFile(markerFile)
		if err != nil {
			t.Fatalf("Failed to read marker file: %v", err)
		}

		got := strings.TrimSpace(string(content))
		if got != testFile {
			t.Errorf("Expected placeholder to be replaced with %q, got %q", testFile, got)
		}
	})

	t.Run("command with touch creates file", func(t *testing.T) {
		tmpDir := t.TempDir()
		testFile := filepath.Join(tmpDir, "test.jpg")
		markerFile := testFile + ".processed"

		// Create a test file
		err := os.WriteFile(testFile, []byte("test"), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		// Run touch command
		err = runPostProcess("touch {file}.processed", testFile)
		if err != nil {
			t.Fatalf("runPostProcess() error = %v", err)
		}

		// Verify marker file was created
		if _, err := os.Stat(markerFile); os.IsNotExist(err) {
			t.Errorf("Expected marker file %s to exist", markerFile)
		}
	})

	t.Run("command failure returns error", func(t *testing.T) {
		err := runPostProcess("exit 1", "/some/file.jpg")
		if err == nil {
			t.Error("Expected error for failing command, got nil")
		}
	})

	t.Run("nonexistent command returns error", func(t *testing.T) {
		err := runPostProcess("nonexistent_command_12345 {file}", "/some/file.jpg")
		if err == nil {
			t.Error("Expected error for nonexistent command, got nil")
		}
	})

	t.Run("complex shell command with pipes", func(t *testing.T) {
		tmpDir := t.TempDir()
		testFile := filepath.Join(tmpDir, "test.jpg")
		outputFile := filepath.Join(tmpDir, "output.txt")

		// Create a test file
		err := os.WriteFile(testFile, []byte("test"), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		// Run a piped command
		cmd := "echo {file} | tr '/' '-' > " + outputFile
		err = runPostProcess(cmd, testFile)
		if err != nil {
			t.Fatalf("runPostProcess() error = %v", err)
		}

		// Verify output file was created
		if _, err := os.Stat(outputFile); os.IsNotExist(err) {
			t.Errorf("Expected output file %s to exist", outputFile)
		}
	})

	t.Run("file path with spaces", func(t *testing.T) {
		tmpDir := t.TempDir()
		testFile := filepath.Join(tmpDir, "test file with spaces.jpg")
		markerFile := filepath.Join(tmpDir, "spaces_test.done")

		// Create a test file with spaces in name
		err := os.WriteFile(testFile, []byte("test"), 0644)
		if err != nil {
			t.Fatalf("Failed to create test file: %v", err)
		}

		// Run a command that uses the file path - {file} is auto-quoted now
		// so paths with spaces work without manual quoting
		cmd := "cat {file} > " + markerFile
		err = runPostProcess(cmd, testFile)
		if err != nil {
			t.Fatalf("runPostProcess() error = %v", err)
		}

		// Verify marker file was created with correct content
		content, err := os.ReadFile(markerFile)
		if err != nil {
			t.Fatalf("Failed to read marker file: %v", err)
		}
		if string(content) != "test" {
			t.Errorf("Expected content 'test', got %q", string(content))
		}
	})
}
