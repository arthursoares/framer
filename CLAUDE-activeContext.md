# Active Context - Framer Improvement Plan

## Current Session Goal
Systematically implementing feature improvements across multiple focused branches. Currently working on feature enhancements after completing Priority 1 cleanup and refactoring tasks.

## Active Work Status
**Phase**: Feature Development (Priority 2)
**Branch Strategy**: Incremental improvements via feature branches
**Completed**: Branches 1-7 (Cleanup, Refactoring, Constants, Output Formats, Input Formats, Caption Templates, Config Presets)
**Next**: Branch 8 (Batch Improvements) or other Priority 3 features

## Planned Branch Workflow

### Branch 1: `cleanup/dead-code-and-errors` (Priority 1) ✅
**Goal**: Remove technical debt and improve code quality
**Status**: Completed
**Tasks**:
- Remove dead code (lines 188-190 in framer.go)
- Remove unused `padWithBorder()` function (lines 87-103)
- Remove or fix `AmericanTypewriter` font reference (missing from fonts_data/)
- Add proper error handling for `strconv.Atoi()` calls
- Add error handling for `hexToRGB()` conversions
- Extract anonymous struct to named `ProcessingConfig` type

### Branch 2: `refactor/process-image` (Priority 1) ✅
**Goal**: Break down large functions into maintainable units
**Status**: Completed
**Tasks**:
- Split `processImage()` function into smaller, focused functions
- Extract caption text determination logic
- Extract border thickness calculation logic
- Extract font size calculation logic
- Improve function signatures and documentation

### Branch 3: `refactor/constants-config` (Priority 1) ✅
**Goal**: Make hardcoded values configurable
**Status**: Completed
**Tasks**:
- Extract magic numbers to constants/config
- Make Instagram frame dimensions (1080x1350) configurable
- Make font scaling factors (0.5, 0.7, 0.9) configurable
- Make JPEG quality (100) configurable
- Add `--quality` flag for JPEG compression

### Branch 4: `feature/output-formats` (Priority 2) ✅
**Goal**: Support multiple output formats
**Status**: Completed
**Tasks**:
- Add PNG output support ✅
- Add `--output-format` flag (jpeg, png) ✅
- ~~Add `--quality` flag for JPEG (60-100 range)~~ ✅ (Completed in Branch 3)
- Update output filename logic for different formats ✅

### Branch 5: `feature/input-formats` (Priority 2)
**Goal**: Support more input image formats
**Status**: Not Started
**Tasks**:
- Replace `jpeg.Decode()` with format-agnostic `image.Decode()`
- Support PNG input
- Support TIFF input
- Support HEIC input (if feasible)
- Update file extension detection in directory walker

### Branch 6: `feature/caption-templates` (Priority 2) ✅
**Goal**: Flexible caption customization
**Status**: Completed
**Tasks**:
- Design template syntax: `{{month}} {{year}} - {{camera}}` ✅
- Extract additional EXIF fields (camera, ISO, aperture, focal length) ✅
- Add `--caption-template` flag ✅
- ~~Add caption position options (top/bottom/left/right)~~ (Deferred - current positioning works well)
- Add `--no-caption` flag ✅

**Implementation Highlights**:
- Created ExifData struct with DateTime, Camera, Lens, ISO, Aperture, ShutterSpeed, FocalLength
- Implemented comprehensive EXIF extraction with getExifData()
- Added applyTemplate() function with {{field}} placeholder substitution
- Caption priority: NoCaption > Caption > Template > Default
- Supports {{year}}, {{year2}}, {{month}}, {{mon}}, {{day}}, {{date}}, {{camera}}, {{lens}}, {{iso}}, {{aperture}}, {{shutter}}, {{focal}}

### Branch 7: `feature/config-presets` (Priority 2) ✅
**Goal**: Reusable configuration presets
**Status**: Completed
**Tasks**:
- Design YAML config file format ✅
- Add `--preset` flag to load preset files ✅
- Add `--config` flag to load custom config files ✅
- Create default presets (vintage, instagram, minimal) ✅
- ~~Add `--save-preset` flag to save current settings~~ (Deferred - manual YAML editing works well)

**Implementation Highlights**:
- Added gopkg.in/yaml.v3 dependency
- Created ConfigFile struct with yaml tags
- Implemented priority-based config loading: --config → --preset → ./.framer.yaml → ~/.config/framer/default.yaml
- Auto-creates ~/.config/framer/presets/ with three default presets on first run
- CLI flags always override config file values
- Added font validation with automatic fallback to default
- Tested: config directory creation, preset loading, priority system, CLI overrides, font validation

### Branch 8: `feature/batch-improvements` (Priority 3)
**Goal**: Improve batch processing UX and performance
**Status**: Not Started
**Tasks**:
- Add progress bar (using `github.com/schollz/progressbar`)
- Implement concurrent processing with goroutines
- Add `--workers N` flag for parallel processing
- Add processing statistics summary

### Branch 9: `feature/border-styles` (Priority 3)
**Goal**: Additional creative border options
**Status**: Not Started
**Tasks**:
- Implement Polaroid style (thick bottom border)
- Implement film strip style with sprocket holes
- Implement double/nested borders
- Implement gradient borders
- Add border style preview examples to README

### Branch 10: `feature/testing` (Priority 3)
**Goal**: Establish testing foundation
**Status**: Not Started
**Tasks**:
- Set up testing infrastructure
- Add unit tests for helper functions (hexToRGB, generateCaptionFromDate)
- Add integration tests with sample images
- Add benchmarks for performance-critical functions
- Set up CI/CD for automated testing

## Future Considerations (Backlog)

### Advanced Features (Priority 4)
- Preview mode with interactive CLI
- Watermark/logo overlay support
- Web interface with drag-and-drop
- Metadata preservation and copying
- `--keep-original` backup functionality

## Notes
- Always run tests before merging branches
- Update README.md with new features as they're added
- Keep CLAUDE-troubleshooting.md updated with discovered issues
- Document architecture decisions in CLAUDE-decisions.md
