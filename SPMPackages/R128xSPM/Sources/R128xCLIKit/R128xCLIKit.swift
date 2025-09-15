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

public actor CliController {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  public private(set) var taskEntries: [TaskEntry] = []

  // MARK: Main Entry Points

  /// Do not call this in unit tests.
  /// - Parameter mas: If true, only accepts `execName --cli file1 file2...` format (for MAS GUI apps)
  ///                  If false, accepts both `execName --cli file1...` and `execName file1...` formats
  public static func runMainAndExit(mas: Bool = false) async {
    // For MAS mode, we need to ensure the app is properly initialized
    if mas {
      // Give the app a moment to initialize its UI subsystem
      try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }

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
        writeToStandardError("[SDBOX] Requesting file access permission for MAS mode...\n")
        let filePaths = config.filePaths
        let grantedURLs = await MainActor.run {
          requestFileAccessPermission(for: filePaths)
        }
        writeDebugInfo("requestFileAccessPermission returned: \(grantedURLs != nil)")
        guard let urls = grantedURLs else {
          writeToStandardError("[SDBOX] Error: File access permission denied by user\n")
          return 1
        }

        // Store the granted URLs in the actor for security-scoped access
        setGrantedDirectoryURLs(urls)

        writeToStandardError(
          "[SDBOX] File access permission granted, proceeding with file processing...\n"
        )
        // Convert file paths to URLs
        let fileURLs = filePaths.map { URL(fileURLWithPath: $0) }
        return await processFiles(fileURLs: fileURLs)
      } else {
        return await processFiles(fileURLs: config.filePaths.map { URL(fileURLWithPath: $0) })
      }

    case let .failure(error):
      writeToStandardError("Error: \(error.localizedDescription)\n")
      return 1
    }
  }

  // MARK: File Processing

  public func processFiles(fileURLs: [URL]) async -> Int32 {
    let filePaths = fileURLs.map(\.pathGuarded)
    writeDebugInfo("processFiles called with \(filePaths.count) files: \(filePaths)")

    // Initialize task entries from file paths
    initializeTaskEntries(from: fileURLs)
    writeDebugInfo("Initialized \(taskEntries.count) task entries")

    // Print table header
    print("FILE\tIL (LUFS)\tLRA (LU)\tMAXTP (dBTP)")

    // Process each file and collect results
    var hasFailures = false

    for i in taskEntries.indices {
      writeDebugInfo("About to process task entry \(i)")
      await processTaskEntry(at: i)

      let entry = taskEntries[i]
      writeDebugInfo("Task entry \(i) processed with status: \(entry.status)")
      // TO Copilot: The App went dark since this line, and the app quits.
      print(formatResult(for: entry))

      if entry.status == .failed {
        hasFailures = true
      }
    }

    writeDebugInfo("All files processed, hasFailures: \(hasFailures)")
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
  /// Returns the granted directory URLs if permission granted, nil if denied
  @MainActor
  internal func requestFileAccessPermission(for filePaths: [String]) -> [URL]? {
    #if canImport(AppKit)
    // Check if we're in a sandbox environment
    let environment = ProcessInfo.processInfo.environment
    let isInSandbox =
      environment["APP_SANDBOX_CONTAINER_ID"] != nil
        || environment["TMPDIR"]?.contains("com.apple.containermanagerd") == true

    guard isInSandbox else {
      // Not sandboxed, no permission needed
      writeToStandardError("[SDBOX] Not in sandbox environment, no permission dialog needed.\n")
      return [] // Return empty array for non-sandboxed environment
    }

    // Group files by their parent directories to minimize dialog prompts
    let uniqueDirectories = Set(
      filePaths.compactMap { path in
        URL(fileURLWithPath: path).deletingLastPathComponent().path
      }
    )

    writeToStandardError("[SDBOX] Sandbox environment detected.\n")
    writeToStandardError("[SDBOX] This app needs permission to access the specified files.\n")
    writeToStandardError(
      "[SDBOX] A system dialog will appear to request access to the containing directories.\n"
    )

    // Show permission request alert
    let userWantsToGrantAccess = showPermissionAlert(for: filePaths)
    guard userWantsToGrantAccess else {
      writeToStandardError("[SDBOX] User cancelled permission request.\n")
      return nil
    }

    // Show file access dialog
    writeToStandardError("[SDBOX] User chose to grant access, showing file dialog...\n")
    let selectedURLs = showFileAccessDialog(for: Array(uniqueDirectories))

    guard let urls = selectedURLs else {
      writeToStandardError("[SDBOX] File dialog cancelled or failed\n")
      return nil
    }

    writeToStandardError(
      "[SDBOX] File dialog completed successfully with \(urls.count) directories\n"
    )
    return urls
    #else
    // Not on macOS, assume permission granted
    return []
    #endif
  }

  // MARK: Private

  /// Check if we're running in an interactive terminal (not piped)
  private static var isInteractiveTerminal: Bool {
    // Check if stdout is a tty (terminal) and not redirected/piped
    isatty(STDOUT_FILENO) != 0
  }

  // MARK: Private Properties

  /// URLs that have been granted security-scoped access for sandboxed operation
  private var grantedDirectoryURLs: [URL] = []

  // Actor method to safely set granted directory URLs
  private func setGrantedDirectoryURLs(_ urls: [URL]) {
    grantedDirectoryURLs = urls
  }

  // MARK: Private Implementation

  #if canImport(AppKit)
  /// Show permission request alert
  @MainActor
  private func showPermissionAlert(for filePaths: [String]) -> Bool {
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
    return response == .alertFirstButtonReturn
  }

  /// Show file access dialog using NSOpenPanel
  @MainActor
  private func showFileAccessDialog(for directories: [String]) -> [URL]? {
    writeToStandardError("[SDBOX] Showing file access dialog for directories: \(directories)\n")
    writeDebugInfo("About to create NSOpenPanel")

    writeDebugInfo("NSOpenPanel created successfully")
    openPanel.title = "Grant Access to Audio File Directories"
    openPanel.message =
      "Please select the directories containing your audio files to grant r128x access permission."
    openPanel.canChooseFiles = false
    openPanel.canChooseDirectories = true
    openPanel.allowsMultipleSelection = true
    openPanel.canCreateDirectories = false

    writeDebugInfo("NSOpenPanel configured")

    // Set the initial directory to the first directory if available
    if let firstDir = directories.first {
      openPanel.directoryURL = URL(fileURLWithPath: firstDir)
      writeToStandardError("[SDBOX] Setting initial directory to: \(firstDir)\n")
    }

    writeDebugInfo("About to call runModal()")
    let response = openPanel.runModal()
    writeDebugInfo("runModal() returned with response: \(response.rawValue)")

    if response == .OK {
      writeToStandardError("[SDBOX] User selected OK, processing selected URLs...\n")

      // Store security-scoped bookmarks for the selected directories
      let selectedURLs = openPanel.urls
      writeToStandardError("[SDBOX] Selected URLs: \(selectedURLs)\n")

      var hasRequiredAccess = true

      // Check if all required directories are covered by the selected URLs
      for requiredDir in directories {
        let requiredURL = URL(fileURLWithPath: requiredDir)
        let hasAccess = selectedURLs.contains { selectedURL in
          requiredURL.pathGuarded.hasPrefix(selectedURL.pathGuarded + "/")
            || requiredURL.pathGuarded == selectedURL.pathGuarded
        }
        writeToStandardError("[SDBOX] Directory \(requiredDir) has access: \(hasAccess)\n")
        if !hasAccess {
          hasRequiredAccess = false
          break
        }
      }

      if hasRequiredAccess {
        // Return the URLs for the caller to store
        writeToStandardError("[SDBOX] Access granted to \(selectedURLs.count) directories.\n")
        return selectedURLs
      } else {
        writeToStandardError("[SDBOX] Not all required directories were selected.\n")
        // Show error that not all required directories were selected
        let alert = NSAlert()
        alert.messageText = "Incomplete Access"
        alert.informativeText =
          "Not all required directories were selected. Please grant access to all directories containing your audio files."
        alert.alertStyle = .warning
        alert.runModal()
        return nil
      }
    } else {
      writeToStandardError("[SDBOX] User cancelled file selection dialog.\n")
      return nil
    }
  }
  #endif

  private func initializeTaskEntries(from urls: [URL]) {
    taskEntries = urls.compactMap { url in
      TaskEntry(url: url)
    }
  }

  private func processTaskEntry(at index: Int) async {
    writeDebugInfo("Starting to process entry \(index): \(taskEntries[index].fileName)")

    // Update status to processing
    taskEntries[index].status = .processing

    do {
      writeDebugInfo("Creating ExtAudioProcessor")
      let processor = ExtAudioProcessor()
      let url = URL(fileURLWithPath: taskEntries[index].fileNamePath)
      writeDebugInfo("Processing file at path: \(taskEntries[index].fileNamePath)")

      // Start accessing security-scoped resource if we have granted access
      var accessing = false
      var grantedURL: URL?

      writeDebugInfo("Checking granted directory URLs: \(grantedDirectoryURLs)")

      // Check if we have a granted directory URL that covers this file
      for directoryURL in grantedDirectoryURLs {
        writeDebugInfo("Checking if \(url.pathGuarded) starts with \(directoryURL.pathGuarded)")
        // Fix path matching by ensuring both paths are properly normalized
        let filePath = url.pathGuarded
        var directoryPath = directoryURL.pathGuarded

        // Ensure directory path ends with a single slash
        if !directoryPath.hasSuffix("/") {
          directoryPath += "/"
        }

        writeDebugInfo("Normalized paths - file: '\(filePath)', directory: '\(directoryPath)'")

        if filePath.hasPrefix(directoryPath) || filePath == directoryPath.dropLast() {
          grantedURL = directoryURL
          writeDebugInfo(
            "Path match found! Starting security-scoped resource access for \(directoryURL)"
          )
          accessing = directoryURL.startAccessingSecurityScopedResource()
          writeDebugInfo("Security-scoped access result: \(accessing)")
          break
        } else {
          writeDebugInfo("No path match: '\(filePath)' does not start with '\(directoryPath)'")
        }
      }

      // If no granted directory covers this file, try direct access
      if !accessing {
        writeDebugInfo("No granted directory covers file, trying direct access")
        accessing = url.startAccessingSecurityScopedResource()
        writeDebugInfo("Direct access result: \(accessing)")
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

      writeDebugInfo("About to call processor.processAudioFile")
      writeDebugInfo("File URL: \(taskEntries[index].url)")
      writeDebugInfo("File path: \(taskEntries[index].url.path)")
      writeDebugInfo(
        "File exists: \(FileManager.default.fileExists(atPath: taskEntries[index].url.path))"
      )

      // Check file attributes
      do {
        let attributes = try FileManager.default.attributesOfItem(
          atPath: taskEntries[index].url.path
        )
        writeDebugInfo("File size: \(attributes[.size] ?? "unknown")")
        writeDebugInfo(
          "File permissions: \(String(format: "%o", (attributes[.posixPermissions] as? NSNumber)?.uintValue ?? 0))"
        )
      } catch {
        writeDebugInfo("Could not read file attributes: \(error)")
      }

      // Test if we can actually read the file data
      do {
        let data = try Data(contentsOf: taskEntries[index].url, options: [.mappedIfSafe])
        writeDebugInfo("Successfully read \(data.count) bytes from file")
      } catch {
        writeDebugInfo("Failed to read file data: \(error)")
      }

      let result = try await processor.processAudioFile(
        at: taskEntries[index].url,
        fileId: taskEntries[index].id.uuidString,
        progressCallback: progressCallback
      )
      #if DEBUG
      writeToStandardError("\n")
      #endif
      writeDebugInfo("Audio processing completed successfully")

      // Clear progress line and update with results
      await MainActor.run {
        clearProgressLine()
      }

      taskEntries[index].programLoudness = result.integratedLoudness
      taskEntries[index].loudnessRange = result.loudnessRange
      taskEntries[index].dBTP = result.maxTruePeak
      taskEntries[index].previewStartAtTime = result.previewStartAtTime
      taskEntries[index].previewLength = result.previewLength
      taskEntries[index].status = .succeeded
      taskEntries[index].progressPercentage = nil

    } catch {
      await MainActor.run {
        clearProgressLine()
      }
      taskEntries[index].status = .failed
      taskEntries[index].progressPercentage = nil

      // Print detailed error information
      let fileName = taskEntries[index].fileName
      if let nsError = error as NSError? {
        writeToStandardError(
          "Error processing \(fileName): \(nsError.localizedDescription)\n"
        )
        if let recoverySuggestion = nsError.localizedRecoverySuggestion {
          writeToStandardError("  \(recoverySuggestion)\n")
        }
      } else {
        writeToStandardError(
          "Error processing \(fileName): \(error.localizedDescription)\n"
        )
      }
    }
  }

  @Sendable
  nonisolated private func progressCallback(
    _ progress: ExtAudioProcessor.ProcessingProgress
  ) async {
    // Simplified progress handling for CLI with debug info
    guard let fileId = progress.fileId, let fileUUID = UUID(uuidString: fileId) else {
      writeDebugInfo(
        "File ID missing for this callback, aborting callback process.\n"
      )
      return
    }
    let matchedTask = await taskEntries.first {
      $0.id == fileUUID
    }
    guard let matchedTask else {
      writeDebugInfo(
        "No task matched for this callback, aborting callback process.\n"
      )
      return
    }

    let fileName = matchedTask.fileName // Capture the filename
    // writeDebugInfo("Progress callback started :") // Disable this line for now.

    // Only show progress bar in interactive terminals, not when piped
    guard isatty(STDOUT_FILENO) != 0 else {
      writeDebugInfo(
        "Skipping progress bar (not interactive terminal)\n"
      )
      return
    }

    let percentage = Int(floor(progress.percentage))
    let totalWidth = 30
    let filledWidth = Int(Double(totalWidth) * progress.percentage / 100.0)
    let emptyWidth = totalWidth - filledWidth

    let filledPart = String(repeating: "=", count: filledWidth)
    let emptyPart = String(repeating: "-", count: emptyWidth)
    let progressBar = filledPart + emptyPart

    // Use stderr for progress to avoid interfering with stdout output
    writeToStandardError(
      String(format: "\r[%@] %3d%% - %@", progressBar, percentage, fileName)
    )
  }

  @MainActor
  private func clearProgressLine() {
    // Only clear progress line in interactive terminals
    guard Self.isInteractiveTerminal else { return }

    // Use stderr to clear the progress line
    writeToStandardError("\r" + String(repeating: " ", count: 80) + "\r")
  }

  private func displayProgress(
    _ progress: ExtAudioProcessor.ProcessingProgress,
    for fileName: String
  ) {
    // Only show progress bar in interactive terminals, not when piped
    guard Self.isInteractiveTerminal else { return }

    let percentage = Int(floor(progress.percentage))
    let totalWidth = 30
    let filledWidth = Int(Double(totalWidth) * progress.percentage / 100.0)
    let emptyWidth = totalWidth - filledWidth

    let filledPart = String(repeating: "=", count: filledWidth)
    let emptyPart = String(repeating: "-", count: emptyWidth)
    let progressBar = filledPart + emptyPart

    // Use stderr for progress to avoid interfering with stdout output
    writeToStandardError(
      String(format: "\r[%@] %3d%% - %@", progressBar, percentage, fileName)
    )
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

// MARK: - Console Print APIs

// Helper function for Actor to write to stderr safely
private func writeToStandardError(_ message: String) {
  FileHandle.standardError.write(Data(message.utf8))
}

/// Write debug information to standard error, only active in DEBUG builds
private func writeDebugInfo(_ message: String) {
  #if DEBUG
  FileHandle.standardError.write(Data("[DEBUG] \(message)\n".utf8))
  #endif
}

// MARK: - URL Path APIs

extension URL {
  fileprivate var pathGuarded: String {
    #if canImport(Darwin)
    if #available(macOS 13.0, *) {
      path(percentEncoded: false)
    } else {
      path
    }
    #else
    path(percentEncoded: false)
    #endif
  }
}

// MARK: - Shared NSOpenPanel Instance

@MainActor private let openPanel = NSOpenPanel()
