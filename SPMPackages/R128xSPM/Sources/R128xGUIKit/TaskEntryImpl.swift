// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

#if canImport(Darwin)
import Foundation

import class ExtAudioProcessor.ExtAudioProcessor
import struct ExtAudioProcessor.TaskEntry
import class ExtAudioProcessor.TaskTrackingVM

// MARK: - TaskEntry

@available(macOS 14.0, *)
extension TaskEntry {
  @MainActor
  public mutating func process(forced: Bool = false, taskTrackingVM: TaskTrackingVM? = nil) async {
    if status == .succeeded, !forced {
      return
    }

    // Always set status to processing when we start
    status = .processing

    // Only preserve existing progress if not forced and we have valid progress data
    // This handles cases where processing was interrupted but should resume
    if !forced, progressPercentage != nil, progressPercentage! > 0 {
      // Keep existing progress, don't reset
      print("Resuming processing for \(fileName) from \(progressPercentage!)%")
    } else {
      // Fresh start or forced processing
      progressPercentage = 0.0
      estimatedTimeRemaining = nil
      currentLoudness = nil
    }

    // Start accessing security-scoped resource for file processing
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let measured = try await ExtAudioProcessor()
        .processAudioFile(
          at: url,
          fileId: id.uuidString,
          progressCallback: { @Sendable _ in
            // Could potentially update UI here with progress, but for now just process
            // The AsyncStream system will handle UI updates
          },
          taskTrackingVM: taskTrackingVM ?? TaskTrackingVM.shared
        )
      programLoudness = measured.integratedLoudness
      loudnessRange = measured.loudnessRange
      dBTP = Double(measured.maxTruePeak)
      previewStartAtTime = measured.previewStartAtTime
      previewLength = measured.previewLength
      status = .succeeded
      progressPercentage = nil
      estimatedTimeRemaining = nil
      currentLoudness = nil

      // Complete progress tracking
      taskTrackingVM?.completeProgress(for: id.uuidString)
    } catch {
      print("Error processing file \(fileName): \(error)")
      status = .failed
      progressPercentage = nil
      estimatedTimeRemaining = nil
      currentLoudness = nil

      // Complete progress tracking even on failure
      taskTrackingVM?.completeProgress(for: id.uuidString)
      return
    }
  }
}
#endif
