import Foundation
import Testing

@testable import EBUR128

@MainActor
@Suite("EBUR128Tests - 2", .serialized)
struct EBUR128TestsBravo {
  @Test
  func testDefensiveInitialization() async throws {
    // Test normal case
    let state = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .LRA])
    #expect(state.channels == 2)
    #expect(state.sampleRate == 48000)

    // Test defensive patterns: invalid channels
    #expect(throws: EBUR128Error.noMem) {
      try EBUR128State(channels: 0, sampleRate: 48000, mode: [.I])
    }

    #expect(throws: EBUR128Error.noMem) {
      try EBUR128State(channels: 100, sampleRate: 48000, mode: [.I])
    }

    // Test defensive patterns: invalid sample rates
    #expect(throws: EBUR128Error.noMem) {
      try EBUR128State(channels: 2, sampleRate: 10, mode: [.I])
    }

    #expect(throws: EBUR128Error.noMem) {
      try EBUR128State(channels: 2, sampleRate: 3_000_000, mode: [.I])
    }
  }

  @Test
  func testChannelMappingDefensive() async throws {
    let state = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I])

    // Test valid channel setting
    try await state.setChannel(0, value: .left)
    try await state.setChannel(1, value: .right)

    // Test defensive pattern: invalid channel index
    await #expect(throws: EBUR128Error.invalidChannelIndex) {
      try await state.setChannel(5, value: .left)
    }

    // Test defensive pattern: duplicate channel types
    await #expect(throws: EBUR128Error.duplicatedTypesAcrossChannels) {
      try await state.setChannels(since: 0, .left, .left)
    }

    // Test defensive pattern: dual mono validation
    let monoState = try EBUR128State(channels: 1, sampleRate: 48000, mode: [.I])
    try await monoState.setChannel(0, value: .dualMono) // Should work

    await #expect(throws: EBUR128Error.invalidChannelIndex) {
      try await state.setChannel(0, value: .dualMono) // Should fail for stereo
    }
  }

  @Test
  func testAudioFrameOverflowProtection() async throws {
    let state = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .samplePeak])

    // Test normal processing
    let frames = 1000
    let audioData = [[Double]](repeating: Array(repeating: 0.1, count: frames), count: 2)
    try await state.addFrames(audioData)

    // Test empty frames (defensive pattern)
    let emptyData = [[Double]](repeating: [], count: 2)
    try await state.addFrames(emptyData) // Should not crash

    // Test mismatched channel count (defensive pattern)
    let wrongChannelData = [[Double]](repeating: Array(repeating: 0.1, count: frames), count: 3)
    await #expect(throws: EBUR128Error.invalidChannelIndex) {
      try await state.addFrames(wrongChannelData)
    }
  }

  @Test
  func testPeakCalculationBoundChecking() async throws {
    let state = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.samplePeak, .truePeak])

    // Test with extreme values to ensure no overflow
    let extremeData = [
      [1.0, -1.0, 0.5, -0.5],
      [0.9, -0.9, 0.3, -0.3],
    ]
    try await state.addFrames(extremeData)

    let samplePeak = try await state.samplePeak(channel: 0)
    let truePeak = try await state.truePeak(channel: 0)

    #expect(samplePeak >= 0.0)
    #expect(truePeak >= 0.0)
    #expect(samplePeak <= 1.0)

    // Test invalid channel access (defensive pattern)
    await #expect(throws: EBUR128Error.invalidChannelIndex) {
      try await state.samplePeak(channel: 5)
    }
  }

  @Test
  func testMemoryAllocationSafety() async throws {
    // Test very large buffer allocation that could overflow
    let state = try EBUR128State(channels: 8, sampleRate: 192000, mode: [.I, .LRA, .truePeak])

    // Should not crash with large allocations
    #expect(state.channels == 8)
    #expect(state.sampleRate == 192000)

    // Test large frame processing
    let largeFrameCount = 19200 // 0.1 seconds at 192kHz
    let largeData = [[Double]](
      repeating: Array(repeating: 0.1, count: largeFrameCount),
      count: 8
    )
    try await state.addFrames(largeData)
  }

  @Test
  func testFilterCoefficientSafety() async throws {
    let state = try EBUR128State(channels: 1, sampleRate: 48000, mode: [.I])

    // Test that filter coefficients are reasonable
    let coeffB = await state.filterCoefB
    let coeffA = await state.filterCoefA

    #expect(coeffB.count == 5)
    #expect(coeffA.count == 5)

    // Coefficients should be finite and reasonable
    for coef in coeffB {
      #expect(coef.isFinite)
      #expect(abs(coef) < 10.0) // Reasonable filter coefficient range
    }

    for coef in coeffA {
      #expect(coef.isFinite)
      #expect(abs(coef) < 10.0) // Reasonable filter coefficient range
    }
  }

  @Test
  func testConcurrentAccessSafety() async throws {
    let state = try EBUR128State(channels: 2, sampleRate: 48000, mode: [.I, .LRA])

    // Test concurrent operations don't crash
    await withTaskGroup(of: Void.self) { group in
      for i in 0 ..< 10 {
        group.addTask {
          let data = [[Double]](
            repeating: Array(repeating: Double(i) * 0.01, count: 480),
            count: 2
          )
          try? await state.addFrames(data)
        }
      }
    }

    // Should be able to get measurements after concurrent operations
    let loudness = await state.loudnessGlobal()
    #expect(loudness.isFinite || loudness == -Double.infinity)
  }
}
