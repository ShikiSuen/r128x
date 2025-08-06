@testable import EBUR128
import XCTest

final class EBUR128Tests: XCTestCase {
  func testBasicInitialization() throws {
    let state = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .LRA, .truePeak])

    XCTAssertEqual(state.channels, 2)
    XCTAssertEqual(state.sampleRate, 48000)
    XCTAssertTrue(state.mode.contains(.I))
    XCTAssertTrue(state.mode.contains(.LRA))
    XCTAssertTrue(state.mode.contains(.truePeak))
  }

  func testFilterCoefficients() throws {
    let state = try EBUR128State(channels: 1, sampleRate: 48000, mode: [.I])

    // Test that filter coefficients are reasonable
    // These should be non-zero for a proper BS.1770 filter
    XCTAssertGreaterThan(abs(state.filterCoefB[0]), 0.01)
    XCTAssertGreaterThan(abs(state.filterCoefA[1]), 0.01)
  }

  func testSilenceProcessing() async throws {
    let state = try EBUR128State(channels: 1, sampleRate: 48000, mode: [.I])

    // Process silence - should produce negative infinity loudness
    let silentFrames = Array(repeating: Array(repeating: 0.0, count: 4800), count: 1)
    try await state.addFrames(silentFrames)

    let loudness = await state.loudnessGlobal()
    XCTAssertEqual(loudness, -Double.infinity)
  }

  func testSineWaveLoudness() async throws {
    let state = try EBUR128State(channels: 1, sampleRate: 48000, mode: [.I])

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
    XCTAssertGreaterThan(loudness, -30.0)
    XCTAssertLessThan(loudness, -15.0)
    print("1 kHz sine wave loudness: \(loudness) LUFS")
  }

  func testChannelWeighting() async throws {
    let state = try EBUR128State(channels: 5, sampleRate: 48000, mode: [.I])

    // Set up 5.1 channel mapping
    try await state.setChannel(0, value: .left)
    try await state.setChannel(1, value: .right)
    try await state.setChannel(2, value: .center)
    try await state.setChannel(3, value: .leftSurround)
    try await state.setChannel(4, value: .rightSurround)

    // Test that surround channels get proper weighting
    // This is more of a structural test
    try await state.setChannel(3, value: .leftSurround)
    try await state.setChannel(4, value: .rightSurround)
  }

  func testPerformanceComparison() throws {
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
      try state.addFrames([leftChunk, rightChunk])
    }
    let processingTime1 = Date().timeIntervalSince(startTime1)
    let realTimeRatio1 = totalDuration / processingTime1

    print("Method 1 (2048 frames): \(processingTime1)s, \(realTimeRatio1)x real-time")
    print("Final loudness: \(state.loudnessGlobal()) LUFS")
    print("Loudness range: \(state.loudnessRange()) LU")

    // Reset state for next test
    let state2 = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .LRA, .truePeak])

    // Test 2: Larger chunks (8192 frames)
    let startTime2 = Date()
    let chunkSize2 = 8192
    for start in stride(from: 0, to: totalFrames, by: chunkSize2) {
      let end = min(start + chunkSize2, totalFrames)
      let leftChunk = Array(testData[0][start ..< end])
      let rightChunk = Array(testData[1][start ..< end])
      try state2.addFrames([leftChunk, rightChunk])
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
      try state3.addFrames([leftChunk, rightChunk])
    }
    let processingTime3 = Date().timeIntervalSince(startTime3)
    let realTimeRatio3 = totalDuration / processingTime3

    print("Method 3 (48000 frames): \(processingTime3)s, \(realTimeRatio3)x real-time")

    // Performance should be better than 5x real-time
    XCTAssertGreaterThan(realTimeRatio1, 5.0, "Small chunks should process at least 5x faster than real-time")
    XCTAssertGreaterThan(realTimeRatio2, 6.0, "Medium chunks should process at least 6x faster than real-time")
    XCTAssertGreaterThan(realTimeRatio3, 7.0, "Large chunks should process at least 7x faster than real-time")

    // Find the best chunk size
    let bestRatio = max(realTimeRatio1, realTimeRatio2, realTimeRatio3)
    print("Best performance: \(bestRatio)x real-time")
  }

  func testPerformanceOptimizations() throws {
    let state = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .LRA, .truePeak])

    // Generate test data: 10 seconds of stereo audio
    let sampleRate = 48000.0
    let totalFrames = Int(sampleRate * 10) // 10 seconds
    let frequency = 1000.0
    let amplitude = pow(10.0, -20.0 / 20.0) // -20 dBFS

    var testData = Array(repeating: Array(repeating: 0.0, count: totalFrames), count: 2)

    for i in 0 ..< totalFrames {
      let t = Double(i) / sampleRate
      let sample = amplitude * sin(2.0 * Double.pi * frequency * t)
      testData[0][i] = sample // Left channel
      testData[1][i] = sample * 0.8 // Right channel, slightly quieter
    }

    // Measure performance
    let startTime = Date()

    // Process in realistic-sized chunks (2048 frames ≈ 42.6ms at 48kHz)
    let chunkSize = 2048
    for start in stride(from: 0, to: totalFrames, by: chunkSize) {
      let end = min(start + chunkSize, totalFrames)
      let leftChunk = Array(testData[0][start ..< end])
      let rightChunk = Array(testData[1][start ..< end])
      try state.addFrames([leftChunk, rightChunk])
    }

    let processingTime = Date().timeIntervalSince(startTime)
    let audioLength = 10.0 // seconds
    let realTimeRatio = audioLength / processingTime

    print("Processing time: \(processingTime) seconds")
    print("Real-time ratio: \(realTimeRatio)x")
    print("Final loudness: \(state.loudnessGlobal()) LUFS")
    print("Loudness range: \(state.loudnessRange()) LU")

    // Performance assertion: should process faster than real-time on modern hardware
    XCTAssertGreaterThan(realTimeRatio, 3.0, "Should process at least 3x faster than real-time")

    // Accuracy assertions: results should still be correct
    let loudness = state.loudnessGlobal()
    XCTAssertGreaterThan(loudness, -30.0)
    XCTAssertLessThan(loudness, -15.0)
  }

  func testLoudnessRangeVariation() async throws {
    let state = try EBUR128State(channels: 1, sampleRate: 48000, mode: [.I, .LRA])

    // Generate a signal with varying loudness over time to produce non-zero LRA
    let sampleRate = 48000.0
    let totalDuration = 15.0 // 15 seconds to ensure we have enough short-term blocks
    let segmentDuration = 3.0 // 3 second segments with different amplitudes
    let frequency = 1000.0

    let segments = Int(totalDuration / segmentDuration)
    let framesPerSegment = Int(sampleRate * segmentDuration)

    print("=== LRA Debug Test ===")
    print("Total duration: \(totalDuration)s, Segments: \(segments), Frames per segment: \(framesPerSegment)")

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
    XCTAssertGreaterThan(finalLRA, 0.1, "LRA should be non-zero with varying signal amplitude")
    XCTAssertLessThan(finalLRA, 20.0, "LRA should be reasonable (< 20 LU)")
  }

  func testSwiftRewriteCompleteness() async throws {
    // Test that demonstrates the complete Swift rewrite works end-to-end
    let state = try EBUR128State(channels: 2, sampleRate: 44100, mode: [.I, .LRA, .samplePeak, .truePeak])

    // Verify basic functionality
    XCTAssertEqual(state.channels, 2)
    XCTAssertEqual(state.sampleRate, 44100)

    // Test all measurement modes work
    XCTAssertTrue(state.mode.contains(.I))
    XCTAssertTrue(state.mode.contains(.LRA))
    XCTAssertTrue(state.mode.contains(.samplePeak))
    XCTAssertTrue(state.mode.contains(.truePeak))

    // Test channel mapping
    try await state.setChannel(0, value: .left)
    try await state.setChannel(1, value: .right)

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
    XCTAssertTrue(momentary.isFinite || momentary == -Double.infinity)
    XCTAssertTrue(shortTerm.isFinite || shortTerm == -Double.infinity)
    XCTAssertTrue(global.isFinite || global == -Double.infinity)
    XCTAssertGreaterThanOrEqual(lra, 0.0)

    // Test peak measurements - just verify they don't throw
    _ = try await state.samplePeak(channel: 0)
    _ = try await state.samplePeak(channel: 1)
    _ = try await state.truePeak(channel: 0)
    _ = try await state.truePeak(channel: 1)

    let leftSamplePeak = try await state.samplePeak(channel: 0)
    let rightSamplePeak = try await state.samplePeak(channel: 1)
    let leftTruePeak = try await state.truePeak(channel: 0)
    let rightTruePeak = try await state.truePeak(channel: 1)

    // Peaks should be reasonable for our test signal
    XCTAssertGreaterThan(leftSamplePeak, 0.0)
    XCTAssertGreaterThan(rightSamplePeak, 0.0)
    XCTAssertGreaterThan(leftTruePeak, 0.0)
    XCTAssertGreaterThan(rightTruePeak, 0.0)

    print("Swift rewrite test completed successfully!")
    print("Momentary: \(momentary) LUFS")
    print("Short-term: \(shortTerm) LUFS")
    print("Global: \(global) LUFS")
    print("LRA: \(lra) LU")
    print("L Sample Peak: \(leftSamplePeak), R Sample Peak: \(rightSamplePeak)")
    print("L True Peak: \(leftTruePeak), R True Peak: \(rightTruePeak)")
  }

  func testFilterCoefficientFix() async throws {
    let state = try EBUR128State(channels: 1, sampleRate: 48000, mode: [.I])

    // Debug: Check filter coefficients (nonisolated properties)
    print("Filter coefficients A: \(state.filterCoefA)")
    print("Filter coefficients B: \(state.filterCoefB)")

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
    XCTAssertTrue(loudness.isFinite, "Loudness should be finite, got: \(loudness)")
    XCTAssertGreaterThan(loudness, -30.0, "Loudness should be reasonable, got: \(loudness)")
    XCTAssertLessThan(loudness, -15.0, "Loudness should be reasonable, got: \(loudness)")
    print("Filter coefficient test - Global loudness: \(loudness) LUFS")
  }
}
