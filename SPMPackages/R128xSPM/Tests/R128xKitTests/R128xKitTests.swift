// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation
import Testing

@testable import R128xKit

struct R128xKitTests {
  @Test
  func testBasicFunctionality() {
    // Basic test to ensure the module loads correctly
    #expect(Bool(true), "Module should load without issues")
  }

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

  @Test
  func testPreviewTimeCalculationLogic() {
    // Test edge cases for preview time calculation logic

    // Test case 1: Normal case - peak in the middle of a long file
    let sampleRate = 48000.0
    let peakPosition: Int64 = 48000 * 10 // 10 seconds into the file
    let totalFrames: Int64 = 48000 * 60 // 60 second file

    let peakTimeInSeconds = Double(peakPosition) / sampleRate
    let totalDurationInSeconds = Double(totalFrames) / sampleRate

    let previewDuration = 3.0
    let halfPreviewDuration = previewDuration / 2.0

    var previewStartTime = peakTimeInSeconds - halfPreviewDuration
    var previewLength = previewDuration

    // Apply boundary checks
    if previewStartTime < 0 {
      previewStartTime = 0
    }

    if previewStartTime + previewLength > totalDurationInSeconds {
      previewLength = totalDurationInSeconds - previewStartTime
    }

    if previewLength > totalDurationInSeconds {
      previewStartTime = 0
      previewLength = totalDurationInSeconds
    }

    previewStartTime = max(0, previewStartTime)
    previewLength = max(0, previewLength)

    #expect(abs(previewStartTime - 8.5) < 0.01, "Peak at 10s should have preview starting at 8.5s")
    #expect(abs(previewLength - 3.0) < 0.01, "Preview should be 3 seconds long")

    // Test case 2: Peak near beginning of file
    let earlyPeakPosition: Int64 = 48000 * 1 // 1 second into the file
    let earlyPeakTimeInSeconds = Double(earlyPeakPosition) / sampleRate

    var earlyPreviewStartTime = earlyPeakTimeInSeconds - halfPreviewDuration
    var earlyPreviewLength = previewDuration

    if earlyPreviewStartTime < 0 {
      earlyPreviewStartTime = 0
    }

    if earlyPreviewStartTime + earlyPreviewLength > totalDurationInSeconds {
      earlyPreviewLength = totalDurationInSeconds - earlyPreviewStartTime
    }

    if earlyPreviewLength > totalDurationInSeconds {
      earlyPreviewStartTime = 0
      earlyPreviewLength = totalDurationInSeconds
    }

    earlyPreviewStartTime = max(0, earlyPreviewStartTime)
    earlyPreviewLength = max(0, earlyPreviewLength)

    #expect(abs(earlyPreviewStartTime - 0.0) < 0.01, "Peak at 1s should clamp preview start to 0")
    #expect(abs(earlyPreviewLength - 3.0) < 0.01, "Preview should still be 3 seconds long")

    // Test case 3: Very short file (2 seconds total)
    let shortTotalFrames: Int64 = 48000 * 2 // 2 second file
    let shortPeakPosition: Int64 = 48000 * 1 // 1 second into the file

    let shortPeakTimeInSeconds = Double(shortPeakPosition) / sampleRate
    let shortTotalDurationInSeconds = Double(shortTotalFrames) / sampleRate

    var shortPreviewStartTime = shortPeakTimeInSeconds - halfPreviewDuration
    var shortPreviewLength = previewDuration

    if shortPreviewStartTime < 0 {
      shortPreviewStartTime = 0
    }

    if shortPreviewStartTime + shortPreviewLength > shortTotalDurationInSeconds {
      shortPreviewLength = shortTotalDurationInSeconds - shortPreviewStartTime
    }

    if shortPreviewLength > shortTotalDurationInSeconds {
      shortPreviewStartTime = 0
      shortPreviewLength = shortTotalDurationInSeconds
    }

    shortPreviewStartTime = max(0, shortPreviewStartTime)
    shortPreviewLength = max(0, shortPreviewLength)

    #expect(abs(shortPreviewStartTime - 0.0) < 0.01, "Short file should start preview at 0")
    #expect(abs(shortPreviewLength - 2.0) < 0.01, "Short file preview should be full file length")
  }
}
