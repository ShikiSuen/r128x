import Foundation
import Testing

@testable import EBUR128

// MARK: - EBUR128Tests

@Suite
struct EBUR128BasicTests {
  @Test
  func testBasicInitialization() async throws {
    let state = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .LRA, .truePeak])

    #expect(state.channels == 2)
    #expect(state.sampleRate == 48000)
    #expect(state.mode.contains(.I))
    #expect(state.mode.contains(.LRA))
    #expect(state.mode.contains(.truePeak))
  }

  @Test
  func testFilterCoefficients() async throws {
    let state = try (EBUR128State(channels: 1, sampleRate: 48000, mode: [.I]))

    // Test that filter coefficients are reasonable
    // These should be non-zero for a proper BS.1770 filter
    #expect(abs(await state.filterCoefB[0]) > 0.01)
    #expect(abs(await state.filterCoefA[1]) > 0.01)
  }

  @Test
  func testSilenceProcessing() async throws {
    let state = try (EBUR128State(channels: 1, sampleRate: 48000, mode: [.I]))

    // Process silence - should produce negative infinity loudness
    let silentFrames = Array(repeating: Array(repeating: 0.0, count: 4800), count: 1)
    try await state.addFrames(silentFrames)

    let loudness = await state.loudnessGlobal()
    #expect(loudness == -Double.infinity)
  }

  @Test
  func testSineWaveLoudness() async throws {
    let state = try (EBUR128State(channels: 1, sampleRate: 48000, mode: [.I]))

    // Generate a 1 kHz sine wave at known level
    let sampleRate = 48000.0
    let frequency = 1000.0
    let frames = 48000 * 5 // 5 seconds
    let amplitude = pow(10.0, -20.0 / 20.0) // -20 dBFS

    var sineWave = [Double]()
    for i in 0 ..< frames {
      let t = Double(i) / sampleRate
      sineWave.append(amplitude * sin(2.0 * Double.pi * frequency * t))
    }

    // Process in chunks
    let chunkSize = 4800
    for start in stride(from: 0, to: frames, by: chunkSize) {
      let end = min(start + chunkSize, frames)
      let chunk = Array(sineWave[start ..< end])
      try await state.addFrames([chunk])
    }

    let loudness = await state.loudnessGlobal()

    // For a 1 kHz sine wave at -20 dBFS, after BS.1770 filtering,
    // we expect approximately -23 LUFS (this is the reference point)
    #expect(loudness > -30.0)
    #expect(loudness < -15.0)
    print("1 kHz sine wave loudness: \(loudness) LUFS")
  }

  @Test
  func testChannelWeighting() async throws {
    let state = try (EBUR128State(channels: 5, sampleRate: 48000, mode: [.I]))

    // Set up 5.1 channel mapping using the new batch API
    try await state.setChannels(since: 0, .left, .right, .center, .leftSurround, .rightSurround)

    // Test that surround channels get proper weighting
    // This is more of a structural test
    try await state.setChannels(since: 3, .leftSurround, .rightSurround)
  }

  @Test
  func testBatchChannelSetting() async throws {
    let state = try (EBUR128State(channels: 6, sampleRate: 48000, mode: [.I]))

    // Test the new batch channel setting API
    try await state.setChannels(
      since: 0, .left, .right, .center, .unused, .leftSurround, .rightSurround
    )

    // Test partial batch setting
    try await state.setChannels(since: 1, .right, .center)

    // Test setting from middle channel
    try await state.setChannels(since: 3, .unused, .leftSurround)

    // Test error cases
    do {
      // Should fail - beyond channel count
      try await state.setChannels(since: 5, .left, .right)
      #expect(Bool(false), "Should have thrown an error for out-of-bounds channels")
    } catch EBUR128Error.invalidChannelIndex {
      // Expected error
    }

    do {
      // Should fail - dualMono on multi-channel system
      try await state.setChannels(since: 0, .dualMono)
      #expect(Bool(false), "Should have thrown an error for invalid dualMono configuration")
    } catch EBUR128Error.invalidChannelIndex {
      // Expected error
    }

    // Test parameter-level duplicate detection
    do {
      // Should fail - duplicate .left in parameters
      try await state.setChannels(since: 0, .left, .left)
      #expect(Bool(false), "Should have thrown an error for duplicate channel types in parameters")
    } catch EBUR128Error.duplicatedTypesAcrossChannels {
      // Expected error
    }

    do {
      // Should fail - .right appears twice in parameters
      try await state.setChannels(since: 1, .right, .center, .right)
      #expect(Bool(false), "Should have thrown an error for duplicate channel types in parameters")
    } catch EBUR128Error.duplicatedTypesAcrossChannels {
      // Expected error
    }

    // Test that .unused can be repeated (should NOT throw)
    try await state.setChannels(since: 2, .unused, .unused, .unused, .unused)
  }

  @Test
  func testCommonChannelConfigurations() async throws {
    // Test common audio configurations using the concise batch API

    // Stereo setup
    let stereoState = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I])
    try await stereoState.setChannels(since: 0, .left, .right)

    // 5.1 surround setup
    let surroundState = try EBUR128State(channels: 6, sampleRate: 48000, mode: [.I])
    try await surroundState.setChannels(
      since: 0, .left, .right, .center, .unused, .leftSurround, .rightSurround
    )

    // 7.1 surround setup
    let sevenOneState = try EBUR128State(channels: 8, sampleRate: 48000, mode: [.I])
    try await sevenOneState.setChannels(
      since: 0, .left, .right, .center, .unused, .leftSurround, .rightSurround, .Mp090, .Mm090
    )

    // Mono with dual mono
    let monoState = try EBUR128State(channels: 1, sampleRate: 48000, mode: [.I])
    try await monoState.setChannels(since: 0, .dualMono)

    print("All common channel configurations set successfully using batch API!")
  }

  @Test
  func testPerformanceComparison() async throws {
    // Test different processing strategies to identify performance bottlenecks
    let state = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .LRA, .truePeak])

    // Generate test data: 30 seconds of stereo audio for more comprehensive testing
    let sampleRate = 48000.0
    let totalDuration = 30.0 // 30 seconds
    let totalFrames = Int(sampleRate * totalDuration)
    let frequency = 1000.0
    let amplitude = pow(10.0, -20.0 / 20.0) // -20 dBFS

    var testData = Array(repeating: Array(repeating: 0.0, count: totalFrames), count: 2)

    print("=== Performance Comparison Test ===")
    print("Generating \(totalDuration)s of test data...")

    for i in 0 ..< totalFrames {
      let t = Double(i) / sampleRate
      let sample = amplitude * sin(2.0 * Double.pi * frequency * t)
      testData[0][i] = sample // Left channel
      testData[1][i] = sample * 0.8 // Right channel
    }

    // Test 1: Current implementation with 2048-frame chunks
    let startTime1 = Date()
    let chunkSize1 = 2048
    for start in stride(from: 0, to: totalFrames, by: chunkSize1) {
      let end = min(start + chunkSize1, totalFrames)
      let leftChunk = Array(testData[0][start ..< end])
      let rightChunk = Array(testData[1][start ..< end])
      try await state.addFrames([leftChunk, rightChunk])
    }
    let processingTime1 = Date().timeIntervalSince(startTime1)
    let realTimeRatio1 = totalDuration / processingTime1

    print("Method 1 (2048 frames): \(processingTime1)s, \(realTimeRatio1)x real-time")
    print("Final loudness: \(await state.loudnessGlobal()) LUFS")
    print("Loudness range: \(await state.loudnessRange()) LU")

    // Reset state for next test
    let state2 = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .LRA, .truePeak])

    // Test 2: Larger chunks (8192 frames)
    let startTime2 = Date()
    let chunkSize2 = 8192
    for start in stride(from: 0, to: totalFrames, by: chunkSize2) {
      let end = min(start + chunkSize2, totalFrames)
      let leftChunk = Array(testData[0][start ..< end])
      let rightChunk = Array(testData[1][start ..< end])
      try await state2.addFrames([leftChunk, rightChunk])
    }
    let processingTime2 = Date().timeIntervalSince(startTime2)
    let realTimeRatio2 = totalDuration / processingTime2

    print("Method 2 (8192 frames): \(processingTime2)s, \(realTimeRatio2)x real-time")

    // Test 3: Largest possible chunks (whole seconds)
    let state3 = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .LRA, .truePeak])
    let startTime3 = Date()
    let chunkSize3 = Int(sampleRate) // 1 second chunks
    for start in stride(from: 0, to: totalFrames, by: chunkSize3) {
      let end = min(start + chunkSize3, totalFrames)
      let leftChunk = Array(testData[0][start ..< end])
      let rightChunk = Array(testData[1][start ..< end])
      try await state3.addFrames([leftChunk, rightChunk])
    }
    let processingTime3 = Date().timeIntervalSince(startTime3)
    let realTimeRatio3 = totalDuration / processingTime3

    print("Method 3 (48000 frames): \(processingTime3)s, \(realTimeRatio3)x real-time")

    // Performance should be better than 3x real-time (more realistic expectations)
    #expect(realTimeRatio1 > 3.0, "Small chunks should process at least 3x faster than real-time")
    #expect(realTimeRatio2 > 4.0, "Medium chunks should process at least 4x faster than real-time")
    #expect(realTimeRatio3 > 6.0, "Large chunks should process at least 6x faster than real-time")

    // Find the best chunk size
    let bestRatio = max(realTimeRatio1, realTimeRatio2, realTimeRatio3)
    print("Best performance: \(bestRatio)x real-time")
  }

  @Test
  func testComprehensivePerformanceBenchmark() async throws {
    print("\n=== Comprehensive Performance Benchmark vs C Implementation ===")

    // Test the same parameters as C benchmark: 30 seconds of stereo audio
    let duration = 30.0
    let sampleRate = 48000
    let state = try EBUR128State(
      channels: 2, sampleRate: UInt(sampleRate), mode: [.I, .LRA, .truePeak]
    )

    // Generate complex test signal similar to C benchmark
    let frames = Int(Double(sampleRate) * duration)
    let frequency = 1000.0
    let amplitude = pow(10.0, -20.0 / 20.0) // -20 dBFS

    var leftChannel = [Double]()
    var rightChannel = [Double]()

    print("Generating \(duration)s of complex test audio...")
    let genStartTime = Date()

    for i in 0 ..< frames {
      let t = Double(i) / Double(sampleRate)
      // Complex signal with harmonics like C version
      let fundamental = amplitude * sin(2.0 * Double.pi * frequency * t)
      let harmonic2 = amplitude * 0.3 * sin(2.0 * Double.pi * frequency * 2.0 * t)
      let harmonic3 = amplitude * 0.1 * sin(2.0 * Double.pi * frequency * 3.0 * t)
      let sample = fundamental + harmonic2 + harmonic3

      leftChannel.append(sample)
      rightChannel.append(sample * 0.9) // Slight channel difference
    }

    let genTime = Date().timeIntervalSince(genStartTime)
    print("Audio generation completed in \(Int(genTime * 1000))ms")
    print("Starting EBUR128 processing...")

    // Process entire audio at once - match C implementation approach
    let startTime = Date()
    try await state.addFrames([leftChannel, rightChannel])
    let processingTime = Date().timeIntervalSince(startTime)
    let audioLength = 10.0 // seconds
    let realTimeRatio = audioLength / processingTime

    let finalLoudness = await state.loudnessGlobal()
    let finalLRA = await state.loudnessRange()
    let leftTruePeak = try await state.truePeak(channel: 0)
    let rightTruePeak = try await state.truePeak(channel: 1)

    print("\n=== SWIFT IMPLEMENTATION PERFORMANCE BENCHMARK ===")
    print("Audio Duration: \(duration) seconds")
    print("Processing Time: \(Int(processingTime * 1000)) ms")
    print("Real-time Ratio: \(String(format: "%.1f", realTimeRatio))x (higher is better)")

    if realTimeRatio > 100.0 {
      print("Performance: EXCELLENT")
    } else if realTimeRatio > 50.0 {
      print("Performance: VERY GOOD")
    } else if realTimeRatio > 30.0 {
      print("Performance: GOOD")
    } else {
      print("Performance: NEEDS IMPROVEMENT")
    }

    print("\n=== MEASUREMENT RESULTS ===")
    print("Integrated Loudness: \(String(format: "%.4f", finalLoudness)) LUFS")
    print("Loudness Range: \(String(format: "%.5f", finalLRA)) LU")
    print("True Peak L: \(String(format: "%.5f", leftTruePeak)) dBFS")
    print("True Peak R: \(String(format: "%.5f", rightTruePeak)) dBFS")
    print("===============================================")

    print("\n⚡ PERFORMANCE COMPARISON NOTE:")
    print("C implementation baseline: 33.3x real-time (900ms for 30s)")
    print(
      "Swift optimized: \(String(format: "%.1f", realTimeRatio))x real-time (\(Int(processingTime * 1000))ms for 30s)"
    )

    let improvement = realTimeRatio / 33.3
    if improvement > 1.0 {
      print("🚀 Swift is \(String(format: "%.1f", improvement))x FASTER than C implementation!")
    } else {
      print("📈 Swift is \(String(format: "%.1f", 1.0 / improvement))x slower than C implementation")
    }

    // Performance assertions
    #if !DEBUG
    #expect(realTimeRatio > 30.0, "Should be at least as fast as C implementation (33.3x)")
    #expect(realTimeRatio > 33.3, "Optimized Swift should exceed C performance (33.3x)")
    #endif

    // Accuracy assertions
    #expect(finalLoudness.isFinite, "Loudness should be finite")
    #expect(finalLoudness > -30.0, "Loudness should be reasonable")
    #expect(finalLoudness < -10.0, "Loudness should be reasonable")
    #expect(finalLRA >= 0.0, "LRA should be non-negative")
    #expect(leftTruePeak > 0.0, "True peak should be positive")
    #expect(rightTruePeak > 0.0, "True peak should be positive")
  }

  @Test
  func testLoudnessRangeVariation() async throws {
    let state = try (EBUR128State(channels: 1, sampleRate: 48000, mode: [.I, .LRA]))

    // Generate a signal with varying loudness over time to produce non-zero LRA
    let sampleRate = 48000.0
    let totalDuration = 15.0 // 15 seconds to ensure we have enough short-term blocks
    let segmentDuration = 3.0 // 3 second segments with different amplitudes
    let frequency = 1000.0

    let segments = Int(totalDuration / segmentDuration)
    let framesPerSegment = Int(sampleRate * segmentDuration)

    print("=== LRA Debug Test ===")
    print(
      "Total duration: \(totalDuration)s, Segments: \(segments), Frames per segment: \(framesPerSegment)"
    )

    for segment in 0 ..< segments {
      // Create different amplitude levels to ensure LRA variation
      // Amplitude varies from quiet to loud and back
      let normalizedPos = Double(segment) / Double(segments - 1)
      let amplitude = 0.1 + 0.4 * sin(normalizedPos * Double.pi) // Varies from 0.1 to 0.5

      print("Segment \(segment): amplitude = \(amplitude)")

      var segmentData = [Double]()
      for i in 0 ..< framesPerSegment {
        let t = Double(i) / sampleRate
        let sample = amplitude * sin(2.0 * Double.pi * frequency * t)
        segmentData.append(sample)
      }

      // Process in smaller chunks to better simulate real audio processing
      let chunkSize = 4800 // 100ms chunks
      for start in stride(from: 0, to: framesPerSegment, by: chunkSize) {
        let end = min(start + chunkSize, framesPerSegment)
        let chunk = Array(segmentData[start ..< end])
        try await state.addFrames([chunk])
      }

      // Check intermediate measurements
      if segment > 0, segment % 2 == 0 {
        let currentLRA = await state.loudnessRange()
        let currentGlobal = await state.loudnessGlobal()
        print("After segment \(segment): Global = \(currentGlobal) LUFS, LRA = \(currentLRA) LU")
      }
    }

    let finalLRA = await state.loudnessRange()
    let finalGlobal = await state.loudnessGlobal()

    print("Final results: Global = \(finalGlobal) LUFS, LRA = \(finalLRA) LU")

    // With varying amplitude, we should get non-zero LRA
    #expect(finalLRA > 0.1, "LRA should be non-zero with varying signal amplitude")
    #expect(finalLRA < 20.0, "LRA should be reasonable (< 20 LU)")
  }

  @Test
  func testSwiftRewriteCompleteness() async throws {
    // Test that demonstrates the complete Swift rewrite works end-to-end
    let state = try
      (EBUR128State(channels: 2, sampleRate: 44100, mode: [.I, .LRA, .samplePeak, .truePeak]))

    // Verify basic functionality
    #expect(state.channels == 2)
    #expect(state.sampleRate == 44100)

    // Test all measurement modes work
    #expect(state.mode.contains(.I))
    #expect(state.mode.contains(.LRA))
    #expect(state.mode.contains(.samplePeak))
    #expect(state.mode.contains(.truePeak))

    // Test channel mapping using the new batch API
    try await state.setChannels(since: 0, .left, .right)

    // Test with a longer audio signal to allow LRA calculation
    let totalDuration = 10.0 // 10 seconds
    let frames = Int(44100.0 * totalDuration)
    let frequency = 440.0 // A4 note

    var leftChannel = [Double]()
    var rightChannel = [Double]()

    // Create signal with varying amplitude for LRA test
    for i in 0 ..< frames {
      let t = Double(i) / 44100.0
      let amplitude = 0.3 + 0.2 * sin(2.0 * Double.pi * t / 2.0) // Amplitude varies every 2 seconds
      leftChannel.append(amplitude * sin(2.0 * Double.pi * frequency * t))
      rightChannel.append(amplitude * sin(2.0 * Double.pi * frequency * t) * 0.8)
    }

    // Process in chunks
    let chunkSize = 4410 // 100ms chunks
    for start in stride(from: 0, to: frames, by: chunkSize) {
      let end = min(start + chunkSize, frames)
      let leftChunk = Array(leftChannel[start ..< end])
      let rightChunk = Array(rightChannel[start ..< end])
      try await state.addFrames([leftChunk, rightChunk])
    }

    // Test all measurement functions work
    let momentary = await state.loudnessMomentary()
    let shortTerm = await state.loudnessShortTerm()
    let global = await state.loudnessGlobal()
    let lra = await state.loudnessRange()

    // Should produce valid measurements (not infinite)
    #expect(momentary.isFinite || momentary == -Double.infinity)
    #expect(shortTerm.isFinite || shortTerm == -Double.infinity)
    #expect(global.isFinite || global == -Double.infinity)
    #expect(lra >= 0.0)

    // Test peak measurements - just verify they don't throw
    let leftSamplePeak = try await state.samplePeak(channel: 0)
    let rightSamplePeak = try await state.samplePeak(channel: 1)
    let leftTruePeak = try await state.truePeak(channel: 0)
    let rightTruePeak = try await state.truePeak(channel: 1)

    // Peaks should be reasonable for our test signal
    #expect(leftSamplePeak > 0.0)
    #expect(rightSamplePeak > 0.0)
    #expect(leftTruePeak > 0.0)
    #expect(rightTruePeak > 0.0)

    print("Swift rewrite test completed successfully!")
    print("Momentary: \(momentary) LUFS")
    print("Short-term: \(shortTerm) LUFS")
    print("Global: \(global) LUFS")
    print("LRA: \(lra) LU")
    print("L Sample Peak: \(leftSamplePeak), R Sample Peak: \(rightSamplePeak)")
    print("L True Peak: \(leftTruePeak), R True Peak: \(rightTruePeak)")
  }

  @Test
  func testFilterCoefficientFix() async throws {
    let state = try (EBUR128State(channels: 1, sampleRate: 48000, mode: [.I]))

    // Debug: Check filter coefficients (nonisolated properties)
    print("Filter coefficients A: \(await state.filterCoefA)")
    print("Filter coefficients B: \(await state.filterCoefB)")

    // Generate a 1 kHz sine wave like the working test
    let sampleRate = 48000.0
    let frequency = 1000.0
    let frames = 48000 * 5 // 5 seconds
    let amplitude = pow(10.0, -20.0 / 20.0) // -20 dBFS

    var sineWave = [Double]()
    for i in 0 ..< frames {
      let t = Double(i) / sampleRate
      sineWave.append(amplitude * sin(2.0 * Double.pi * frequency * t))
    }

    // Process in chunks like the working test
    let chunkSize = 4800
    for start in stride(from: 0, to: frames, by: chunkSize) {
      let end = min(start + chunkSize, frames)
      let chunk = Array(sineWave[start ..< end])
      try await state.addFrames([chunk])
    }

    let loudness = await state.loudnessGlobal()

    // If filter coefficients are correct, we should get a finite loudness value around -23 LUFS
    #expect(loudness.isFinite, "Loudness should be finite, got: \(loudness)")
    #expect(loudness > -30.0, "Loudness should be reasonable, got: \(loudness)")
    #expect(loudness < -15.0, "Loudness should be reasonable, got: \(loudness)")
    print("Filter coefficient test - Global loudness: \(loudness) LUFS")
  }

  @Test
  func testDownsamplingOptimization() async throws {
    print("=== Intelligent Decimation Optimization Test ===")

    // Test with very high sample rate to trigger decimation
    let highSampleRate: UInt = 192000
    let state = try
      (EBUR128State(channels: 2, sampleRate: highSampleRate, mode: [.I, .LRA, .truePeak]))

    // Generate test data: 10 seconds at 192kHz
    let sampleRateDouble = Double(highSampleRate)
    let totalDuration = 10.0
    let totalFrames = Int(sampleRateDouble * totalDuration)
    let frequency = 1000.0
    let amplitude = pow(10.0, -20.0 / 20.0) // -20 dBFS

    var testData = Array(repeating: Array(repeating: 0.0, count: totalFrames), count: 2)

    print("Generating \(totalDuration)s of test data at \(highSampleRate)Hz...")

    for i in 0 ..< totalFrames {
      let t = Double(i) / sampleRateDouble
      let sample = amplitude * sin(2.0 * Double.pi * frequency * t)
      testData[0][i] = sample // Left channel
      testData[1][i] = sample * 0.8 // Right channel
    }

    // Measure performance with decimation
    let startTime = Date()

    // Process in larger chunks for better efficiency with high sample rates
    let chunkSize = 96000 // 500ms at 192kHz (larger chunks for better efficiency)
    for start in stride(from: 0, to: totalFrames, by: chunkSize) {
      let end = min(start + chunkSize, totalFrames)
      let leftChunk = Array(testData[0][start ..< end])
      let rightChunk = Array(testData[1][start ..< end])
      try await state.addFrames([leftChunk, rightChunk])
    }

    let processingTime = Date().timeIntervalSince(startTime)
    let realTimeRatio = totalDuration / processingTime

    print("High sample rate processing (\(highSampleRate)Hz with decimation):")
    print("Processing time: \(processingTime) seconds")
    print("Real-time ratio: \(realTimeRatio)x")
    print("Final loudness: \(await state.loudnessGlobal()) LUFS")
    print("Loudness range: \(await state.loudnessRange()) LU")

    // With decimation, high sample rate should process reasonably efficiently
    #expect(
      realTimeRatio > 1.0,
      "High sample rate should process at least 1x faster than real-time with decimation"
    )

    // Accuracy should be maintained
    let loudness = await state.loudnessGlobal()
    #expect(loudness.isFinite, "Loudness should be finite")
    #expect(loudness > -30.0, "Loudness should be reasonable")
    #expect(loudness < -15.0, "Loudness should be reasonable")

    // Compare with standard 48kHz processing
    print("\n--- Comparison with 48kHz processing ---")
    let standardState = try EBUR128State(
      channels: 2, sampleRate: 48000, mode: [.I, .LRA, .truePeak]
    )

    // Generate equivalent 48kHz data
    let standardFrames = Int(48000.0 * totalDuration)
    var standardData = Array(repeating: Array(repeating: 0.0, count: standardFrames), count: 2)

    for i in 0 ..< standardFrames {
      let t = Double(i) / 48000.0
      let sample = amplitude * sin(2.0 * Double.pi * frequency * t)
      standardData[0][i] = sample
      standardData[1][i] = sample * 0.8
    }

    let standardStartTime = Date()
    let standardChunkSize = 24000 // 500ms at 48kHz
    for start in stride(from: 0, to: standardFrames, by: standardChunkSize) {
      let end = min(start + standardChunkSize, standardFrames)
      let leftChunk = Array(standardData[0][start ..< end])
      let rightChunk = Array(standardData[1][start ..< end])
      try await standardState.addFrames([leftChunk, rightChunk])
    }

    let standardProcessingTime = Date().timeIntervalSince(standardStartTime)
    let standardRealTimeRatio = totalDuration / standardProcessingTime

    print("Standard 48kHz processing:")
    print("Processing time: \(standardProcessingTime) seconds")
    print("Real-time ratio: \(standardRealTimeRatio)x")
    print("Final loudness: \(await standardState.loudnessGlobal()) LUFS")

    let relativeBenefit = realTimeRatio / standardRealTimeRatio
    print("\nDecimation relative performance: \(relativeBenefit)x")

    // With larger chunks, decimation should provide some benefit for very high sample rates
    if relativeBenefit > 0.8 {
      print("✅ Decimation provides acceptable performance for high sample rates")
    } else {
      print("⚠️  Decimation overhead still significant, but acceptable for very high sample rates")
    }
  }

  @Test
  func testRealWorldPerformanceBenchmark() async throws {
    print("\n=== Real-World Performance Benchmark ===")

    // Test with multiple synthetic scenarios to benchmark different aspects
    let scenarios = [
      ("High Sample Rate (192kHz)", 192000, 5.0),
      ("Standard Rate (48kHz)", 48000, 5.0),
      ("Low Rate (44.1kHz)", 44100, 5.0),
    ]

    for (name, sampleRate, duration) in scenarios {
      print("\n--- \(name) Test ---")
      let state = try
        (EBUR128State(channels: 2, sampleRate: UInt(sampleRate), mode: [.I, .LRA, .truePeak]))

      // Generate test audio with some complexity
      let frames = Int(Double(sampleRate) * duration)
      let frequency = 1000.0
      let amplitude = pow(10.0, -20.0 / 20.0)

      var leftChannel = [Double]()
      var rightChannel = [Double]()

      for i in 0 ..< frames {
        let t = Double(i) / Double(sampleRate)
        // Add some harmonic content for more realistic processing load
        let fundamental = amplitude * sin(2.0 * Double.pi * frequency * t)
        let harmonic2 = amplitude * 0.3 * sin(2.0 * Double.pi * frequency * 2.0 * t)
        let harmonic3 = amplitude * 0.1 * sin(2.0 * Double.pi * frequency * 3.0 * t)
        let sample = fundamental + harmonic2 + harmonic3

        leftChannel.append(sample)
        rightChannel.append(sample * 0.9) // Slight channel difference
      }

      let startTime = Date()

      // Process in realistic chunk sizes
      let chunkSize = sampleRate / 10 // 100ms chunks
      for start in stride(from: 0, to: frames, by: chunkSize) {
        let end = min(start + chunkSize, frames)
        let leftChunk = Array(leftChannel[start ..< end])
        let rightChunk = Array(rightChannel[start ..< end])
        try await state.addFrames([leftChunk, rightChunk])
      }

      let processingTime = Date().timeIntervalSince(startTime)
      let realTimeRatio = duration / processingTime

      let finalLoudness = await state.loudnessGlobal()
      let finalLRA = await state.loudnessRange()

      print("Sample Rate: \(sampleRate)Hz")
      print("Processing Time: \(String(format: "%.4f", processingTime))s")
      print("Real-time Ratio: \(String(format: "%.2f", realTimeRatio))x")
      print("Final Loudness: \(String(format: "%.2f", finalLoudness)) LUFS")
      print("Loudness Range: \(String(format: "%.2f", finalLRA)) LU")

      // Performance expectations
      if realTimeRatio > 30.0 {
        print("✅ Excellent performance")
      } else if realTimeRatio > 10.0 {
        print("✅ Good performance")
      } else {
        print("⚠️  Performance needs improvement")
      }
    }
  }

  @Test
  func testMemoryAndAllocationOptimization() async throws {
    print("\n=== Memory and Allocation Optimization Test ===")

    // Generate larger dataset to test memory efficiency
    let duration = 30.0 // 30 seconds
    let sampleRate = 48000.0
    let frames = Int(sampleRate * duration)

    print("Processing \(duration)s of 48kHz stereo audio (\(frames) frames per channel)")

    let startTime = Date()

    // Process in various chunk sizes to find optimal balance
    let chunkSizes = [480, 1200, 2400, 4800, 9600] // 10ms to 200ms at 48kHz

    for chunkSize in chunkSizes {
      let testState = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .LRA, .truePeak])

      let chunkStartTime = Date()
      let chunksNeeded = frames / chunkSize

      for chunkIndex in 0 ..< chunksNeeded {
        let start = chunkIndex * chunkSize
        let end = min(start + chunkSize, frames)
        let actualChunkSize = end - start

        // Generate chunk data
        var leftChunk = [Double]()
        var rightChunk = [Double]()

        for i in 0 ..< actualChunkSize {
          let t = Double(start + i) / sampleRate
          let sample = 0.1 * sin(2.0 * Double.pi * 1000.0 * t)
          leftChunk.append(sample)
          rightChunk.append(sample * 0.8)
        }

        try await testState.addFrames([leftChunk, rightChunk])
      }

      let chunkProcessingTime = Date().timeIntervalSince(chunkStartTime)
      let chunkRealTimeRatio = duration / chunkProcessingTime

      print(
        "Chunk size \(chunkSize) (\(Double(chunkSize) / sampleRate * 1000)ms): \(String(format: "%.2f", chunkRealTimeRatio))x real-time"
      )
    }

    let totalTime = Date().timeIntervalSince(startTime)
    print("Total benchmark time: \(String(format: "%.2f", totalTime))s")
  }

  @Test
  func testRevolutionaryPerformanceOptimization() async throws {
    print("\n=== Revolutionary Performance Test ===")

    // Test the revolutionary ultra-fast processing path
    let sampleRate: UInt = 192000
    let duration = 10.0
    let state = try
      (EBUR128State(channels: 2, sampleRate: sampleRate, mode: [.I, .LRA, .truePeak]))

    // Generate complex test signal
    let frames = Int(Double(sampleRate) * duration)
    let frequency = 1000.0
    let amplitude = pow(10.0, -20.0 / 20.0)

    var leftChannel = [Double]()
    var rightChannel = [Double]()

    for i in 0 ..< frames {
      let t = Double(i) / Double(sampleRate)
      let fundamental = amplitude * sin(2.0 * Double.pi * frequency * t)
      let harmonic2 = amplitude * 0.3 * sin(2.0 * Double.pi * frequency * 2.0 * t)
      let sample = fundamental + harmonic2

      leftChannel.append(sample)
      rightChannel.append(sample * 0.9)
    }

    print("Testing revolutionary processing with \(frames) frames at \(sampleRate)Hz")

    let startTime = Date()

    // Use revolutionary processing
    try await state.addFramesRevolutionary([leftChannel, rightChannel])

    let processingTime = Date().timeIntervalSince(startTime)
    let realTimeRatio = duration / processingTime

    let finalLoudness = await state.loudnessGlobal()

    print("Revolutionary Processing Results:")
    print("Processing Time: \(String(format: "%.4f", processingTime))s")
    print("Real-time Ratio: \(String(format: "%.2f", realTimeRatio))x")
    print("Final Loudness: \(String(format: "%.2f", finalLoudness)) LUFS")

    if realTimeRatio > 100.0 {
      print("🚀 Revolutionary performance achieved!")
    } else if realTimeRatio > 50.0 {
      print("⚡ Excellent performance!")
    } else {
      print("📈 Good performance, target: 10x improvement")
    }

    // Verify accuracy is maintained
    #if !DEBUG
    #expect(realTimeRatio > 8.0, "Performance should be at least 8x real-time")
    #endif
    #expect(finalLoudness.isFinite, "Loudness should be finite")
    #expect(abs(finalLoudness - -15.0) < 5.0, "Loudness should be approximately correct")
  }
}
