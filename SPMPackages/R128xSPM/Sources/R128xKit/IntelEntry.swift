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

  public mutating func process(forced: Bool = false) {
    if status == .succeeded, !forced {
      return
    }

    status = .processing
    do {
      let (il, lra, max_tp) = try ExtAudioProcessor.processAudioFile(at: fileName)
      programLoudness = il
      loudnessRange = lra
      dBTP = Double(max_tp)
      status = .succeeded
    } catch {
      status = .failed
      return
    }
  }
}
