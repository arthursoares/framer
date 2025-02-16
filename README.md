# Framer

A Go utility that adds elegant borders and captions to your photos. Perfect for creating consistent photo presentations for social media or portfolios.

![Example Images](docs/examples.png)

## Features

- Two border styles:
  - `solid`: Clean, colored border with customizable padding
  - `instagram`: 4:5 ratio frame (1080x1350px) optimized for Instagram

- Caption features:
  - Automatic EXIF date extraction (displays as "MON 'YY")
  - Custom caption text support
  - Multiple embedded fonts
  - Customizable font size and color

- Border customization:
  - Percentage or pixel-based thickness
  - Color selection via hex values
  - Optional padding

## Installation

### From Source

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/framer.git
   cd framer
   ```

2. Build the executable:
   ```bash
   go build frameit.go fonts.go
   ```

3. Optional: Move the binary to your PATH for global access:
   ```bash
   sudo mv frameit /usr/local/bin/
   ```

## Usage

```bash
# Process a single file with default settings
./frameit -i /path/to/image.jpg -o /path/to/output_folder

# Process with custom border and font
./frameit -i /path/to/image.jpg -o /path/to/output_folder -t 5% --font-size 50 --font-name "AmericanTypewriter" --border-color "#000000"

# Process a folder of images
./frameit -i /path/to/folder -o /path/to/output_folder

# Instagram formatting with maximum size 900px
./frameit -i /path/to/image.jpg -o /path/to/output_folder --border-style instagram --instagram-max-size 900

# List available embedded fonts
./frameit --list-fonts
```

## Available Fonts

The following fonts are embedded into the binary:
- `CourierPrime-Bold` (default)
- `AmericanTypewriter`
- `BigBlueTermPlusNerdFont-Regular`
- `HeavyDataNerdFont-Regular`

## Adding New Fonts

To add new fonts to the application:

1. Place your TTF or TTC font file in the `fonts_data/` directory
2. Update the `availableFonts` array in `frameit.go` to include your font name (without extension)
3. Regenerate the embedded font data:
   ```bash
   go get -u github.com/go-bindata/go-bindata/...
   go install github.com/go-bindata/go-bindata/...
   $(go env GOPATH)/bin/go-bindata -pkg main -o fonts.go fonts_data/
   ```
4. Rebuild the application:
   ```bash
   go build frameit.go fonts.go
   ```

## Command-line Arguments

- `--input`, `-i`: Path to a JPEG file or a folder containing JPEG files
- `--output`, `-o`: Output folder where processed images will be saved
- `--border-thickness`, `-t`: Border thickness in pixels or as a percentage (e.g. '10%')
- `--border-style`, `-s`: Border style: 'solid' or 'instagram'
- `--border-color`: Border color in hex (default: '#000000')
- `--caption`: Override the caption text (if empty, EXIF date is used)
- `--font-name`: Name of the font to use (run with --list-fonts to see available options)
- `--font-size`: Font size in pixels
- `--font-color`: Font color in hex (default: '#000000')
- `--instagram-max-size`: Maximum width/height for the image in Instagram style
- `--padding`: Additional padding around the image in pixels
- `--list-fonts`: List all available embedded fonts and exit

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.