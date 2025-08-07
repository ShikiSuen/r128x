// (c) (C ver. only) 2012-2013 Manuel Naudin (AGPL v3.0 License or later).
// (c) (this Swift implementation) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation

// MARK: - StatusForProcessing

public enum StatusForProcessing: String {
  case processing = "…"
  case succeeded = "✔︎"
  case failed = "✖︎"
}

// MARK: - IntelEntry

public struct IntelEntry: Identifiable, Equatable {
  // MARK: Lifecycle

  public init(fileName: String) {
    self.fileName = fileName
  }

  // MARK: Public

  public let id = UUID()
  public let fileName: String
  public var programLoudness: Double?
  public var loudnessRange: Double?
  public var dBTP: Double?
  public var status: StatusForProcessing = .processing
  public var progressPercentage: Double?
  public var estimatedTimeRemaining: TimeInterval?

  public var done: Bool {
    status == .succeeded || status == .failed
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

  public var progressDisplayed: String {
    guard status == .processing, let progressPercentage = progressPercentage else {
      return status == .succeeded ? "100%" : (status == .failed ? "Failed" : "Pending")
    }
    return String(format: "%.1f%%", progressPercentage)
  }

  public var timeRemainingDisplayed: String {
    guard status == .processing, let estimatedTimeRemaining = estimatedTimeRemaining else {
      return status == .succeeded ? "Done" : (status == .failed ? "Failed" : "Waiting")
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

  public mutating func process(forced: Bool = false) async {
    if status == .succeeded, !forced {
      return
    }

    status = .processing
    progressPercentage = 0.0
    estimatedTimeRemaining = nil
    do {
      let (il, lra, max_tp) = try await ExtAudioProcessor.processAudioFile(at: fileName, fileId: id.uuidString) { _ in
        // Could potentially update UI here with progress, but for now just process
        // The notification system will handle UI updates
      }
      programLoudness = il
      loudnessRange = lra
      dBTP = Double(max_tp)
      status = .succeeded
      progressPercentage = nil
      estimatedTimeRemaining = nil
    } catch {
      status = .failed
      progressPercentage = nil
      estimatedTimeRemaining = nil
      return
    }
  }
}
