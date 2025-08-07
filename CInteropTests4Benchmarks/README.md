# EBUR128 C Implementation Tests and Benchmarks

This directory contains comprehensive tests and benchmarks for the C implementation of the EBUR128 library using Google Test framework.

## Overview

These tests validate the C implementation of EBUR128 (EBU R128 loudness measurement standard) by:
- Testing basic functionality with known test signals  
- Validating loudness calculations (integrated, momentary, short-term)
- Testing loudness range (LRA) calculations
- Testing peak measurements (sample and true peak)
- Performance benchmarking
- Error condition handling
- Multi-instance processing

## Building and Running Tests

### Prerequisites
- CMake 3.6 or later
- C++17 compatible compiler (GCC, Clang, etc.)
- Make or Ninja build system

### Build Instructions

1. Create build directory and configure:
```bash
mkdir build
cd build
cmake .. -DENABLE_TEST=ON
```

2. Build the project:
```bash
make -j$(nproc)
```

3. Run tests (multiple options):
```bash
# Run tests directly
./ebur128_test

# Run via CTest
ctest --verbose

# Run via make target  
make runebur128Test
```

## Test Coverage

The test suite includes 13 comprehensive test cases:

### Core Functionality Tests
- **BasicInitializationAndDestruction**: Library initialization and cleanup
- **VersionInformation**: Version number retrieval
- **ChannelMapping**: Channel configuration and mapping
- **SilenceProcessing**: Handling of silence (should produce -∞ loudness)

### Signal Processing Tests  
- **SineWaveLoudness**: Known sine wave loudness validation
- **ShortTermLoudness**: Short-term loudness measurement (3s window)
- **LoudnessRange**: LRA calculation with varying signal levels
- **DifferentSampleRates**: Multi-sample-rate compatibility (44.1kHz - 192kHz)

### Peak Measurement Tests
- **SamplePeak**: Maximum sample peak detection
- **TruePeak**: True peak measurement with oversampling

### Advanced Tests
- **ErrorConditions**: Error handling and invalid parameter testing
- **MultipleInstances**: Multi-instance processing and combined measurements
- **PerformanceBenchmark**: Processing speed measurement and validation

## Performance Results

The performance benchmark processes 10 seconds of stereo audio and measures:
- Processing time (should be well under 1 second for real-time performance)
- Integrated loudness accuracy  
- Loudness range calculation
- True peak detection

Expected results for test signals:
- 1kHz sine wave at -20 dBFS: ~-20 LUFS integrated loudness
- Processing speed: >30x real-time performance
- True peak accuracy within 0.1 dB

## Expected Test Signal Results

The tests validate against known expected values:

| Test Signal | Expected Integrated Loudness | Expected LRA | Expected True Peak |
|-------------|------------------------------|--------------|-------------------|
| Silence     | -∞ LUFS                     | N/A          | 0.0               |
| 1kHz @ -20dBFS | ~-20 LUFS                | ~0 LU        | ~-20 dBTP         |
| Varying levels | Finite value              | >0 LU        | Peak of loudest   |

## Usage for Swift Implementation Validation

These C implementation tests can serve as reference values for validating the Swift EBUR128 implementation:

1. Process identical test signals in both implementations
2. Compare integrated loudness, LRA, and peak values
3. Ensure results match within acceptable tolerance (typically ±0.1 LUFS)
4. Use performance benchmark as baseline for Swift optimization efforts

## Files

- `ebur128.h` - EBUR128 C library header
- `ebur128.c` - EBUR128 C library implementation  
- `ebur128_test.cpp` - Comprehensive GTest test suite
- `CMakeLists.txt` - CMake build configuration
- `COPYING` - Library license information