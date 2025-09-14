// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation
import Testing

@testable import ExtAudioProcessor
@testable import R128xCLIKit

// MARK: - RF64SupportTests

@Suite
struct RF64SupportTests {
  // MARK: Internal

  // MARK: - RF64 Detection Tests

  @Test
  func testRF64FileDetection() throws {
    // Create temporary RF64 test file
    let tempDir = FileManager.default.temporaryDirectory
    let rf64URL = tempDir.appendingPathComponent("test_rf64.wav")
    let rf64Data = createRF64TestData()

    try rf64Data.write(to: rf64URL)
    defer { try? FileManager.default.removeItem(at: rf64URL) }

    // Test RF64 detection
    #expect(
      RF64Support.isRF64File(at: rf64URL.path(percentEncoded: false)), "Should detect RF64 format"
    )

    // Create temporary WAV test file
    let wavURL = tempDir.appendingPathComponent("test_wav.wav")
    let wavData = createWAVTestData()

    try wavData.write(to: wavURL)
    defer { try? FileManager.default.removeItem(at: wavURL) }

    // Test WAV detection (should not be RF64)
    #expect(
      !RF64Support.isRF64File(at: wavURL.path(percentEncoded: false)),
      "Should not detect regular WAV as RF64"
    )
  }

  @Test
  func testRF64FileDetectionWithInvalidFile() throws {
    // Test with non-existent file
    #expect(
      !RF64Support.isRF64File(at: "/nonexistent/file.wav"),
      "Should handle non-existent files gracefully"
    )

    // Test with empty file
    let tempDir = FileManager.default.temporaryDirectory
    let emptyURL = tempDir.appendingPathComponent("empty.wav")
    let emptyData = Data()

    do {
      try emptyData.write(to: emptyURL)
      defer { try? FileManager.default.removeItem(at: emptyURL) }

      #expect(
        !RF64Support.isRF64File(at: emptyURL.path(percentEncoded: false)),
        "Should handle empty files gracefully"
      )
    } catch {
      Issue.record("Failed to create empty test file: \(error)")
    }
  }

  // MARK: - RF64 Parsing Tests

  @Test
  func testRF64InfoParsing() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let rf64URL = tempDir.appendingPathComponent("test_rf64_parse.wav")
    let rf64Data = createRF64TestData()

    try rf64Data.write(to: rf64URL)
    defer { try? FileManager.default.removeItem(at: rf64URL) }

    // Test RF64 info parsing
    let info = try RF64Support.parseRF64Info(at: rf64URL.path(percentEncoded: false))

    #expect(info.isValidRF64, "Should parse as valid RF64")
    #expect(info.dataSize == 0x0000_0001_0000_0000, "Should parse correct data size")
    #expect(info.sampleCount == 0, "Should parse correct sample count")
  }

  @Test
  func testRF64InfoParsingWithWAVFile() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let wavURL = tempDir.appendingPathComponent("test_wav_parse.wav")
    let wavData = createWAVTestData()

    try wavData.write(to: wavURL)
    defer { try? FileManager.default.removeItem(at: wavURL) }

    // Test RF64 info parsing with WAV file (should fail)
    #expect(throws: RF64Support.RF64Error.self) {
      try RF64Support.parseRF64Info(at: wavURL.path(percentEncoded: false))
    }
  }

  // MARK: - RF64 Support Status Tests

  @Test
  func testRF64SupportStatus() throws {
    // Test with RF64 file
    let tempDir = FileManager.default.temporaryDirectory
    let rf64URL = tempDir.appendingPathComponent("test_rf64_status.wav")
    let rf64Data = createRF64TestData()

    try rf64Data.write(to: rf64URL)
    defer { try? FileManager.default.removeItem(at: rf64URL) }

    let rf64Status = RF64Support.getRF64SupportStatus(for: rf64URL.path(percentEncoded: false))
    #expect(!rf64Status.isEmpty, "Should provide non-empty status message for RF64 files")
    #expect(rf64Status.contains("RF64"), "Status message should mention RF64 format")

    // Test with non-RF64 file
    let wavURL = tempDir.appendingPathComponent("test_wav_status.wav")
    let wavData = createWAVTestData()

    try wavData.write(to: wavURL)
    defer { try? FileManager.default.removeItem(at: wavURL) }

    let wavStatus = RF64Support.getRF64SupportStatus(for: wavURL.path(percentEncoded: false))
    #expect(wavStatus.contains("not in RF64 format"), "Should indicate when file is not RF64")
  }

  // MARK: - CoreAudio Support Tests

  @Test
  func testCoreAudioRF64Support() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let rf64URL = tempDir.appendingPathComponent("test_rf64_coreaudio.wav")
    let rf64Data = createRF64TestData()

    try rf64Data.write(to: rf64URL)
    defer { try? FileManager.default.removeItem(at: rf64URL) }

    // Test CoreAudio RF64 support (expected to fail with test data)
    #if canImport(AudioToolbox)
    let isSupported = RF64Support.testCoreAudioRF64Support(
      at: rf64URL.path(percentEncoded: false)
    )
    // We expect this to be false since our test data is not a valid audio file
    #expect(!isSupported, "Test RF64 data should not be supported by CoreAudio")
    #endif

    // Test with non-RF64 file
    let wavURL = tempDir.appendingPathComponent("test_wav_coreaudio.wav")
    let wavData = createWAVTestData()

    try wavData.write(to: wavURL)
    defer { try? FileManager.default.removeItem(at: wavURL) }

    let wavSupported = RF64Support.testCoreAudioRF64Support(at: wavURL.path(percentEncoded: false))
    #expect(!wavSupported, "WAV file should not be tested for RF64 support")
  }

  // MARK: - Error Handling Tests

  @Test
  func testRF64ErrorTypes() {
    let errors: [RF64Support.RF64Error] = [
      .invalidHeader,
      .invalidDS64Chunk,
      .notRF64File,
      .coreAudioUnsupported,
      .fileReadError,
    ]

    for error in errors {
      #expect(error.errorDescription != nil, "All RF64 errors should have descriptions")
      #expect(!error.errorDescription!.isEmpty, "Error descriptions should not be empty")
    }
  }

  // MARK: Private

  // MARK: - Test Data Generation

  /// Create a minimal RF64 file header for testing
  private func createRF64TestData() -> Data {
    var data = Data()

    // RF64 header
    data.append(contentsOf: [0x52, 0x46, 0x36, 0x34]) // "RF64"
    data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // Chunk size (placeholder)
    data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

    // ds64 chunk
    data.append(contentsOf: [0x64, 0x73, 0x36, 0x34]) // "ds64"
    data.append(contentsOf: [0x1C, 0x00, 0x00, 0x00]) // ds64 chunk size (28 bytes)
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // RIFF size low
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x01]) // RIFF size high
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Data size low - 0x0000_0000
    data.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // Data size high - 0x0000_0001 (little-endian)
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Sample count low
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Sample count high
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Table length

    return data
  }

  /// Create a regular WAV file header for testing
  private func createWAVTestData() -> Data {
    var data = Data()

    // WAV header
    data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
    data.append(contentsOf: [0x24, 0x00, 0x00, 0x00]) // Chunk size
    data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

    return data
  }
}

// MARK: - RF64IntegrationTests

@Suite
struct RF64IntegrationTests {
  @Test
  func testExtAudioProcessorRF64ErrorHandling() async throws {
    // Create a fake RF64 file for testing error handling
    let tempDir = FileManager.default.temporaryDirectory
    let rf64URL = tempDir.appendingPathComponent("test_rf64_integration.wav")

    var data = Data()
    // RF64 header
    data.append(contentsOf: [0x52, 0x46, 0x36, 0x34]) // "RF64"
    data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // Chunk size
    data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

    try data.write(to: rf64URL)
    defer { try? FileManager.default.removeItem(at: rf64URL) }

    // Test ExtAudioProcessor with RF64 file
    let processor = ExtAudioProcessor()

    do {
      _ = try await processor.processAudioFile(at: rf64URL.path(percentEncoded: false))
      Issue.record("Should have thrown an error for unsupported RF64 file")
    } catch let error as NSError {
      // Verify we get an RF64-specific error message
      #expect(
        error.localizedDescription.contains("RF64")
          || error.localizedRecoverySuggestion?.contains("RF64") == true,
        "Error should mention RF64 format: \(error)"
      )
    } catch {
      Issue.record("Should have thrown NSError with RF64 information")
    }
  }

  @Test
  func testCLIRF64ErrorOutput() async throws {
    // This test would require actually running the CLI, which we can't do easily in unit tests
    // But we can test the CliController error handling path

    let tempDir = FileManager.default.temporaryDirectory
    let rf64URL = tempDir.appendingPathComponent("test_rf64_cli.wav")

    var data = Data()
    // Minimal RF64 header
    data.append(contentsOf: [0x52, 0x46, 0x36, 0x34]) // "RF64"
    data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // Chunk size
    data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

    try data.write(to: rf64URL)
    defer { try? FileManager.default.removeItem(at: rf64URL) }

    let controller = CliController(path: rf64URL.path(percentEncoded: false))
    await controller.doMeasure()

    // Should have failed
    #expect(controller.status != 0, "Should have failed processing RF64 file")
    #expect(controller.il.isNaN, "Integrated loudness should be NaN on failure")
    #expect(controller.lra.isNaN, "Loudness range should be NaN on failure")
    #expect(controller.maxTP.isNaN, "Max true peak should be NaN on failure")
  }
}
