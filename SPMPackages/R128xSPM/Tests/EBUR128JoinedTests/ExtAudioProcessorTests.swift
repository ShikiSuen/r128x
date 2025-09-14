import Foundation
import Testing

@testable import EBUR128
@testable import ExtAudioProcessor

@Suite
struct ExtAudioProcessorTests {
  @Test
  func testExtAudioProcessorInitialization() {
    _ = ExtAudioProcessor()
    // Just verify the processor was created successfully (no throw)
    #expect(Bool(true), "ExtAudioProcessor should initialize successfully")
  }

  @Test
  func testMeasuredResultWithPreviewTimes() {
    // Test MeasuredResult initialization with preview times
    let result = MeasuredResult(
      integratedLoudness: -23.0,
      loudnessRange: 10.5,
      maxTruePeak: -1.2,
      previewStartAtTime: 15.5,
      previewLength: 3.0
    )

    #expect(abs(result.integratedLoudness - -23.0) < 0.01)
    #expect(abs(result.loudnessRange - 10.5) < 0.01)
    #expect(abs(result.maxTruePeak - -1.2) < 0.01)
    #expect(abs(result.previewStartAtTime - 15.5) < 0.01)
    #expect(abs(result.previewLength - 3.0) < 0.01)
  }
}
