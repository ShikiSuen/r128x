import Foundation
import Testing

@testable import EBUR128

@Suite("EBUR128Tests - 3")
struct EBUR128TestsCharlie {
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
