// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation

// MARK: - TaskEntry

public struct TaskEntry: Identifiable, Equatable, Sendable, Hashable {
  // MARK: Lifecycle

  public init(url: URL) {
    // 此处暂且默认传入的 URL 是文件 URL 而非资料夹 URL。
    self.url = url
  }

  // MARK: Public

  public enum StatusForProcessing: String, Sendable {
    case processing = "…"
    case succeeded = "✔︎"
    case failed = "✖︎"
  }

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

  public var fileNamePath: String {
    if #available(macOS 13.0, *) {
      url.path(percentEncoded: false)
    } else {
      url.path
    }
  }

  public var fileName: String {
    url.lastPathComponent
  }

  public var folderPath: String {
    if #available(macOS 13.0, *) {
      url.deletingLastPathComponent().path(percentEncoded: false)
    } else {
      url.deletingLastPathComponent().path
    }
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

  public var previewStartAtTimeDisplayed: String {
    guard let previewStartAtTime = previewStartAtTime else { return "N/A" }
    let totalSeconds = Int(previewStartAtTime)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = previewStartAtTime.truncatingRemainder(dividingBy: 60)

    if hours > 0 {
      return String(format: "%d:%02d:%06.3f", hours, minutes, seconds)
    } else {
      return String(format: "%d:%06.3f", minutes, seconds)
    }
  }

  public var previewStartAtTimeDisplayedShort: String {
    guard let previewStartAtTime = previewStartAtTime else { return "N/A" }
    let totalSeconds = Int(previewStartAtTime)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }

  public var previewLengthDisplayed: String {
    guard let previewLength = previewLength else { return "N/A" }
    return String(format: "%.3fs", previewLength)
  }

  public var previewRangeDisplayed: String {
    guard let start = previewStartAtTime, let length = previewLength else { return "N/A" }
    let end = start + length
    let startMinutes = Int(start) / 60
    let startSeconds = start.truncatingRemainder(dividingBy: 60)
    let endMinutes = Int(end) / 60
    let endSeconds = end.truncatingRemainder(dividingBy: 60)
    return String(
      format: "%d:%06.3f - %d:%06.3f", startMinutes, startSeconds, endMinutes, endSeconds
    )
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

  public var isDBTPPlaybackable: Bool {
    previewStartAtTime != nil && (previewLength ?? 0) > 0
  }
}
