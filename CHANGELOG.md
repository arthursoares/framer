# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- GitHub Actions CI/CD pipeline for automated builds
- Multi-platform binary releases (macOS ARM, Linux AMD64/ARM64, Windows AMD64)
- Comprehensive README documentation
- Homebrew installation support

## [1.0.0] - TBD

This is the first major release of Framer, incorporating all improvements from development branches.

### Added

#### Branch 8: Batch Processing Improvements
- **Concurrent Processing**: Multi-core batch processing with worker pool pattern
- **Progress Bar**: Real-time progress indication using progressbar/v3
- **Statistics Tracking**: Detailed batch processing statistics (success/failure counts, duration, rate)
- **`--workers` Flag**: Configure number of concurrent workers (default: CPU cores)
- **Performance**: 2-3x speedup for batch operations

#### Branch 7: Configuration Presets
- **YAML Config Support**: Save and reuse configurations in YAML format
- **Built-in Presets**: Three default presets (vintage, instagram, minimal)
- **Priority System**: Config loading priority (--config → --preset → .framer.yaml → defaults)
- **`--config` Flag**: Load custom configuration files
- **`--preset` Flag**: Load named presets from ~/.config/framer/presets/
- **Auto-discovery**: Automatically loads .framer.yaml from current directory
- **Font Validation**: Automatic validation and fallback for invalid fonts

#### Branch 6: Caption Templates
- **Template System**: `{{field}}` placeholder support for dynamic captions
- **EXIF Data Extraction**: Comprehensive metadata extraction (camera, lens, exposure settings)
- **`--caption-template` Flag**: Custom caption templates with EXIF placeholders
- **Template Fields**: {{camera}}, {{lens}}, {{iso}}, {{aperture}}, {{shutter}}, {{focal}}, {{year}}, {{month}}, {{day}}, etc.
- **`--no-caption` Flag**: Disable captions entirely

#### Branch 5: Input Format Support
- **Format-Agnostic Decoding**: Support for multiple input formats
- **PNG Input**: Process PNG images
- **TIFF Input**: Process TIFF images
- **Auto-detection**: Automatic format detection based on file content

#### Branch 4: Output Format Support
- **PNG Output**: Lossless PNG output format
- **`--output-format` Flag**: Choose between JPEG and PNG output
- **Format Preservation**: Intelligent format handling

#### Branch 3: Constants and Configuration
- **Configurable Quality**: JPEG quality control (60-100 range)
- **`--quality` Flag**: Set JPEG output quality
- **Named Constants**: Extracted magic numbers to named constants
- **Instagram Frame Constants**: Configurable Instagram dimensions
- **Font Scaling Constants**: Configurable font size scaling factors

#### Branch 2: Code Refactoring
- **Modular Functions**: Refactored processImage() into focused helper functions
- **`determineCaption()`**: Extracted caption determination logic
- **`calculateBorderThickness()`**: Extracted border thickness calculation
- **`calculateFontSize()`**: Extracted font size calculation
- **Improved Maintainability**: Cleaner, more testable code structure

#### Branch 1: Cleanup and Error Handling
- **Dead Code Removal**: Removed unused padWithBorder() function
- **Error Handling**: Proper error handling for strconv.Atoi() and hexToRGB()
- **ProcessingConfig Type**: Extracted anonymous struct to named type
- **Font Cleanup**: Removed missing AmericanTypewriter reference

### Core Features (Initial Release)
- **Two Border Styles**: Solid and Instagram (4:5 ratio) borders
- **EXIF Date Extraction**: Automatic date captions from EXIF metadata
- **Custom Borders**: Percentage or pixel-based border thickness
- **Color Customization**: Hex color support for borders and fonts
- **Font Support**: Multiple embedded TrueType fonts
- **Batch Processing**: Process entire directories of images
- **`--font-color` Flag**: Customize caption color

### Changed
- Updated error handling from logging to returning errors
- Improved performance with concurrent processing
- Enhanced configuration system with presets and YAML support
- Better user feedback with progress bars and statistics

### Fixed
- Fixed recursive processing when output is subdirectory of input
- Fixed percentage-based border thickness calculation
- Improved font loading with better fallback handling

## Release Notes

### Building from Source

```bash
git clone https://github.com/arthursoares/framer.git
cd framer
go build framer.go fonts.go
```

### Installation

See [README.md](README.md) for detailed installation instructions including Homebrew, binary downloads, and building from source.

---

**Note**: All development was done using [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) as an experiment in AI-assisted development.
