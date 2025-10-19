#!/bin/bash

# Framer Test Suite - Comprehensive Parameter Validation
# Tests all border styles with various parameter combinations

set -e

# Configuration
FRAMER="./framer"
INPUT_DIR="examples"
OUTPUT_DIR="test_output"
LOG_FILE="test_results.txt"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Input images
VERTICAL_IMG="$INPUT_DIR/L1003137.jpg"
HORIZONTAL_IMG="$INPUT_DIR/L1003172.jpg"

# Counter for test numbering
TEST_NUM=0

# Initialize log file
echo "========================================" > "$LOG_FILE"
echo "Framer Test Suite - Comprehensive Tests" >> "$LOG_FILE"
echo "Started: $TIMESTAMP" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Function to run a test and log it
run_test() {
    local description="$1"
    local style="$2"
    local image="$3"
    local output_subdir="$4"
    shift 4
    local params=("$@")

    TEST_NUM=$((TEST_NUM + 1))
    local output_path="$OUTPUT_DIR/$style/$output_subdir"

    echo "Running Test #$TEST_NUM: $description"

    # Create output directory
    mkdir -p "$output_path"

    # Run framer
    $FRAMER -i "$image" -o "$output_path" -s "$style" "${params[@]}"

    # Rename output to include test number for uniqueness
    local basename=$(basename "$image")
    local name="${basename%.*}"
    local original_output="$output_path/${name}_${style}.jpg"
    local unique_output="$output_path/test_${TEST_NUM}_${name}_${style}.jpg"

    if [ -f "$original_output" ]; then
        mv "$original_output" "$unique_output"
    fi

    # Log the test
    echo "Test #$TEST_NUM: $description" >> "$LOG_FILE"
    echo "  Style: $style" >> "$LOG_FILE"
    echo "  Input: $image" >> "$LOG_FILE"
    echo "  Output: $unique_output" >> "$LOG_FILE"
    echo "  Parameters: ${params[*]}" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

echo "=========================================="
echo "Framer Test Suite"
echo "=========================================="
echo ""

# Create base output directory
mkdir -p "$OUTPUT_DIR"

echo "Phase 1: Testing SOLID border style"
echo "--------------------------------------"

run_test "Solid - Default black border" "solid" "$HORIZONTAL_IMG" "default" \
    --border-thickness "20"

run_test "Solid - Thick border with padding" "solid" "$HORIZONTAL_IMG" "thick_padding" \
    --border-thickness "30" --padding "150" --border-color "#000000"

run_test "Solid - White border with custom caption" "solid" "$VERTICAL_IMG" "white_custom" \
    --border-thickness "25" --border-color "#FFFFFF" --padding "100" \
    --caption "Leica M11 Test"

run_test "Solid - Red border, no caption" "solid" "$HORIZONTAL_IMG" "red_no_caption" \
    --border-thickness "15" --border-color "#8B0000" --no-caption

echo ""
echo "Phase 2: Testing INSTAGRAM border style"
echo "--------------------------------------"

run_test "Instagram - Default settings" "instagram" "$VERTICAL_IMG" "default"

run_test "Instagram - Black border" "instagram" "$HORIZONTAL_IMG" "black_border" \
    --border-thickness "10" --border-color "#000000"

run_test "Instagram - Navy border with custom caption" "instagram" "$VERTICAL_IMG" "navy_custom" \
    --border-thickness "8" --border-color "#000080" \
    --caption-template "{{mon}} '{{year2}}"

run_test "Instagram - Thin border no caption" "instagram" "$HORIZONTAL_IMG" "thin_no_caption" \
    --border-thickness "3" --no-caption

echo ""
echo "Phase 3: Testing PRINT10X15 border style"
echo "--------------------------------------"

# Default tests
run_test "Print10x15 - Default white background (horizontal)" "print10x15" "$HORIZONTAL_IMG" "default" \
    --outer-padding "50" --caption-padding "20"

run_test "Print10x15 - Default white background (vertical - rotation test)" "print10x15" "$VERTICAL_IMG" "default" \
    --outer-padding "50" --caption-padding "20"

# Background color variations
run_test "Print10x15 - Beige background" "print10x15" "$HORIZONTAL_IMG" "backgrounds" \
    --bg-color "#F5F5DC" --outer-padding "50" --caption-padding "20"

run_test "Print10x15 - Cream background" "print10x15" "$VERTICAL_IMG" "backgrounds" \
    --bg-color "#FFFACD" --outer-padding "50" --caption-padding "20"

run_test "Print10x15 - Light gray background" "print10x15" "$HORIZONTAL_IMG" "backgrounds" \
    --bg-color "#E5E5E5" --outer-padding "50" --caption-padding "20"

run_test "Print10x15 - Light blue background" "print10x15" "$VERTICAL_IMG" "backgrounds" \
    --bg-color "#E6F2FF" --outer-padding "50" --caption-padding "20"

# Outer padding variations
run_test "Print10x15 - Minimal outer padding (30px)" "print10x15" "$HORIZONTAL_IMG" "paddings" \
    --outer-padding "30" --caption-padding "20" --bg-color "#FFFFFF"

run_test "Print10x15 - Standard outer padding (50px)" "print10x15" "$VERTICAL_IMG" "paddings" \
    --outer-padding "50" --caption-padding "20" --bg-color "#FFFFFF"

run_test "Print10x15 - Large outer padding (80px)" "print10x15" "$HORIZONTAL_IMG" "paddings" \
    --outer-padding "80" --caption-padding "20" --bg-color "#FFFFFF"

run_test "Print10x15 - Extra large outer padding (100px)" "print10x15" "$VERTICAL_IMG" "paddings" \
    --outer-padding "100" --caption-padding "20" --bg-color "#FFFFFF"

# Caption padding variations
run_test "Print10x15 - Minimal caption padding (10px)" "print10x15" "$HORIZONTAL_IMG" "paddings" \
    --outer-padding "50" --caption-padding "10" --bg-color "#FFFFFF"

run_test "Print10x15 - Large caption padding (30px)" "print10x15" "$VERTICAL_IMG" "paddings" \
    --outer-padding "50" --caption-padding "30" --bg-color "#FFFFFF"

run_test "Print10x15 - Extra large caption padding (40px)" "print10x15" "$HORIZONTAL_IMG" "paddings" \
    --outer-padding "50" --caption-padding "40" --bg-color "#FFFFFF"

# Font variations
run_test "Print10x15 - Small font (20px)" "print10x15" "$VERTICAL_IMG" "fonts" \
    --font-size "20" --outer-padding "50" --caption-padding "20"

run_test "Print10x15 - Medium font (30px - default)" "print10x15" "$HORIZONTAL_IMG" "fonts" \
    --font-size "30" --outer-padding "50" --caption-padding "20"

run_test "Print10x15 - Large font (40px)" "print10x15" "$VERTICAL_IMG" "fonts" \
    --font-size "40" --outer-padding "50" --caption-padding "20"

run_test "Print10x15 - Extra large font (50px)" "print10x15" "$HORIZONTAL_IMG" "fonts" \
    --font-size "50" --outer-padding "50" --caption-padding "20"

# Caption options
run_test "Print10x15 - Custom caption" "print10x15" "$HORIZONTAL_IMG" "captions" \
    --caption "Leica M11 • 2024" --outer-padding "50" --caption-padding "20"

run_test "Print10x15 - Template caption" "print10x15" "$VERTICAL_IMG" "captions" \
    --caption-template "{{camera}} • {{mon}} '{{year2}}" \
    --outer-padding "50" --caption-padding "20"

run_test "Print10x15 - No caption" "print10x15" "$HORIZONTAL_IMG" "captions" \
    --no-caption --outer-padding "50" --caption-padding "20"

# Combined variations
run_test "Print10x15 - Beige + large padding + large font" "print10x15" "$VERTICAL_IMG" "combined" \
    --bg-color "#F5F5DC" --outer-padding "80" --caption-padding "30" --font-size "40"

run_test "Print10x15 - Gray + minimal padding + small font" "print10x15" "$HORIZONTAL_IMG" "combined" \
    --bg-color "#E5E5E5" --outer-padding "30" --caption-padding "10" --font-size "20"

run_test "Print10x15 - Cream + custom caption + large font" "print10x15" "$VERTICAL_IMG" "combined" \
    --bg-color "#FFFACD" --outer-padding "60" --caption-padding "25" \
    --font-size "45" --caption "Vintage Film Look"

echo ""
echo "=========================================="
echo "Test Suite Complete!"
echo "=========================================="
echo "Total tests run: $TEST_NUM"
echo "Output directory: $OUTPUT_DIR"
echo "Test log: $LOG_FILE"
echo ""

# Add summary to log
echo "========================================" >> "$LOG_FILE"
echo "Test Suite Completed" >> "$LOG_FILE"
echo "Total Tests: $TEST_NUM" >> "$LOG_FILE"
echo "Finished: $(date +"%Y-%m-%d %H:%M:%S")" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

echo "Review test_output/ directory to validate results"
