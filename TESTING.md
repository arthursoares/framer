# Testing Guide

This document describes the testing infrastructure for the Framer project.

## Overview

The test suite is organized into multiple files, each focusing on different aspects of the application:

- **`framer_test.go`**: Unit tests for core functions
- **`config_test.go`**: Configuration loading and merging tests
- **`integration_test.go`**: End-to-end workflow tests
- **`benchmark_test.go`**: Performance benchmarks

## Running Tests

### Run All Tests

```bash
go test ./...
```

### Run Tests with Verbose Output

```bash
go test -v ./...
```

### Run Specific Test File

```bash
go test -v -run TestHexToRGB
```

### Run Tests with Coverage

```bash
go test -cover ./...
```

### Generate Coverage Report

```bash
# Generate coverage profile
go test -coverprofile=coverage.out ./...

# View coverage in terminal
go tool cover -func=coverage.out

# Generate HTML coverage report
go tool cover -html=coverage.out -o coverage.html
```

### Skip Integration Tests

Integration tests can take longer to run. Skip them with:

```bash
go test -short ./...
```

### Run with Race Detection

```bash
go test -race ./...
```

## Test Organization

### Unit Tests (`framer_test.go`)

Tests for pure functions with no side effects:

- **`TestHexToRGB`**: Color parsing validation (11 test cases)
- **`TestGenerateCaptionFromDate`**: Date caption generation (4 test cases)
- **`TestApplyTemplate`**: EXIF template application (8 test cases)
- **`TestCalculateBorderThickness`**: Border size calculations (9 test cases)
- **`TestCalculateFontSize`**: Font size calculations (10 test cases)
- **`TestValidateFontName`**: Font validation (6 test cases)
- **`TestProcessingStats`**: Statistics tracking (7 sub-tests)
- **`TestGetAvailableFonts`**: Font availability check

Example:
```bash
go test -v -run TestHexToRGB
```

### Configuration Tests (`config_test.go`)

Tests for YAML configuration system:

- **`TestLoadConfigFile`**: Configuration file loading
  - Valid config parsing
  - Invalid YAML syntax handling
  - Missing file error handling
  - Empty file handling
  - Partial configuration support

- **`TestMergeConfig`**: Configuration merging logic
  - CLI precedence over config files
  - Config fills empty CLI values
  - Font name validation during merge
  - JPEG quality merging
  - NoCaption flag handling
  - Border style default handling
  - Output format merging
  - Caption template merging

- **`TestGetConfigDir`**: Config directory resolution
- **`TestEnsureConfigDir`**: Config directory creation

Example:
```bash
go test -v -run TestMergeConfig
```

### Integration Tests (`integration_test.go`)

End-to-end tests that process actual images:

- **`TestProcessImageEndToEnd`**: Full image processing pipeline
  - Solid border with caption
  - Instagram frame generation
  - Processing without captions
  - PNG output format
  - Percentage-based border thickness

- **`TestBatchProcessing`**: Batch operations
  - Multiple image processing
  - Mixed valid and invalid files
  - Statistics tracking

- **`TestErrorHandling`**: Error scenarios
  - Missing input files
  - Invalid border thickness values
  - Invalid color codes

Example:
```bash
go test -v -run TestProcessImageEndToEnd
```

### Benchmarks (`benchmark_test.go`)

Performance tests for optimization tracking:

```bash
# Run all benchmarks
go test -bench=. -benchmem

# Run specific benchmark
go test -bench=BenchmarkHexToRGB -benchmem

# Run benchmarks with CPU profiling
go test -bench=. -cpuprofile=cpu.prof

# Run benchmarks with memory profiling
go test -bench=. -memprofile=mem.prof
```

Available benchmarks:

- **`BenchmarkHexToRGB`**: Color parsing performance
- **`BenchmarkCalculateBorderThickness`**: Border calculation
- **`BenchmarkCalculateFontSize`**: Font size calculation
- **`BenchmarkGenerateCaptionFromDate`**: Caption generation
- **`BenchmarkApplyTemplate`**: Template application
- **`BenchmarkValidateFontName`**: Font validation
- **`BenchmarkReadExif`**: EXIF metadata reading
- **`BenchmarkProcessImage`**: Full image processing
  - Solid border with caption
  - Instagram frame
  - No caption
  - PNG output
- **`BenchmarkProcessImageSizes`**: Different image dimensions
  - Small (640x480)
  - Medium (1920x1080)
  - Large (3840x2160)
  - Portrait (1080x1920)
- **`BenchmarkBatchProcessing`**: Batch operations
  - 5, 10, 20 files
- **`BenchmarkProcessingStats`**: Statistics operations
- **`BenchmarkConfigOperations`**: Config loading/merging

Example benchmark output:
```
BenchmarkProcessImage/solid_border_with_caption-8    50    23456789 ns/op    1234567 B/op    1234 allocs/op
```

## Test Data

Test fixtures are stored in the `testdata/` directory:

```
testdata/
└── sample_800x600.jpg    # 800x600 sample image for testing
```

Integration tests create temporary test images programmatically to avoid dependency on external files.

## Coverage Goals

Target coverage: **>80%**

Current coverage areas:
- ✅ Color parsing and validation
- ✅ Border calculations (absolute and percentage)
- ✅ Font size calculations
- ✅ Caption generation and templates
- ✅ Configuration loading and merging
- ✅ Image processing pipeline
- ✅ Batch processing with concurrency
- ✅ Error handling and edge cases

## Continuous Integration

Tests run automatically on every push and pull request via GitHub Actions:

```yaml
# .github/workflows/test.yml
- Run unit tests
- Run integration tests
- Generate coverage report
- Run with race detector
- Test on multiple Go versions
```

## Writing New Tests

### Unit Test Template

```go
func TestNewFeature(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    string
        wantErr bool
    }{
        {"valid case", "input", "output", false},
        {"error case", "bad", "", true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := newFeature(tt.input)
            if (err != nil) != tt.wantErr {
                t.Errorf("newFeature() error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            if !tt.wantErr && got != tt.want {
                t.Errorf("newFeature() = %v, want %v", got, tt.want)
            }
        })
    }
}
```

### Integration Test Template

```go
func TestNewWorkflow(t *testing.T) {
    if testing.Short() {
        t.Skip("Skipping integration test in short mode")
    }

    tmpDir := t.TempDir()
    // Setup test environment

    // Execute workflow

    // Verify results
    if _, err := os.Stat(expectedOutput); os.IsNotExist(err) {
        t.Errorf("Expected output not created: %s", expectedOutput)
    }
}
```

### Benchmark Template

```go
func BenchmarkNewOperation(b *testing.B) {
    // Setup

    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        _ = newOperation()
    }
}
```

## Best Practices

1. **Use Table-Driven Tests**: Group related test cases for better organization
2. **Test Edge Cases**: Empty strings, zero values, invalid input, boundary conditions
3. **Use Sub-Tests**: `t.Run()` for better test organization and targeted execution
4. **Clean Up Resources**: Use `t.TempDir()` for automatic cleanup
5. **Skip Long Tests**: Use `testing.Short()` for integration tests
6. **Test Errors**: Verify error conditions, not just happy paths
7. **Benchmark Realistically**: Use realistic input sizes and scenarios
8. **Document Test Purpose**: Use clear test names and comments

## Common Commands

```bash
# Quick test during development
go test -short -v

# Full test suite with coverage
go test -cover -race ./...

# Run specific test
go test -run TestHexToRGB/valid_black

# Run benchmarks with memory stats
go test -bench=. -benchmem -benchtime=10s

# Profile CPU usage
go test -bench=BenchmarkProcessImage -cpuprofile=cpu.prof
go tool pprof cpu.prof

# Check test coverage
go test -coverprofile=coverage.out && go tool cover -html=coverage.out
```

## Troubleshooting

### Tests Fail Due to Missing Fonts

Ensure required fonts are installed:
```bash
./install_fonts.sh
```

### Integration Tests Timeout

Increase timeout:
```bash
go test -timeout 5m ./...
```

### Race Detector Fails

Fix concurrent access issues. The race detector helps identify data races:
```bash
go test -race ./...
```

### Coverage Too Low

Identify untested code:
```bash
go test -coverprofile=coverage.out
go tool cover -html=coverage.out
```

Look for red (untested) sections in the HTML report.

## Resources

- [Go Testing Package](https://pkg.go.dev/testing)
- [Table-Driven Tests](https://github.com/golang/go/wiki/TableDrivenTests)
- [Go Test Coverage](https://go.dev/blog/cover)
- [Benchmarking in Go](https://pkg.go.dev/testing#hdr-Benchmarks)
