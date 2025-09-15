// (c) (C ver. only) 2012-2013 Manuel Naudin (AGPL v3.0 License or later).
// (c) (this Swift implementation) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.
// ====================
// This file is part of r128x.
//
// r128x is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// r128x is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with r128x.  If not, see <http://www.gnu.org/licenses/>.
// copyright Manuel Naudin 2012-2013

import ExtAudioProcessor
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - CLIConfig

public struct CLIConfig {
  // MARK: Lifecycle

  public init(executableName: String, filePaths: [String], showHelp: Bool = false) {
    self.executableName = executableName
    self.filePaths = filePaths
    self.showHelp = showHelp
  }

  // MARK: Public

  public let executableName: String
  public let filePaths: [String]
  public let showHelp: Bool
}

// MARK: - CLIArgumentParser

public enum CLIArgumentParser {
  public static func parse(arguments: [String] = CommandLine.arguments, masMode: Bool = false)
    -> Result<CLIConfig, CLIError> {
    guard !arguments.isEmpty else {
      return .failure(.invalidArguments("No arguments provided"))
    }

    let executableName = ProcessInfo.processInfo.processName
    let args = Array(arguments.dropFirst()) // Drop executable name

    // Handle help flags
    if args.contains("--help") || args.contains("-h") {
      return .success(CLIConfig(executableName: executableName, filePaths: [], showHelp: true))
    }

    // In MAS mode, we require --cli flag
    if masMode {
      // Look for --cli flag
      guard let cliIndex = args.firstIndex(of: "--cli") else {
        return .failure(.invalidArguments("MAS mode requires --cli flag"))
      }

      // Get file paths after --cli flag
      let filePaths = Array(args.dropFirst(cliIndex + 1)).filter { arg in
        !arg.hasPrefix("--") && !arg.hasPrefix("-")
      }

      guard !filePaths.isEmpty else {
        return .failure(.noFilesProvided(executableName + " --cli"))
      }

      return .success(CLIConfig(executableName: executableName, filePaths: filePaths))
    } else {
      // Standard mode: support both --cli and direct file arguments
      let hasCliFlag = args.contains("--cli")

      let filePaths: [String]
      if hasCliFlag {
        // If --cli is present, get files after it
        guard let cliIndex = args.firstIndex(of: "--cli") else {
          return .failure(.invalidArguments("Invalid CLI flag usage"))
        }
        filePaths = Array(args.dropFirst(cliIndex + 1)).filter { arg in
          !arg.hasPrefix("--") && !arg.hasPrefix("-")
        }
      } else {
        // No --cli flag, treat all non-flag arguments as file paths
        filePaths = args.filter { arg in
          !arg.hasPrefix("--") && !arg.hasPrefix("-")
        }
      }

      guard !filePaths.isEmpty else {
        let sampleCommand = hasCliFlag ? "\(executableName) --cli" : executableName
        return .failure(.noFilesProvided(sampleCommand))
      }

      return .success(CLIConfig(executableName: executableName, filePaths: filePaths))
    }
  }
}

// MARK: - CLIError

public enum CLIError: Error, LocalizedError {
  case invalidArguments(String)
  case noFilesProvided(String)

  // MARK: Public

  public var errorDescription: String? {
    switch self {
    case let .invalidArguments(message):
      return message
    case let .noFilesProvided(executableName):
      return """
      Missing arguments. You should specify at least one audio file. E.g.:
      \(executableName) /path/to/audio/file.wav
      Use --help for more information.
      """
    }
  }
}

// MARK: - CliController

@MainActor
public final class CliController {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  public private(set) var taskEntries: [TaskEntry] = []

  // MARK: Main Entry Points

  /// Do not call this in unit tests.
  /// - Parameter mas: If true, only accepts `execName --cli file1 file2...` format (for MAS GUI apps)
  ///                  If false, accepts both `execName --cli file1...` and `execName file1...` formats
  public static func runMainAndExit(mas: Bool = false) async {
    let controller = CliController()
    let exitCode = await controller.run(masMode: mas)
    exit(exitCode)
  }

  /// Legacy method for backward compatibility
  @available(*, deprecated, message: "Use run(masMode:) instead")
  public static func handleVarArgsAndProcess(dropping droppedCount: Int = 1) async -> Int32 {
    let controller = CliController()
    return await controller.run(masMode: false)
  }

  /// Main execution function with proper error handling
  /// - Parameter masMode: Whether to use MAS mode (requires --cli flag)
  public func run(masMode: Bool = false) async -> Int32 {
    let parseResult = CLIArgumentParser.parse(masMode: masMode)

    switch parseResult {
    case let .success(config):
      if config.showHelp {
        printHelp(executableName: config.executableName)
        return 0
      }
      return await processFiles(filePaths: config.filePaths)

    case let .failure(error):
      print("Error: \(error.localizedDescription)", to: &standardError)
      return 1
    }
  }

  // MARK: File Processing

  public func processFiles(filePaths: [String]) async -> Int32 {
    // Initialize task entries from file paths
    initializeTaskEntries(from: filePaths)

    // Print table header
    print("FILE\tIL (LUFS)\tLRA (LU)\tMAXTP (dBTP)")

    // Process each file and collect results
    var hasFailures = false

    for i in taskEntries.indices {
      await processTaskEntry(at: i)

      let entry = taskEntries[i]
      print(formatResult(for: entry))

      if entry.status == .failed {
        hasFailures = true
      }
    }

    // Return appropriate exit code
    return hasFailures ? 1 : 0
  }

  // MARK: Private

  // MARK: Private Implementation

  /// Check if we're running in an interactive terminal (not piped)
  private var isInteractiveTerminal: Bool {
    // Check if stdout is a tty (terminal) and not redirected/piped
    isatty(STDOUT_FILENO) != 0
  }

  private func initializeTaskEntries(from filePaths: [String]) {
    taskEntries = filePaths.compactMap { path in
      let url = URL(fileURLWithPath: path)
      return TaskEntry(url: url)
    }
  }

  private func processTaskEntry(at index: Int) async {
    // Update status to processing
    taskEntries[index].status = .processing

    do {
      let processor = ExtAudioProcessor()
      let result = try await processor.processAudioFile(
        at: taskEntries[index].fileNamePath,
        fileId: taskEntries[index].id.uuidString
      ) { @Sendable progress in
        Task { @MainActor in
          // Update progress information
          self.taskEntries[index].progressPercentage = progress.percentage
          self.taskEntries[index].estimatedTimeRemaining = progress.estimatedTimeRemaining
          self.taskEntries[index].currentLoudness = progress.currentLoudness

          // Display progress bar
          self.displayProgress(progress, for: self.taskEntries[index].fileName)
        }
      }

      // Clear progress line and update with results
      clearProgressLine()

      taskEntries[index].programLoudness = result.integratedLoudness
      taskEntries[index].loudnessRange = result.loudnessRange
      taskEntries[index].dBTP = result.maxTruePeak
      taskEntries[index].previewStartAtTime = result.previewStartAtTime
      taskEntries[index].previewLength = result.previewLength
      taskEntries[index].status = .succeeded
      taskEntries[index].progressPercentage = nil

    } catch {
      clearProgressLine()
      taskEntries[index].status = .failed
      taskEntries[index].progressPercentage = nil

      // Print detailed error information
      if let nsError = error as NSError? {
        print(
          "Error processing \(taskEntries[index].fileName): \(nsError.localizedDescription)",
          to: &standardError
        )
        if let recoverySuggestion = nsError.localizedRecoverySuggestion {
          print("  \(recoverySuggestion)", to: &standardError)
        }
      } else {
        print(
          "Error processing \(taskEntries[index].fileName): \(error.localizedDescription)",
          to: &standardError
        )
      }
    }
  }

  private func displayProgress(
    _ progress: ExtAudioProcessor.ProcessingProgress, for fileName: String
  ) {
    // Only show progress bar in interactive terminals, not when piped
    guard isInteractiveTerminal else { return }

    let percentage = Int(floor(progress.percentage))
    let totalWidth = 30
    let filledWidth = Int(Double(totalWidth) * progress.percentage / 100.0)
    let emptyWidth = totalWidth - filledWidth

    let filledPart = String(repeating: "=", count: filledWidth)
    let emptyPart = String(repeating: "-", count: emptyWidth)
    let progressBar = filledPart + emptyPart

    // Use stderr for progress to avoid interfering with stdout output
    FileHandle.standardError.write(
      Data(String(format: "\r[%@] %3d%% - %@", progressBar, percentage, fileName).utf8)
    )
  }

  private func clearProgressLine() {
    // Only clear progress line in interactive terminals
    guard isInteractiveTerminal else { return }

    // Use stderr to clear the progress line
    FileHandle.standardError.write(Data(("\r" + String(repeating: " ", count: 80) + "\r").utf8))
  }

  private func formatResult(for entry: TaskEntry) -> String {
    var blocks: [String] = []
    blocks.append(entry.fileName)

    switch entry.status {
    case .succeeded:
      blocks.append(String(format: "%.1f", entry.programLoudness ?? Double.nan))
      blocks.append(String(format: "%.1f", entry.loudnessRange ?? Double.nan))
      blocks.append(String(format: "%.1f", entry.dBTP ?? Double.nan))
    case .failed:
      blocks.append("// Processing Failed.")
    case .processing:
      blocks.append("// Still Processing...")
    }

    return blocks.joined(separator: "\t")
  }

  private func printHelp(executableName: String) {
    let helpText = """
    r128x - EBU R128 Loudness Measurement Tool

    USAGE:
        \(executableName) [OPTIONS] <file1> [file2] [file3] ...

    ARGUMENTS:
        <file>    Audio file(s) to analyze

    OPTIONS:
        -h, --help    Show this help message

    EXAMPLES:
        \(executableName) audio.wav
        \(executableName) *.wav
        \(executableName) song1.mp3 song2.flac song3.aac

    OUTPUT:
        Results are displayed in tab-separated format:
        FILE    IL (LUFS)    LRA (LU)    MAXTP (dBTP)

    For more information, visit: https://github.com/ShikiSuen/r128x
    """

    print(helpText)
  }
}

// MARK: - StandardError

private struct StandardError: TextOutputStream {
  mutating func write(_ string: String) {
    FileHandle.standardError.write(Data(string.utf8))
  }
}

@MainActor private var standardError = StandardError()
