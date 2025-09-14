// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation

extension TimeInterval {
  func formatted() -> String {
    let minutes = Int(self) / 60
    let seconds = Int(self) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}

// MARK: - StatusForProcessing

public enum StatusForProcessing: String, Sendable {
  case processing = "…"
  case succeeded = "✔︎"
  case failed = "✖︎"
}

// MARK: - TaskEntry

public struct TaskEntry: Identifiable, Equatable, Sendable, Hashable {
  // MARK: Lifecycle

  public init(url: URL) {
    // 此处暂且默认传入的 URL 是文件 URL 而非资料夹 URL。
    self.url = url
  }

  // MARK: Public

  public let id = UUID()
  public let url: URL
  public var programLoudness: Double?
  public var loudnessRange: Double?
  public var dBTP: Double?
  public var previewStartAtTime: Double?
  public var previewLength: Double?
  public var status: StatusForProcessing = .processing
  public var progressPercentage: Double?
  public var estimatedTimeRemaining: TimeInterval?
  public var currentLoudness: Double?

  public var fileNamePath: String { url.path(percentEncoded: false) }

  public var fileName: String {
    url.lastPathComponent
  }

  public var folderPath: String {
    url.deletingLastPathComponent().path(percentEncoded: false)
  }

  public var done: Bool {
    status == .succeeded || status == .failed
  }

  public var isResultInvalid: Bool {
    [programLoudness, loudnessRange, dBTP, previewStartAtTime, previewLength]
      .allSatisfy { $0 == nil } && status != .processing
  }

  public var statusDisplayed: String { status.rawValue }
  public var programLoudnessDisplayed: String { programLoudness?.description ?? "N/A" }
  public var loudnessRangeDisplayed: String {
    guard let loudnessRange = loudnessRange else { return "N/A" }
    let format = "%.\(2)f"
    return String(format: format, loudnessRange)
  }

  public var dBTPDisplayed: String {
    guard let dBTP = dBTP else { return "N/A" }
    let format = "%.\(2)f"
    return String(format: format, dBTP)
  }

  public var guardedProgressValue: Double? {
    guard status == .processing, let progressPercentage = progressPercentage else {
      return status == .succeeded ? 1 : (status == .failed ? 0 : nil)
    }
    return Swift.max(0, Swift.min(1, progressPercentage / 100))
  }

  public var progressDisplayed: String {
    guard status == .processing, let progressPercentage = progressPercentage else {
      return status == .succeeded ? "100%" : (status == .failed ? "⚠︎" : "…")
    }
    return String(format: "%.1f%%", progressPercentage)
  }

  public var timeRemainingDisplayed: String {
    guard status == .processing, let estimatedTimeRemaining = estimatedTimeRemaining else {
      return status == .succeeded ? "✅" : (status == .failed ? "❌" : "…")
    }
    if estimatedTimeRemaining < 1 {
      return "< 1s"
    } else if estimatedTimeRemaining < 60 {
      return String(format: "%.0fs", estimatedTimeRemaining)
    } else {
      let minutes = Int(estimatedTimeRemaining) / 60
      let seconds = Int(estimatedTimeRemaining) % 60
      return String(format: "%d:%02ds", minutes, seconds)
    }
  }

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
          at: fileNamePath,
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
