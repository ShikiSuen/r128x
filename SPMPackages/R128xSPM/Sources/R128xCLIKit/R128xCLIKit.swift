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

#if canImport(AppKit)
import AppKit
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
    let argsOfLowerCases = args.map { $0.lowercased() }

    // Handle help flags (including --cli --help combination)
    if argsOfLowerCases.contains("--help") || argsOfLowerCases.contains("-h") {
      return .success(CLIConfig(executableName: executableName, filePaths: [], showHelp: true))
    }

    // In MAS mode, we require --cli flag
    if masMode {
      // Look for --cli flag
      guard let cliIndex = argsOfLowerCases.firstIndex(of: "--cli") else {
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
      let hasCliFlag = argsOfLowerCases.contains("--cli")

      let filePaths: [String]
      if hasCliFlag {
        // If --cli is present, get files after it
        guard let cliIndex = argsOfLowerCases.firstIndex(of: "--cli") else {
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
        printHelp(executableName: config.executableName, masMode: masMode)
        return 0
      }

      // In MAS mode, request file access permission if needed
      if masMode {
        let granted = await requestFileAccessPermission(for: config.filePaths)
        if !granted {
          print("Error: File access permission denied by user", to: &standardError)
          return 1
        }
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

  // MARK: Internal

  internal func printHelp(executableName: String, masMode: Bool = false) {
    let helpText: String

    if masMode {
      helpText = """
      r128x - EBU R128 Loudness Measurement Tool

      USAGE:
          \(executableName) --cli [OPTIONS] <file1> [file2] [file3] ...

      ARGUMENTS:
          <file>    Audio file(s) to analyze

      OPTIONS:
          --cli         Enable CLI mode (otherwise, this app will run in GUI mode)
          -h, --help    Show this help message (Only works when CLI mode is enabled)

      EXAMPLES:
          \(executableName) --cli audio.wav
          \(executableName) --cli *.wav
          \(executableName) --cli song1.mp3 song2.flac song3.aac

      OUTPUT:
          Results are displayed in tab-separated format:
          FILE    IL (LUFS)    LRA (LU)    MAXTP (dBTP)

      SANDBOX COMPATIBILITY:
          In the Mac App Store version, the app will show permission dialogs
          to request access to your audio files when using CLI mode.
          This ensures compatibility with macOS sandbox security requirements.

      For more information, visit: https://github.com/ShikiSuen/r128x
      """
    } else {
      helpText = """
      r128x - EBU R128 Loudness Measurement Tool

      USAGE:
          \(executableName) [OPTIONS] <file1> [file2] [file3] ...
          \(executableName) --cli [OPTIONS] <file1> [file2] [file3] ...

      ARGUMENTS:
          <file>    Audio file(s) to analyze

      OPTIONS:
          --cli         Enable CLI mode (required in some environments)
          -h, --help    Show this help message

      EXAMPLES:
          \(executableName) audio.wav
          \(executableName) *.wav
          \(executableName) song1.mp3 song2.flac song3.aac
          \(executableName) --cli audio.wav
          \(executableName) --cli --help

      OUTPUT:
          Results are displayed in tab-separated format:
          FILE    IL (LUFS)    LRA (LU)    MAXTP (dBTP)

      For more information, visit: https://github.com/ShikiSuen/r128x
      """
    }

    print(helpText)
  }

  /// Request file access permission using system UI dialog
  /// This is needed for sandboxed Mac App Store apps to access files via CLI
  internal func requestFileAccessPermission(for filePaths: [String]) async -> Bool {
    #if canImport(Darwin)
    // Check if we're in a sandbox environment
    let environment = ProcessInfo.processInfo.environment
    guard environment["APP_SANDBOX_CONTAINER_ID"] != nil else {
      // Not sandboxed, no permission needed
      return true
    }

    // Group files by their parent directories to minimize dialog prompts
    let uniqueDirectories = Set(
      filePaths.compactMap { path in
        URL(fileURLWithPath: path).deletingLastPathComponent().path
      }
    )

    print("This app needs permission to access the specified files.", to: &standardError)
    print(
      "A system dialog will appear to request access to the containing directories.",
      to: &standardError
    )

    return await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = "File Access Permission Required"
        alert.informativeText = """
        r128x needs permission to access the audio files you specified via command line.

        Click 'Grant Access' to open a file selection dialog where you can grant permission to the required directories.

        Files to process:
        \(filePaths.map { "• " + URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n"))
        """
        alert.addButton(withTitle: "Grant Access")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
          // User chose to grant access
          self.showFileAccessDialog(for: Array(uniqueDirectories)) { success in
            continuation.resume(returning: success)
          }
        } else {
          // User cancelled
          continuation.resume(returning: false)
        }
      }
    }
    #else
    // Not on macOS, assume permission granted
    return true
    #endif
  }

  // MARK: Private

  // MARK: Private Properties

  /// URLs that have been granted security-scoped access for sandboxed operation
  private var grantedDirectoryURLs: [URL] = []

  // MARK: Private Implementation

  /// Check if we're running in an interactive terminal (not piped)
  private var isInteractiveTerminal: Bool {
    // Check if stdout is a tty (terminal) and not redirected/piped
    isatty(STDOUT_FILENO) != 0
  }

  #if canImport(AppKit)
  /// Show file access dialog using NSOpenPanel
  private func showFileAccessDialog(
    for directories: [String], completion: @escaping (Bool) -> Void
  ) {
    let openPanel = NSOpenPanel()
    openPanel.title = "Grant Access to Audio File Directories"
    openPanel.message =
      "Please select the directories containing your audio files to grant r128x access permission."
    openPanel.canChooseFiles = false
    openPanel.canChooseDirectories = true
    openPanel.allowsMultipleSelection = true
    openPanel.canCreateDirectories = false

    // Set the initial directory to the first directory if available
    if let firstDir = directories.first {
      openPanel.directoryURL = URL(fileURLWithPath: firstDir)
    }

    openPanel.begin { response in
      if response == .OK {
        // Store security-scoped bookmarks for the selected directories
        let selectedURLs = openPanel.urls
        var hasRequiredAccess = true

        // Check if all required directories are covered by the selected URLs
        for requiredDir in directories {
          let requiredURL = URL(fileURLWithPath: requiredDir)
          let hasAccess = selectedURLs.contains { selectedURL in
            requiredURL.path.hasPrefix(selectedURL.path)
          }
          if !hasAccess {
            hasRequiredAccess = false
            break
          }
        }

        if hasRequiredAccess {
          // Store the URLs for later use (they will have security-scoped access)
          self.grantedDirectoryURLs = selectedURLs
          completion(true)
        } else {
          // Show error that not all required directories were selected
          DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Incomplete Access"
            alert.informativeText =
              "Not all required directories were selected. Please grant access to all directories containing your audio files."
            alert.alertStyle = .warning
            alert.runModal()
            completion(false)
          }
        }
      } else {
        completion(false)
      }
    }
  }
  #endif

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
      let url = URL(fileURLWithPath: taskEntries[index].fileNamePath)

      // Start accessing security-scoped resource if we have granted access
      var accessing = false
      var grantedURL: URL?

      // Check if we have a granted directory URL that covers this file
      for directoryURL in grantedDirectoryURLs {
        if url.path.hasPrefix(directoryURL.path) {
          grantedURL = directoryURL
          accessing = directoryURL.startAccessingSecurityScopedResource()
          break
        }
      }

      // If no granted directory covers this file, try direct access
      if !accessing {
        accessing = url.startAccessingSecurityScopedResource()
      }

      defer {
        if accessing {
          if let grantedURL = grantedURL {
            grantedURL.stopAccessingSecurityScopedResource()
          } else {
            url.stopAccessingSecurityScopedResource()
          }
        }
      }

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
}

// MARK: - StandardError

private struct StandardError: TextOutputStream {
  mutating func write(_ string: String) {
    FileHandle.standardError.write(Data(string.utf8))
  }
}

@MainActor private var standardError = StandardError()
