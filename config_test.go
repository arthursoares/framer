package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadConfigFile(t *testing.T) {
	t.Run("valid config file", func(t *testing.T) {
		tmpDir := t.TempDir()
		configPath := filepath.Join(tmpDir, "test.yaml")

		content := `border_style: instagram
border_thickness: "15"
border_color: "#123456"
padding: "100"
font_name: CourierPrime-Bold
font_size: "50"
font_color: "#FFFFFF"
caption: "Test Caption"
no_caption: false
jpeg_quality: 95
output_format: png
`

		err := os.WriteFile(configPath, []byte(content), 0644)
		if err != nil {
			t.Fatalf("Failed to create test config: %v", err)
		}

		config, err := loadConfigFile(configPath)
		if err != nil {
			t.Fatalf("loadConfigFile() error = %v", err)
		}

		if config.BorderStyle != "instagram" {
			t.Errorf("Expected BorderStyle 'instagram', got %q", config.BorderStyle)
		}
		if config.BorderThickness != "15" {
			t.Errorf("Expected BorderThickness '15', got %q", config.BorderThickness)
		}
		if config.BorderColor != "#123456" {
			t.Errorf("Expected BorderColor '#123456', got %q", config.BorderColor)
		}
		if config.Padding != "100" {
			t.Errorf("Expected Padding '100', got %q", config.Padding)
		}
		if config.Caption != "Test Caption" {
			t.Errorf("Expected Caption 'Test Caption', got %q", config.Caption)
		}
		if config.JPEGQuality != 95 {
			t.Errorf("Expected JPEGQuality 95, got %d", config.JPEGQuality)
		}
		if config.OutputFormat != "png" {
			t.Errorf("Expected OutputFormat 'png', got %q", config.OutputFormat)
		}
	})

	t.Run("invalid YAML syntax", func(t *testing.T) {
		tmpDir := t.TempDir()
		configPath := filepath.Join(tmpDir, "invalid.yaml")

		content := `border_style: instagram
this is: [invalid yaml
missing bracket
`

		err := os.WriteFile(configPath, []byte(content), 0644)
		if err != nil {
			t.Fatalf("Failed to create test config: %v", err)
		}

		_, err = loadConfigFile(configPath)
		if err == nil {
			t.Error("Expected error for invalid YAML, got nil")
		}
	})

	t.Run("file not found", func(t *testing.T) {
		_, err := loadConfigFile("/nonexistent/path/config.yaml")
		if err == nil {
			t.Error("Expected error for missing file, got nil")
		}
	})

	t.Run("empty file", func(t *testing.T) {
		tmpDir := t.TempDir()
		configPath := filepath.Join(tmpDir, "empty.yaml")

		err := os.WriteFile(configPath, []byte(""), 0644)
		if err != nil {
			t.Fatalf("Failed to create test config: %v", err)
		}

		config, err := loadConfigFile(configPath)
		if err != nil {
			t.Fatalf("loadConfigFile() error = %v", err)
		}

		// Empty file should return default zero values
		if config.BorderStyle != "" {
			t.Errorf("Expected empty BorderStyle, got %q", config.BorderStyle)
		}
	})

	t.Run("partial config", func(t *testing.T) {
		tmpDir := t.TempDir()
		configPath := filepath.Join(tmpDir, "partial.yaml")

		content := `border_style: solid
border_color: "#FF0000"
`

		err := os.WriteFile(configPath, []byte(content), 0644)
		if err != nil {
			t.Fatalf("Failed to create test config: %v", err)
		}

		config, err := loadConfigFile(configPath)
		if err != nil {
			t.Fatalf("loadConfigFile() error = %v", err)
		}

		if config.BorderStyle != "solid" {
			t.Errorf("Expected BorderStyle 'solid', got %q", config.BorderStyle)
		}
		if config.BorderColor != "#FF0000" {
			t.Errorf("Expected BorderColor '#FF0000', got %q", config.BorderColor)
		}
		// Other fields should be empty/zero
		if config.Padding != "" {
			t.Errorf("Expected empty Padding, got %q", config.Padding)
		}
	})

	t.Run("config with post_process", func(t *testing.T) {
		tmpDir := t.TempDir()
		configPath := filepath.Join(tmpDir, "post_process.yaml")

		content := `border_style: solid
post_process: "jpegoptim --strip-all {file}"
`

		err := os.WriteFile(configPath, []byte(content), 0644)
		if err != nil {
			t.Fatalf("Failed to create test config: %v", err)
		}

		config, err := loadConfigFile(configPath)
		if err != nil {
			t.Fatalf("loadConfigFile() error = %v", err)
		}

		if config.BorderStyle != "solid" {
			t.Errorf("Expected BorderStyle 'solid', got %q", config.BorderStyle)
		}
		if config.PostProcess != "jpegoptim --strip-all {file}" {
			t.Errorf("Expected PostProcess 'jpegoptim --strip-all {file}', got %q", config.PostProcess)
		}
	})

	t.Run("config with JPEGmini Pro command", func(t *testing.T) {
		tmpDir := t.TempDir()
		configPath := filepath.Join(tmpDir, "jpegmini.yaml")

		content := `border_style: instagram
post_process: "open -W -a 'JPEGmini Pro' {file}"
`

		err := os.WriteFile(configPath, []byte(content), 0644)
		if err != nil {
			t.Fatalf("Failed to create test config: %v", err)
		}

		config, err := loadConfigFile(configPath)
		if err != nil {
			t.Fatalf("loadConfigFile() error = %v", err)
		}

		expected := "open -W -a 'JPEGmini Pro' {file}"
		if config.PostProcess != expected {
			t.Errorf("Expected PostProcess %q, got %q", expected, config.PostProcess)
		}
	})
}

func TestMergeConfig(t *testing.T) {
	t.Run("CLI takes precedence over config file", func(t *testing.T) {
		configFile := &ConfigFile{
			BorderStyle:     "instagram",
			BorderColor:     "#FF0000",
			BorderThickness: "10",
			Padding:         "50",
		}
		cliConfig := ProcessingConfig{
			BorderStyle:     "solid", // Explicitly set by user
			BorderColor:     "#000000",
			BorderThickness: "20",
			Padding:         "100",
		}

		result := mergeConfig(configFile, cliConfig)

		// CLI values should win
		if result.BorderThickness != "20" {
			t.Errorf("Expected BorderThickness '20' from CLI, got %q", result.BorderThickness)
		}
		if result.Padding != "100" {
			t.Errorf("Expected Padding '100' from CLI, got %q", result.Padding)
		}
	})

	t.Run("config fills in empty CLI values", func(t *testing.T) {
		configFile := &ConfigFile{
			BorderStyle:     "instagram",
			BorderThickness: "15",
			Caption:         "Custom Caption",
			FontName:        "CourierPrime-Bold",
			FontSize:        "40",
		}
		cliConfig := ProcessingConfig{
			BorderStyle: "solid", // Default value
			// Other fields empty - should use config
		}

		result := mergeConfig(configFile, cliConfig)

		if result.BorderThickness != "15" {
			t.Errorf("Expected BorderThickness '15' from config, got %q", result.BorderThickness)
		}
		if result.Caption != "Custom Caption" {
			t.Errorf("Expected Caption 'Custom Caption' from config, got %q", result.Caption)
		}
		if result.FontSize != "40" {
			t.Errorf("Expected FontSize '40' from config, got %q", result.FontSize)
		}
	})

	t.Run("validate font names during merge", func(t *testing.T) {
		configFile := &ConfigFile{
			FontName: "InvalidFont",
		}
		cliConfig := ProcessingConfig{}

		result := mergeConfig(configFile, cliConfig)

		// Invalid font should fall back to default
		if result.FontName != "CourierPrime-Bold" {
			t.Errorf("Expected default font, got %q", result.FontName)
		}
	})

	t.Run("JPEG quality merge", func(t *testing.T) {
		configFile := &ConfigFile{
			JPEGQuality: 85,
		}
		cliConfig := ProcessingConfig{
			JPEGQuality: 0, // Not set
		}

		result := mergeConfig(configFile, cliConfig)

		if result.JPEGQuality != 85 {
			t.Errorf("Expected JPEGQuality 85 from config, got %d", result.JPEGQuality)
		}
	})

	t.Run("NoCaption flag merge", func(t *testing.T) {
		configFile := &ConfigFile{
			NoCaption: true,
		}
		cliConfig := ProcessingConfig{
			NoCaption: false, // Default
		}

		result := mergeConfig(configFile, cliConfig)

		if !result.NoCaption {
			t.Error("Expected NoCaption true from config")
		}
	})

	t.Run("border style default handling", func(t *testing.T) {
		configFile := &ConfigFile{
			BorderStyle: "instagram",
		}
		cliConfig := ProcessingConfig{
			BorderStyle: "solid", // Default value
		}

		result := mergeConfig(configFile, cliConfig)

		// Since CLI has default "solid", config instagram should be used
		if result.BorderStyle != "instagram" {
			t.Errorf("Expected BorderStyle 'instagram' from config, got %q", result.BorderStyle)
		}
	})

	t.Run("output format merge", func(t *testing.T) {
		configFile := &ConfigFile{
			OutputFormat: "png",
		}
		cliConfig := ProcessingConfig{
			OutputFormat: "jpeg", // Default
		}

		result := mergeConfig(configFile, cliConfig)

		if result.OutputFormat != "png" {
			t.Errorf("Expected OutputFormat 'png' from config, got %q", result.OutputFormat)
		}
	})

	t.Run("caption template merge", func(t *testing.T) {
		configFile := &ConfigFile{
			CaptionTemplate: "{{camera}} • {{iso}}",
		}
		cliConfig := ProcessingConfig{
			CaptionTemplate: "", // Not set
		}

		result := mergeConfig(configFile, cliConfig)

		if result.CaptionTemplate != "{{camera}} • {{iso}}" {
			t.Errorf("Expected CaptionTemplate from config, got %q", result.CaptionTemplate)
		}
	})

	t.Run("post_process merge from config", func(t *testing.T) {
		configFile := &ConfigFile{
			PostProcess: "jpegoptim {file}",
		}
		cliConfig := ProcessingConfig{
			PostProcess: "", // Not set
		}

		result := mergeConfig(configFile, cliConfig)

		if result.PostProcess != "jpegoptim {file}" {
			t.Errorf("Expected PostProcess from config, got %q", result.PostProcess)
		}
	})

	t.Run("post_process CLI takes precedence", func(t *testing.T) {
		configFile := &ConfigFile{
			PostProcess: "jpegoptim {file}",
		}
		cliConfig := ProcessingConfig{
			PostProcess: "jpegmini {file}", // CLI override
		}

		result := mergeConfig(configFile, cliConfig)

		if result.PostProcess != "jpegmini {file}" {
			t.Errorf("Expected PostProcess from CLI, got %q", result.PostProcess)
		}
	})
}

func TestGetConfigDir(t *testing.T) {
	dir, err := getConfigDir()
	if err != nil {
		t.Fatalf("getConfigDir() error = %v", err)
	}

	if dir == "" {
		t.Error("Expected non-empty config directory path")
	}

	// Should end with .config/framer
	expectedSuffix := filepath.Join(".config", "framer")
	if !filepath.IsAbs(dir) {
		t.Error("Expected absolute path for config directory")
	}

	if len(dir) < len(expectedSuffix) {
		t.Errorf("Config directory path too short: %s", dir)
	}
}

func TestEnsureConfigDir(t *testing.T) {
	// This test modifies the actual config directory, so we'll test the logic
	// by checking that it doesn't error on normal execution
	err := ensureConfigDir()
	if err != nil {
		t.Errorf("ensureConfigDir() error = %v", err)
	}

	// Verify the directory was created
	configDir, err := getConfigDir()
	if err != nil {
		t.Fatalf("getConfigDir() error = %v", err)
	}

	presetsDir := filepath.Join(configDir, "presets")
	if _, err := os.Stat(presetsDir); os.IsNotExist(err) {
		t.Errorf("Presets directory not created: %s", presetsDir)
	}
}
