# Framer

![](./docs/sample_solid.jpg)

A powerful Go CLI tool that adds professional borders and captions to images. Designed for photographers to post-process images exported from Adobe Lightroom with vintage-style borders and EXIF metadata captions.

| Original               | Solid Border                                                                                                 | Instagram Frame                                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| ![](./docs/sample.jpg) | ![](./docs/sample_solid.jpg)                                                                                 | ![](./docs/sample_instagram.jpg)                                                                                                      |
| ––                     | Border Style: Solid / Padding: 100px | Border Style: Instagram / Internal Image Max. Size: 1000px / Font Color: #123abc |

> **Note**: This entire project was created using [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) as an experiment in AI-assisted development.

## Inspiration

The border format is inspired by an old box of photos from my grandfather, featuring white borders with machine-printed dates.

![](./docs/inspiration.jpg)

## ✨ Features

### Border Styles
- **Solid**: Clean, colored border with customizable padding - preserves original aspect ratio
- **Instagram**: Fixed 4:5 ratio frame (1080x1350px) - optimized for Instagram posts

### Caption Customization
- **EXIF Date Extraction**: Automatically displays date as "MON 'YY" format
- **Custom Templates**: Use `{{field}}` placeholders for dynamic captions
  - `{{camera}}`, `{{lens}}`, `{{iso}}`, `{{aperture}}`, `{{shutter}}`, `{{focal}}`
  - `{{year}}`, `{{year2}}`, `{{month}}`, `{{mon}}`, `{{day}}`, `{{date}}`
- **Custom Text**: Override with any text
- **No Caption**: Disable captions entirely with `--no-caption`

### Configuration Management
- **YAML Config Files**: Save and reuse complex configurations
- **Presets**: Built-in presets (vintage, instagram, minimal)
- **Priority System**: CLI flags → --config → --preset → .framer.yaml → defaults
- **Auto-discovery**: Automatically loads `.framer.yaml` from current directory

### Performance
- **Concurrent Processing**: Multi-core batch processing with worker pool
- **Progress Bar**: Real-time progress with statistics
- **Smart Defaults**: Optimal settings for each border style
- **Fast**: Process hundreds of images efficiently

### Flexibility
- **Multiple Output Formats**: JPEG (with quality control) and PNG
- **Color Customization**: Hex color support for borders and fonts
- **Font Selection**: Multiple embedded fonts included
- **Responsive Sizing**: Percentage-based or pixel-based border thickness

## 📦 Installation

### Homebrew (macOS ARM)

```bash
# Add tap
brew tap arthursoares/framer

# Install
brew install framer

# Update
brew upgrade framer
```

### Binary Download

Download the latest binary for your platform from the [Releases](https://github.com/arthursoares/framer/releases) page:

- **macOS ARM**: `framer-darwin-arm64`
- **Linux AMD64**: `framer-linux-amd64`
- **Linux ARM64**: `framer-linux-arm64`
- **Windows AMD64**: `framer-windows-amd64.exe`

Make the binary executable (Linux/macOS):
```bash
chmod +x framer-*
sudo mv framer-* /usr/local/bin/framer
```

### From Source

Requires Go 1.22 or later.

```bash
# Clone repository
git clone https://github.com/arthursoares/framer.git
cd framer

# Build
go build framer.go fonts.go

# Install globally (optional)
sudo mv framer /usr/local/bin/
```

## 🚀 Quick Start

```bash
# Process a single image with defaults
framer -i photo.jpg -o output/

# Process a folder with progress bar
framer -i photos/ -o output/

# Use a preset
framer -i photo.jpg -o output/ --preset vintage

# Custom caption template
framer -i photo.jpg -o output/ --caption-template "{{camera}} • {{iso}} {{aperture}} {{shutter}}"

# Instagram format with custom settings
framer -i photo.jpg -o output/ -s instagram --instagram-max-size 900

# High-quality PNG output
framer -i photo.jpg -o output/ -f png --quality 100

# Process with 8 workers
framer -i photos/ -o output/ --workers 8
```

## 📖 Usage

### Basic Commands

```bash
# Single file processing
framer -i /path/to/image.jpg -o /path/to/output/

# Directory processing (batch)
framer -i /path/to/folder/ -o /path/to/output/

# List available fonts
framer --list-fonts
```

### Using Presets

Framer includes three built-in presets stored in `~/.config/framer/presets/`:

**Vintage** - Classic film look with date stamp:
```bash
framer -i photo.jpg -o output/ --preset vintage
```

**Instagram** - 4:5 ratio optimized for Instagram:
```bash
framer -i photo.jpg -o output/ --preset instagram
```

**Minimal** - Thin white border, no caption:
```bash
framer -i photo.jpg -o output/ --preset minimal
```

### Custom Configuration

Create a `.framer.yaml` file in your project directory:

```yaml
border_style: solid
border_thickness: "5%"
border_color: "#000000"
padding: "150"
font_name: CourierPrime-Bold
font_size: "50"
font_color: "#FFFFFF"
caption_template: "{{camera}} • {{iso}} {{aperture}}"
output_format: png
```

Then simply run:
```bash
framer -i photo.jpg -o output/
```

Override any config setting with CLI flags:
```bash
framer -i photo.jpg -o output/ --border-color "#FF0000"
```

### Caption Templates

Use `{{field}}` placeholders to create dynamic captions from EXIF data:

```bash
# Camera and exposure info
framer -i photo.jpg -o output/ --caption-template "{{camera}} • {{iso}} {{aperture}} {{shutter}}"

# Date format
framer -i photo.jpg -o output/ --caption-template "{{mon}} '{{year2}}"

# Full detail
framer -i photo.jpg -o output/ --caption-template "{{camera}} {{lens}} • {{focal}} {{aperture}} {{shutter}} {{iso}}"

# Disable caption
framer -i photo.jpg -o output/ --no-caption
```

**Available placeholders:**
- **Date/Time**: `{{year}}`, `{{year2}}`, `{{month}}`, `{{mon}}`, `{{day}}`, `{{date}}`
- **Camera**: `{{camera}}`, `{{lens}}`
- **Exposure**: `{{iso}}`, `{{aperture}}`, `{{shutter}}`, `{{focal}}`

### Advanced Examples

```bash
# Custom border with padding
framer -i photo.jpg -o output/ -t 5% --padding 150 --border-color "#000000"

# PNG output with specific quality
framer -i photo.jpg -o output/ -f png -q 95

# Process with custom font
framer -i photo.jpg -o output/ --font-name "BigBlueTermPlusNerdFont-Regular" --font-size 60 --font-color "#FF0000"

# Batch process with maximum workers
framer -i photos/ -o output/ --workers $(nproc)

# Load custom config file
framer -i photo.jpg -o output/ --config my-settings.yaml
```

## 📋 Command-line Arguments

| Flag | Shorthand | Description | Default |
|------|-----------|-------------|---------|
| `--input` | `-i` | Path to image file or directory | *required* |
| `--output` | `-o` | Output directory for processed images | *required* |
| `--border-style` | `-s` | Border style: `solid` or `instagram` | `solid` |
| `--border-thickness` | `-t` | Border thickness (pixels or percentage, e.g., `10` or `5%`) | `20` (solid), `5` (instagram) |
| `--border-color` | | Border color in hex format (e.g., `#000000`) | `#000000` |
| `--padding` | | Additional padding around image (pixels) | `150` (solid), `0` (instagram) |
| `--caption` | | Override caption with custom text | EXIF date |
| `--caption-template` | | Caption template with `{{field}}` placeholders | `" - MON 'YY -"` |
| `--no-caption` | | Disable caption entirely | `false` |
| `--font-name` | | Font name (use `--list-fonts` to see options) | `CourierPrime-Bold` |
| `--font-size` | | Font size in pixels | Auto-calculated |
| `--font-color` | | Font color in hex format | `#000000` |
| `--quality` | `-q` | JPEG output quality (60-100) | `100` |
| `--output-format` | `-f` | Output format: `jpeg` or `png` | `jpeg` |
| `--instagram-max-size` | | Max width/height for Instagram style (pixels) | `1000` |
| `--config` | | Path to YAML config file | |
| `--preset` | | Load preset from `~/.config/framer/presets/` | |
| `--workers` | `-w` | Number of concurrent workers for batch processing | CPU cores |
| `--list-fonts` | | List all available fonts and exit | |

## 🎨 Available Fonts

The following fonts are embedded in the binary:

- `CourierPrime-Bold` (default)
- `BigBlueTermPlusNerdFont-Regular`
- `HeavyDataNerdFont-Regular`

List fonts with: `framer --list-fonts`

## 🔧 Configuration Files

### Config File Locations

Framer searches for configuration in this order (highest priority first):

1. `--config path/to/config.yaml` (explicit path)
2. `--preset preset-name` (from `~/.config/framer/presets/`)
3. `./.framer.yaml` (current directory)
4. `~/.config/framer/default.yaml` (user-wide default)

### Config File Format

```yaml
# Border settings
border_style: solid              # solid or instagram
border_thickness: "20"           # pixels or percentage (e.g., "5%")
border_color: "#000000"          # hex color
padding: "150"                   # pixels

# Caption settings
caption: ""                      # explicit caption text
caption_template: " - {{mon}} '{{year2}} -"  # template with placeholders
no_caption: false                # disable caption

# Font settings
font_name: CourierPrime-Bold     # font name
font_size: "50"                  # pixels (empty = auto-calculate)
font_color: "#000000"            # hex color

# Output settings
output_format: jpeg              # jpeg or png
jpeg_quality: 100                # 60-100
```

### Creating Custom Presets

1. Copy a default preset:
```bash
cp ~/.config/framer/presets/vintage.yaml ~/.config/framer/presets/my-preset.yaml
```

2. Edit the file with your preferred settings

3. Use your preset:
```bash
framer -i photo.jpg -o output/ --preset my-preset
```

## 🔨 Adding Custom Fonts

1. Place your TTF or TTC font file in `fonts_data/`
2. Update `availableFonts` array in `framer.go`
3. Regenerate embedded fonts:
   ```bash
   go get -u github.com/go-bindata/go-bindata/...
   go install github.com/go-bindata/go-bindata/...
   $(go env GOPATH)/bin/go-bindata -pkg main -o fonts.go fonts_data/
   ```
4. Rebuild:
   ```bash
   go build framer.go fonts.go
   ```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development

```bash
# Clone repository
git clone https://github.com/arthursoares/framer.git
cd framer

# Install dependencies
go mod download

# Build
go build framer.go fonts.go

# Run tests (when available)
go test ./...
```

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built entirely with [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)
- Inspired by vintage photo printing techniques
- Uses embedded fonts for consistent cross-platform rendering

---

**Made with ❤️ and AI**
