import Foundation
import Testing

@testable import EBUR128
@testable import ExtAudioProcessor

// MARK: - ExtAudioProcessorTests

/// Basic tests for core types in ExtAudioProcessor and EBUR128

@Suite
struct ExtAudioProcessorTests {
  @Test
  func testExtAudioProcessorInitialization() {
    _ = ExtAudioProcessor()
    // Just verify the processor was created successfully (no throw)
    #expect(Bool(true), "ExtAudioProcessor should initialize successfully")
  }
}

// MARK: - MeasuredResultTests

/// Test suite for MeasuredResult data structure functionality
@Suite("MeasuredResult Tests")
struct MeasuredResultTests {
  @Test("Test MeasuredResult initialization and properties")
  func testMeasuredResultInitialization() {
    let result = MeasuredResult(
      integratedLoudness: -23.0,
      loudnessRange: 5.5,
      maxTruePeak: -1.0,
      previewStartAtTime: 60.0,
      previewLength: 3.0
    )

    #expect(result.integratedLoudness == -23.0)
    #expect(result.loudnessRange == 5.5)
    #expect(result.maxTruePeak == -1.0)
    #expect(result.previewStartAtTime == 60.0)
    #expect(result.previewLength == 3.0)
  }

  @Test("Test MeasuredResult with default values")
  func testMeasuredResultWithDefaults() {
    let result = MeasuredResult(
      integratedLoudness: -23.0,
      loudnessRange: 5.5,
      maxTruePeak: -1.0
    )

    #expect(result.integratedLoudness == -23.0)
    #expect(result.loudnessRange == 5.5)
    #expect(result.maxTruePeak == -1.0)
    #expect(result.previewStartAtTime == 0.0)
    #expect(result.previewLength == 0.0)
  }

  @Test("Test MeasuredResult with preview times")
  func testMeasuredResultWithPreviewTimes() {
    // Test MeasuredResult initialization with preview times
    let result = MeasuredResult(
      integratedLoudness: -23.0,
      loudnessRange: 10.5,
      maxTruePeak: -1.2,
      previewStartAtTime: 15.5,
      previewLength: 3.0
    )

    #expect(result.integratedLoudness == -23.0)
    #expect(result.loudnessRange == 10.5)
    #expect(result.maxTruePeak == -1.2)
    #expect(result.previewStartAtTime == 15.5)
    #expect(result.previewLength == 3.0)
  }

  @Test("Test MeasuredResult Codable conformance")
  func testMeasuredResultCodable() throws {
    let original = MeasuredResult(
      integratedLoudness: -23.0,
      loudnessRange: 5.5,
      maxTruePeak: -1.0,
      previewStartAtTime: 60.0,
      previewLength: 3.0
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(MeasuredResult.self, from: data)

    #expect(decoded.integratedLoudness == original.integratedLoudness)
    #expect(decoded.loudnessRange == original.loudnessRange)
    #expect(decoded.maxTruePeak == original.maxTruePeak)
    #expect(decoded.previewStartAtTime == original.previewStartAtTime)
    #expect(decoded.previewLength == original.previewLength)
  }
}

// MARK: - ProgressUpdateTests

/// Test suite for ProgressUpdate data structure functionality
@Suite("ProgressUpdate Tests")
struct ProgressUpdateTests {
  @Test("Test ProgressUpdate initialization and properties")
  func testProgressUpdateInitialization() {
    let update = ProgressUpdate(
      fileId: "test-file-id",
      percentage: 75.5,
      framesProcessed: 1000,
      totalFrames: 2000,
      currentLoudness: -23.0,
      estimatedTimeRemaining: 30.5
    )

    #expect(update.fileId == "test-file-id")
    #expect(update.percentage == 75.5)
    #expect(update.framesProcessed == 1000)
    #expect(update.totalFrames == 2000)
    #expect(update.currentLoudness == -23.0)
    #expect(update.estimatedTimeRemaining == 30.5)
  }

  @Test("Test ProgressUpdate with nil optional values")
  func testProgressUpdateWithNilValues() {
    let update = ProgressUpdate(
      fileId: "test-file-id",
      percentage: 50.0,
      framesProcessed: 500,
      totalFrames: 1000
    )

    #expect(update.fileId == "test-file-id")
    #expect(update.percentage == 50.0)
    #expect(update.framesProcessed == 500)
    #expect(update.totalFrames == 1000)
    #expect(update.currentLoudness == nil)
    #expect(update.estimatedTimeRemaining == nil)
  }

  @Test("Test ProgressUpdate Equatable conformance")
  func testProgressUpdateEquatable() {
    let update1 = ProgressUpdate(
      fileId: "test-file-id",
      percentage: 75.5,
      framesProcessed: 1000,
      totalFrames: 2000,
      currentLoudness: -23.0,
      estimatedTimeRemaining: 30.5
    )

    let update2 = ProgressUpdate(
      fileId: "test-file-id",
      percentage: 75.5,
      framesProcessed: 1000,
      totalFrames: 2000,
      currentLoudness: -23.0,
      estimatedTimeRemaining: 30.5
    )

    let update3 = ProgressUpdate(
      fileId: "different-file-id",
      percentage: 75.5,
      framesProcessed: 1000,
      totalFrames: 2000,
      currentLoudness: -23.0,
      estimatedTimeRemaining: 30.5
    )

    #expect(update1 == update2)
    #expect(update1 != update3)
  }
}

// MARK: - TaskEntryTests

@Suite
struct TaskEntryTests {
  @Test("Test TaskEntry properties and display methods")
  func testTaskEntryProperties() {
    let url = URL(fileURLWithPath: "/test/path/audio.wav")
    var entry = TaskEntry(url: url)

    // Test basic properties
    #expect(entry.fileName == "audio.wav")
    #expect(entry.fileNamePath.hasSuffix("/test/path/audio.wav"))
    // folderPath may have trailing slash in some macOS versions
    #expect(entry.folderPath.hasPrefix("/test/path"))
    #expect(entry.status == .processing)
    #expect(entry.done == false)
    #expect(entry.isResultInvalid == false) // processing state

    // Test success state
    entry.status = .succeeded
    entry.programLoudness = -23.0
    entry.loudnessRange = 5.5
    entry.dBTP = -1.0
    entry.previewStartAtTime = 60.5
    entry.previewLength = 3.0

    #expect(entry.done == true)
    #expect(entry.isResultInvalid == false)
    #expect(entry.statusDisplayed == "✔︎")
    #expect(entry.programLoudnessDisplayed == "-23.0")
    #expect(entry.loudnessRangeDisplayed == "5.50")
    #expect(entry.dBTPDisplayed == "-1.00")
    #expect(entry.previewStartAtTimeDisplayed.contains("1:00.500"))
    #expect(entry.previewLengthDisplayed == "3.000s")
    #expect(entry.isDBTPPlaybackable == true)

    // Test failed state
    entry.status = .failed
    entry.programLoudness = nil
    entry.loudnessRange = nil
    entry.dBTP = nil
    entry.previewStartAtTime = nil
    entry.previewLength = nil

    #expect(entry.done == true)
    #expect(entry.isResultInvalid == true)
    #expect(entry.statusDisplayed == "✖︎")
    #expect(entry.programLoudnessDisplayed == "N/A")
    #expect(entry.loudnessRangeDisplayed == "N/A")
    #expect(entry.dBTPDisplayed == "N/A")
    #expect(entry.previewStartAtTimeDisplayed == "N/A")
    #expect(entry.previewLengthDisplayed == "N/A")
    #expect(entry.isDBTPPlaybackable == false)

    // Test progress display
    entry.status = .processing
    entry.progressPercentage = 75.5
    entry.estimatedTimeRemaining = 30.5

    #expect(entry.progressDisplayed == "75.5%")
    #expect(entry.timeRemainingDisplayed == "30s")
    #expect(entry.guardedProgressValue == 0.755)
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

    var previewStartTime = Swift.max(0, peakTimeInSeconds - halfPreviewDuration)
    var previewLength = previewDuration
    previewLength = Swift.max(
      0, Swift.min(previewDuration, totalDurationInSeconds - previewStartTime)
    )

    if previewLength > totalDurationInSeconds {
      previewStartTime = 0
      previewLength = totalDurationInSeconds
    }

    #expect(abs(previewStartTime - 8.5) < 0.01, "Peak at 10s should have preview starting at 8.5s")
    #expect(abs(previewLength - 3.0) < 0.01, "Preview should be 3 seconds long")

    // Test case 2: Peak near beginning of file
    let earlyPeakPosition: Int64 = 48000 * 1 // 1 second into the file
    let earlyPeakTimeInSeconds = Double(earlyPeakPosition) / sampleRate

    var earlyPreviewStartTime = Swift.max(0, earlyPeakTimeInSeconds - halfPreviewDuration)
    var earlyPreviewLength = previewDuration
    earlyPreviewLength = Swift.max(
      0, Swift.min(previewDuration, totalDurationInSeconds - earlyPreviewStartTime)
    )

    if earlyPreviewLength > totalDurationInSeconds {
      earlyPreviewStartTime = 0
      earlyPreviewLength = totalDurationInSeconds
    }

    #expect(abs(earlyPreviewStartTime - 0.0) < 0.01, "Peak at 1s should clamp preview start to 0")
    #expect(abs(earlyPreviewLength - 3.0) < 0.01, "Preview should still be 3 seconds long")

    // Test case 3: Very short file (2 seconds total)
    let shortTotalFrames: Int64 = 48000 * 2 // 2 second file
    let shortPeakPosition: Int64 = 48000 * 1 // 1 second into the file

    let shortPeakTimeInSeconds = Double(shortPeakPosition) / sampleRate
    let shortTotalDurationInSeconds = Double(shortTotalFrames) / sampleRate

    var shortPreviewStartTime = Swift.max(0, shortPeakTimeInSeconds - halfPreviewDuration)
    var shortPreviewLength = previewDuration
    shortPreviewLength = Swift.max(
      0, Swift.min(previewDuration, shortTotalDurationInSeconds - shortPreviewStartTime)
    )

    if shortPreviewLength > shortTotalDurationInSeconds {
      shortPreviewStartTime = 0
      shortPreviewLength = shortTotalDurationInSeconds
    }

    #expect(abs(shortPreviewStartTime - 0.0) < 0.01, "Short file should start preview at 0")
    #expect(abs(shortPreviewLength - 2.0) < 0.01, "Short file preview should be full file length")
  }

  @Test
  func testTaskEntryPreviewTimeDisplayProperties() {
    // Test TaskEntry with preview time values
    let url = URL(fileURLWithPath: "/test/audio.wav")
    var taskEntry = TaskEntry(url: url)

    // Set some sample values
    taskEntry.previewStartAtTime = 125.5 // 2 minutes, 5.5 seconds
    taskEntry.previewLength = 3.0

    #expect(
      taskEntry.previewStartAtTimeDisplayed == "2:05.500",
      "Preview start time should be formatted as MM:SS.sss"
    )
    #expect(
      taskEntry.previewLengthDisplayed == "3.000s",
      "Preview length should be formatted with 3 decimal places"
    )
    #expect(
      taskEntry.previewRangeDisplayed == "2:05.500 - 2:08.500",
      "Preview range should show start to end time"
    )

    // Test with nil values
    taskEntry.previewStartAtTime = nil
    taskEntry.previewLength = nil

    #expect(
      taskEntry.previewStartAtTimeDisplayed == "N/A",
      "Should display N/A when preview start time is nil"
    )
    #expect(
      taskEntry.previewLengthDisplayed == "N/A", "Should display N/A when preview length is nil"
    )
    #expect(
      taskEntry.previewRangeDisplayed == "N/A", "Should display N/A when preview values are nil"
    )
  }
}
