// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation
import Testing

@testable import ExtAudioProcessor
@testable import R128xCLIKit

// MARK: - CliControllerTests

/// Test suite for CliController functionality including error handling and file processing
@Suite
struct CliControllerTests {
  @Test
  func testCLIRF64ErrorOutput() async throws {
    // Test CliController error handling with RF64 files
    let tempDir = FileManager.default.temporaryDirectory
    let rf64URL = tempDir.appendingPathComponent("test_rf64_cli.wav")

    var data = Data()
    // Minimal RF64 header
    data.append(contentsOf: [0x52, 0x46, 0x36, 0x34]) // "RF64"
    data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // Chunk size
    data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

    try data.write(to: rf64URL)
    defer { try? FileManager.default.removeItem(at: rf64URL) }

    // Run on MainActor since CliController is MainActor-isolated
    let result = await MainActor.run {
      let controller = CliController()
      return controller
    }

    let exitCode = await result.processFiles(filePaths: [rf64URL.path(percentEncoded: false)])

    // Should have failed due to invalid RF64 file
    #expect(exitCode == 1, "Should have failed processing invalid RF64 file")

    let taskEntries = await MainActor.run { result.taskEntries }
    #expect(!taskEntries.isEmpty, "Should have created task entries")

    if let entry = taskEntries.first {
      #expect(entry.status == .failed, "Task should have failed")
      #expect(entry.programLoudness == nil, "Program loudness should be nil on failure")
      #expect(entry.loudnessRange == nil, "Loudness range should be nil on failure")
      #expect(entry.dBTP == nil, "dBTP should be nil on failure")
    }
  }

  @Test("Test CliController with non-existent file")
  func testCliControllerWithNonExistentFile() async throws {
    let controller = await MainActor.run { CliController() }
    let exitCode = await controller.processFiles(filePaths: ["/non/existent/file.wav"])

    // Should have failed due to non-existent file
    #expect(exitCode == 1, "Should have failed processing non-existent file")

    let taskEntries = await MainActor.run { controller.taskEntries }
    #expect(!taskEntries.isEmpty, "Should have created task entries")

    if let entry = taskEntries.first {
      #expect(entry.status == .failed, "Task should have failed")
      #expect(entry.fileName == "file.wav", "Should have correct filename")
    }
  }

  @Test("Test CliController with multiple invalid files")
  func testCliControllerWithMultipleInvalidFiles() async throws {
    let controller = await MainActor.run { CliController() }

    let tempDir = FileManager.default.temporaryDirectory
    let invalidFile1 = tempDir.appendingPathComponent("invalid1.wav")
    let invalidFile2 = tempDir.appendingPathComponent("invalid2.wav")

    // Create some invalid files
    try Data([0x00, 0x01, 0x02, 0x03]).write(to: invalidFile1)
    try Data([0xFF, 0xFE, 0xFD, 0xFC]).write(to: invalidFile2)

    defer {
      try? FileManager.default.removeItem(at: invalidFile1)
      try? FileManager.default.removeItem(at: invalidFile2)
    }

    let exitCode = await controller.processFiles(filePaths: [
      invalidFile1.path(percentEncoded: false),
      invalidFile2.path(percentEncoded: false),
    ])

    // Should have failed due to invalid files
    #expect(exitCode == 1, "Should have failed processing invalid files")

    let taskEntries = await MainActor.run { controller.taskEntries }
    #expect(taskEntries.count == 2, "Should have created 2 task entries")

    for entry in taskEntries {
      #expect(entry.status == .failed, "All tasks should have failed")
    }
  }

  @Test("Test CliController run method with help flag")
  func testCliControllerRunWithHelpFlag() async throws {
    // Mock command line arguments for help
    let args = ["r128x", "--help"]
    let parseResult = CLIArgumentParser.parse(arguments: args, masMode: false)

    switch parseResult {
    case let .success(config):
      #expect(config.showHelp == true, "Should show help")
      #expect(config.filePaths.isEmpty, "Should have no file paths")
    case .failure:
      Issue.record("Help parsing should not fail")
    }
  }

  @Test("Test CliController help output in standard mode")
  func testCliControllerHelpStandardMode() async throws {
    let controller = await MainActor.run { CliController() }
    let exitCode = await controller.run(masMode: false)

    // When no arguments are provided, it should fail and show usage info
    #expect(exitCode == 1, "Should fail when no arguments provided")
  }

  @Test("Test CliController help output in MAS mode with --cli --help")
  func testCliControllerHelpMASMode() async throws {
    // Test MAS mode with --cli --help
    let args = ["r128x", "--cli", "--help"]
    let parseResult = CLIArgumentParser.parse(arguments: args, masMode: true)

    switch parseResult {
    case let .success(config):
      #expect(config.showHelp == true, "Should show help")
      #expect(config.filePaths.isEmpty, "Should have no file paths")

      // Test that the help is displayed correctly in MAS mode
      // We need to create a custom test that simulates the help display
      await MainActor.run {
        let controller = CliController()
        // Simulate the help display by directly calling printHelp with masMode: true
        controller.printHelp(executableName: "test-r128x", masMode: true)
      }
    case .failure:
      Issue.record("MAS mode help parsing should not fail")
    }
  }

  @Test("Test file access permission request for non-sandboxed environment")
  func testFileAccessPermissionNonSandboxed() async throws {
    let controller = await MainActor.run { CliController() }

    // In non-sandboxed environment, permission should be granted automatically
    let granted = await controller.requestFileAccessPermission(for: ["/tmp/test.wav"])
    #expect(granted == true, "Permission should be granted in non-sandboxed environment")
  }

  @Test("Test CliController run method with MAS mode")
  func testCliControllerRunWithMASMode() async throws {
    // Test MAS mode without --cli flag (should fail)
    let argsWithoutCli = ["r128x", "file.wav"]
    let resultWithoutCli = CLIArgumentParser.parse(arguments: argsWithoutCli, masMode: true)

    switch resultWithoutCli {
    case .success:
      Issue.record("MAS mode without --cli should fail")
    case let .failure(error):
      if case let .invalidArguments(message) = error {
        #expect(message.contains("MAS mode requires --cli flag"))
      }
    }

    // Test MAS mode with --cli flag (should succeed if files exist)
    let argsWithCli = ["r128x", "--cli", "file.wav"]
    let resultWithCli = CLIArgumentParser.parse(arguments: argsWithCli, masMode: true)

    switch resultWithCli {
    case let .success(config):
      #expect(config.filePaths == ["file.wav"])
      #expect(config.showHelp == false)
    case .failure:
      Issue.record("MAS mode with --cli should succeed")
    }
  }
}

// MARK: - ErrorHandlingTests

/// Test suite for various error conditions and edge cases
@Suite("Error Handling Tests")
struct ErrorHandlingTests {
  @Test("Test CLIError localized descriptions")
  func testCLIErrorLocalizedDescriptions() {
    let invalidArgsError = CLIError.invalidArguments("Test invalid arguments")
    #expect(invalidArgsError.localizedDescription == "Test invalid arguments")

    let noFilesError = CLIError.noFilesProvided("r128x")
    if let description = noFilesError.errorDescription {
      #expect(description.contains("Missing arguments"))
      #expect(description.contains("r128x"))
      #expect(description.contains("--help"))
    } else {
      Issue.record("Error description should not be nil")
    }
  }

  @Test("Test invalid file path handling")
  func testInvalidFilePathHandling() async throws {
    let controller = await MainActor.run { CliController() }

    // Test with various invalid paths
    let invalidPaths = [
      "/dev/null/nonexistent.wav",
      "",
      "/root/restricted/file.wav",
      "not-a-path",
      "/tmp/\0invalid\0path.wav",
    ]

    let exitCode = await controller.processFiles(filePaths: invalidPaths)

    // Should have failed due to invalid paths
    #expect(exitCode == 1, "Should have failed processing invalid paths")

    let taskEntries = await MainActor.run { controller.taskEntries }
    #expect(taskEntries.count == invalidPaths.count, "Should have created entries for all paths")

    for entry in taskEntries {
      #expect(entry.status == .failed, "All tasks should have failed")
    }
  }

  @Test("Test directory instead of file")
  func testDirectoryInsteadOfFile() async throws {
    let controller = await MainActor.run { CliController() }

    // Use a directory path instead of file
    let tempDir = FileManager.default.temporaryDirectory
    let directoryPath = tempDir.path(percentEncoded: false)

    let exitCode = await controller.processFiles(filePaths: [directoryPath])

    // Should have failed because it's a directory, not a file
    #expect(exitCode == 1, "Should have failed when given a directory instead of file")

    let taskEntries = await MainActor.run { controller.taskEntries }
    #expect(!taskEntries.isEmpty, "Should have created task entries")

    if let entry = taskEntries.first {
      #expect(entry.status == .failed, "Task should have failed")
    }
  }

  @Test("Test empty file handling")
  func testEmptyFileHandling() async throws {
    let controller = await MainActor.run { CliController() }

    let tempDir = FileManager.default.temporaryDirectory
    let emptyFile = tempDir.appendingPathComponent("empty.wav")

    // Create empty file
    try Data().write(to: emptyFile)
    defer { try? FileManager.default.removeItem(at: emptyFile) }

    let exitCode = await controller.processFiles(filePaths: [emptyFile.path(percentEncoded: false)])

    // Should have failed due to empty file
    #expect(exitCode == 1, "Should have failed processing empty file")

    let taskEntries = await MainActor.run { controller.taskEntries }
    #expect(!taskEntries.isEmpty, "Should have created task entries")

    if let entry = taskEntries.first {
      #expect(entry.status == .failed, "Task should have failed")
      #expect(entry.fileName == "empty.wav", "Should have correct filename")
    }
  }

  @Test("Test corrupted audio file header")
  func testCorruptedAudioFileHeader() async throws {
    let controller = await MainActor.run { CliController() }

    let tempDir = FileManager.default.temporaryDirectory
    let corruptedFile = tempDir.appendingPathComponent("corrupted.wav")

    // Create file with invalid WAV header
    var data = Data()
    data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
    data.append(contentsOf: [0x10, 0x00, 0x00, 0x00]) // File size
    data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
    data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
    data.append(contentsOf: [0x10, 0x00, 0x00, 0x00]) // Chunk size
    // Intentionally corrupted format data
    data.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])

    try data.write(to: corruptedFile)
    defer { try? FileManager.default.removeItem(at: corruptedFile) }

    let exitCode = await controller.processFiles(filePaths: [
      corruptedFile.path(percentEncoded: false),
    ])

    // Should have failed due to corrupted file
    #expect(exitCode == 1, "Should have failed processing corrupted file")

    let taskEntries = await MainActor.run { controller.taskEntries }
    #expect(!taskEntries.isEmpty, "Should have created task entries")

    if let entry = taskEntries.first {
      #expect(entry.status == .failed, "Task should have failed")
      #expect(entry.fileName == "corrupted.wav", "Should have correct filename")
    }
  }

  @Test("Test mixed success and failure scenarios")
  func testMixedSuccessAndFailureScenarios() async throws {
    let controller = await MainActor.run { CliController() }

    let tempDir = FileManager.default.temporaryDirectory
    let validFile = tempDir.appendingPathComponent("test.txt") // Not audio, but file exists
    let invalidFile = tempDir.appendingPathComponent("nonexistent.wav")

    // Create a regular text file (will fail audio processing but file exists)
    try "This is not an audio file".write(to: validFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: validFile) }

    let filePaths = [
      validFile.path(percentEncoded: false),
      invalidFile.path(percentEncoded: false),
    ]

    let exitCode = await controller.processFiles(filePaths: filePaths)

    // Should have failed due to at least one failure
    #expect(exitCode == 1, "Should have failed when any file fails")

    let taskEntries = await MainActor.run { controller.taskEntries }
    #expect(taskEntries.count == 2, "Should have created 2 task entries")

    // All should have failed (non-audio file and non-existent file)
    for entry in taskEntries {
      #expect(entry.status == .failed, "All tasks should have failed")
    }
  }
}

// MARK: - CLIArgumentParserTests

/// Test suite for CLIArgumentParser functionality including different modes and error cases
@Suite("CLI Argument Parser Tests")
struct CLIArgumentParserTests {
  @Test("Parse standard mode with file arguments")
  func testParseStandardModeWithFiles() throws {
    let args = ["r128x", "file1.wav", "file2.flac"]
    let result = CLIArgumentParser.parse(arguments: args, masMode: false)

    switch result {
    case let .success(config):
      // In testing environment, the executable name comes from ProcessInfo
      #expect(!config.executableName.isEmpty)
      #expect(config.filePaths == ["file1.wav", "file2.flac"])
      #expect(config.showHelp == false)
    case let .failure(error):
      Issue.record("Should not fail: \(error)")
    }
  }

  @Test("Parse standard mode with --cli flag")
  func testParseStandardModeWithCliFlag() throws {
    let args = ["r128x", "--cli", "file1.wav", "file2.flac"]
    let result = CLIArgumentParser.parse(arguments: args, masMode: false)

    switch result {
    case let .success(config):
      #expect(!config.executableName.isEmpty)
      #expect(config.filePaths == ["file1.wav", "file2.flac"])
      #expect(config.showHelp == false)
    case let .failure(error):
      Issue.record("Should not fail: \(error)")
    }
  }

  @Test("Parse MAS mode with --cli flag")
  func testParseMASModeWithCliFlag() throws {
    let args = ["r128x", "--cli", "file1.wav", "file2.flac"]
    let result = CLIArgumentParser.parse(arguments: args, masMode: true)

    switch result {
    case let .success(config):
      #expect(!config.executableName.isEmpty)
      #expect(config.filePaths == ["file1.wav", "file2.flac"])
      #expect(config.showHelp == false)
    case let .failure(error):
      Issue.record("Should not fail: \(error)")
    }
  }

  @Test("Parse MAS mode without --cli flag should fail")
  func testParseMASModeWithoutCliFlagShouldFail() throws {
    let args = ["r128x", "file1.wav", "file2.flac"]
    let result = CLIArgumentParser.parse(arguments: args, masMode: true)

    switch result {
    case .success:
      Issue.record("Should fail in MAS mode without --cli flag")
    case let .failure(error):
      if case let .invalidArguments(message) = error {
        #expect(message.contains("MAS mode requires --cli flag"))
      } else {
        Issue.record("Wrong error type: \(error)")
      }
    }
  }

  @Test("Parse help flag --help")
  func testParseHelpFlag() throws {
    let args = ["r128x", "--help"]
    let result = CLIArgumentParser.parse(arguments: args, masMode: false)

    switch result {
    case let .success(config):
      #expect(!config.executableName.isEmpty)
      #expect(config.filePaths.isEmpty)
      #expect(config.showHelp == true)
    case let .failure(error):
      Issue.record("Should not fail: \(error)")
    }
  }

  @Test("Parse help flag -h")
  func testParseHelpFlagShort() throws {
    let args = ["r128x", "-h"]
    let result = CLIArgumentParser.parse(arguments: args, masMode: false)

    switch result {
    case let .success(config):
      #expect(!config.executableName.isEmpty)
      #expect(config.filePaths.isEmpty)
      #expect(config.showHelp == true)
    case let .failure(error):
      Issue.record("Should not fail: \(error)")
    }
  }

  @Test("Parse --cli --help combination")
  func testParseCliHelpCombination() throws {
    let args = ["r128x", "--cli", "--help"]
    let result = CLIArgumentParser.parse(arguments: args, masMode: false)

    switch result {
    case let .success(config):
      #expect(!config.executableName.isEmpty)
      #expect(config.filePaths.isEmpty)
      #expect(config.showHelp == true)
    case let .failure(error):
      Issue.record("Should not fail: \(error)")
    }
  }

  @Test("Parse --cli --help combination in MAS mode")
  func testParseCliHelpCombinationMASMode() throws {
    let args = ["r128x", "--cli", "--help"]
    let result = CLIArgumentParser.parse(arguments: args, masMode: true)

    switch result {
    case let .success(config):
      #expect(!config.executableName.isEmpty)
      #expect(config.filePaths.isEmpty)
      #expect(config.showHelp == true)
    case let .failure(error):
      Issue.record("Should not fail: \(error)")
    }
  }

  @Test("Parse with no files should fail")
  func testParseWithNoFilesShouldFail() throws {
    let args = ["r128x"]
    let result = CLIArgumentParser.parse(arguments: args, masMode: false)

    switch result {
    case .success:
      Issue.record("Should fail when no files provided")
    case let .failure(error):
      if case let .noFilesProvided(execName) = error {
        #expect(!execName.isEmpty)
      } else {
        Issue.record("Wrong error type: \(error)")
      }
    }
  }

  @Test("Parse with --cli but no files should fail")
  func testParseWithCliFlagButNoFilesShouldFail() throws {
    let args = ["r128x", "--cli"]
    let result = CLIArgumentParser.parse(arguments: args, masMode: false)

    switch result {
    case .success:
      Issue.record("Should fail when --cli provided but no files")
    case let .failure(error):
      if case let .noFilesProvided(execName) = error {
        #expect(execName.contains("--cli"))
      } else {
        Issue.record("Wrong error type: \(error)")
      }
    }
  }

  @Test("Parse empty arguments should fail")
  func testParseEmptyArgumentsShouldFail() throws {
    let args: [String] = []
    let result = CLIArgumentParser.parse(arguments: args, masMode: false)

    switch result {
    case .success:
      Issue.record("Should fail when no arguments provided")
    case let .failure(error):
      if case let .invalidArguments(message) = error {
        #expect(message.contains("No arguments provided"))
      } else {
        Issue.record("Wrong error type: \(error)")
      }
    }
  }

  @Test("Parse with mixed flags and files")
  func testParseWithMixedFlagsAndFiles() throws {
    let args = ["r128x", "--cli", "file1.wav", "--some-flag", "file2.flac", "-x"]
    let result = CLIArgumentParser.parse(arguments: args, masMode: false)

    switch result {
    case let .success(config):
      #expect(!config.executableName.isEmpty)
      // Should only include files, not flags
      #expect(config.filePaths == ["file1.wav", "file2.flac"])
      #expect(config.showHelp == false)
    case let .failure(error):
      Issue.record("Should not fail: \(error)")
    }
  }
}
