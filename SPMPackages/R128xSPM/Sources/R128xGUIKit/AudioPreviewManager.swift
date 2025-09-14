// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation

import struct ExtAudioProcessor.TaskEntry

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - AudioPreviewManager

/// Manages audio preview playback functionality with security-scoped resource management
@available(macOS 14.0, *)
@MainActor
@Observable
public final class AudioPreviewManager {
  // MARK: Lifecycle

  public init() {}

  deinit {
    // Cleanup will be handled by stopPreview() when needed
  }

  // MARK: Public

  // MARK: - Public Properties

  /// Currently previewing task ID, nil if no preview is active
  public private(set) var currentPreviewingTaskId: UUID?

  /// Whether audio is currently playing
  public private(set) var isPlaying: Bool = false

  // MARK: - Public Methods

  /// Start preview for a given task entry
  /// - Parameter entry: The task entry to preview
  public func startPreview(for entry: TaskEntry) {
    // Stop any existing preview first
    stopPreview()

    // Check if preview data is available
    guard let previewStartTime = entry.previewStartAtTime,
          let previewLength = entry.previewLength,
          previewLength > 0
    else {
      print("Preview data not available for entry: \(entry.fileName)")
      return
    }

    currentPreviewingTaskId = entry.id

    #if canImport(AVFoundation)
    // Use AVFoundation as primary method for iOS and macOS
    Task {
      await playUsingAVFoundation(
        url: entry.url,
        startTime: previewStartTime,
        duration: previewLength
      )
    }
    #else
    // Fallback for platforms without AVFoundation (e.g., Linux)
    Task {
      await playAudioUsingSystemCommand(
        url: entry.url,
        startTime: previewStartTime,
        duration: previewLength
      )
    }
    #endif
  }

  /// Stop the current preview
  public func stopPreview() {
    #if canImport(AVFoundation)
    audioPlayer?.stop()
    audioPlayer = nil
    stopTimer?.invalidate()
    stopTimer = nil
    #endif

    // Stop any system command-based playback (only for non-AVFoundation platforms)
    #if !canImport(AVFoundation)
    stopSystemCommandPlayback()
    #endif

    isPlaying = false
    currentPreviewingTaskId = nil

    // Clean up security-scoped resource access
    cleanupSecurityScopedAccess()
  }

  /// Check if a specific task is currently being previewed
  /// - Parameter taskId: The task ID to check
  /// - Returns: True if the task is currently being previewed
  public func isPreviewingTask(id taskId: UUID) -> Bool {
    currentPreviewingTaskId == taskId && isPlaying
  }

  // MARK: Private

  // MARK: - Private Properties

  #if canImport(AVFoundation)
  private var audioPlayer: AVAudioPlayer?
  private var stopTimer: Timer?
  #endif

  /// URL currently being accessed with security scope
  private var currentSecurityScopedURL: URL?

  /// Whether we're currently accessing a security-scoped resource
  private var isAccessingSecurityScopedResource: Bool = false

  // MARK: - Private Methods

  #if !canImport(AVFoundation)
  /// Play audio using system commands for platforms without AVFoundation (Linux only)
  private func playAudioUsingSystemCommand(url: URL, startTime: Double, duration: Double) async {
    // Start accessing security-scoped resource
    let accessing = url.startAccessingSecurityScopedResource()
    currentSecurityScopedURL = url
    isAccessingSecurityScopedResource = accessing

    isPlaying = true

    #if os(Linux)
    // Use ffplay on Linux
    let command = buildFfplayCommand(url: url, startTime: startTime, duration: duration)
    await executeSystemCommand(command)
    #else
    print("Audio preview not supported on this platform without AVFoundation")
    #endif

    // Playback finished
    await MainActor.run {
      self.isPlaying = false
      self.currentPreviewingTaskId = nil
      self.cleanupSecurityScopedAccess()
    }
  }

  #if os(Linux)
  private func buildFfplayCommand(url: URL, startTime: Double, duration: Double) -> String {
    let path = url.path(percentEncoded: false)
    let escapedPath = path.replacingOccurrences(of: "'", with: "'\"'\"'")
    return "ffplay -ss \(startTime) -t \(duration) -autoexit -nodisp '\(escapedPath)'"
  }
  #endif

  private func executeSystemCommand(_ command: String) async {
    await withCheckedContinuation { continuation in
      let task = Process()
      task.launchPath = "/bin/sh"
      task.arguments = ["-c", command]

      task.terminationHandler = { _ in
        continuation.resume()
      }

      do {
        try task.run()
      } catch {
        print("Failed to execute audio preview command: \(error)")
        continuation.resume()
      }
    }
  }

  private func stopSystemCommandPlayback() {
    #if os(Linux)
    let killCommand = "pkill -f ffplay"
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", killCommand]

    do {
      try task.run()
    } catch {
      // Ignore errors when killing processes
    }
    #endif
  }
  #endif

  #if canImport(AVFoundation)
  private func playUsingAVFoundation(url: URL, startTime: Double, duration: Double) async {
    // Start accessing security-scoped resource
    let accessing = url.startAccessingSecurityScopedResource()
    currentSecurityScopedURL = url
    isAccessingSecurityScopedResource = accessing

    isPlaying = true

    do {
      // Setup audio session for playback (important for iOS)
      #if os(iOS)
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default)
      try audioSession.setActive(true)
      #endif

      let player = try AVAudioPlayer(contentsOf: url)
      audioPlayer = player

      // Prepare the player
      player.prepareToPlay()

      // Set the start time (if the audio supports it)
      if startTime > 0, startTime < player.duration {
        player.currentTime = startTime
      }

      // Start playing
      let success = player.play()

      if success {
        // Schedule stop after duration using Timer for better precision
        stopTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {
          [weak self] _ in
          Task { @MainActor in
            self?.audioPlayer?.stop()
            self?.isPlaying = false
            self?.currentPreviewingTaskId = nil
            self?.cleanupSecurityScopedAccess()
            self?.stopTimer = nil
          }
        }
      } else {
        // Failed to start playback
        await MainActor.run {
          self.isPlaying = false
          self.currentPreviewingTaskId = nil
          self.cleanupSecurityScopedAccess()
        }
      }

    } catch {
      print("Failed to play audio using AVFoundation: \(error)")
      await MainActor.run {
        self.isPlaying = false
        self.currentPreviewingTaskId = nil
        self.cleanupSecurityScopedAccess()
      }
    }
  }
  #endif

  private func cleanupSecurityScopedAccess() {
    if isAccessingSecurityScopedResource,
       let url = currentSecurityScopedURL {
      url.stopAccessingSecurityScopedResource()
    }

    currentSecurityScopedURL = nil
    isAccessingSecurityScopedResource = false
  }
}

// MARK: - Singleton Access

@available(macOS 14.0, *)
extension AudioPreviewManager {
  /// Shared instance for global access
  public static let shared = AudioPreviewManager()
}
