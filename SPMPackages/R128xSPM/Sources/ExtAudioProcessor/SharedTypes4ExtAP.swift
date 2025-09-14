// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

// MARK: - MeasuredResult

public struct MeasuredResult: Codable, Hashable, Sendable {
  // MARK: Lifecycle

  public init(
    integratedLoudness: Double,
    loudnessRange: Double,
    maxTruePeak: Double,
    previewStartAtTime: Double = 0,
    previewLength: Double = 0
  ) {
    self.integratedLoudness = integratedLoudness
    self.loudnessRange = loudnessRange
    self.maxTruePeak = maxTruePeak
    self.previewStartAtTime = previewStartAtTime
    self.previewLength = previewLength
  }

  // MARK: Public

  public let integratedLoudness: Double
  public let loudnessRange: Double
  public let maxTruePeak: Double
  public var previewStartAtTime: Double = 0
  public var previewLength: Double = 0
}

// MARK: - ProgressUpdate

/// Progress update structure for AsyncStream
public struct ProgressUpdate: Sendable, Equatable, Hashable {
  // MARK: Lifecycle

  public init(
    fileId: String,
    percentage: Double,
    framesProcessed: Int64,
    totalFrames: Int64,
    currentLoudness: Double? = nil,
    estimatedTimeRemaining: Double? = nil
  ) {
    self.fileId = fileId
    self.percentage = percentage
    self.framesProcessed = framesProcessed
    self.totalFrames = totalFrames
    self.currentLoudness = currentLoudness
    self.estimatedTimeRemaining = estimatedTimeRemaining
  }

  // MARK: Public

  public let fileId: String
  public let percentage: Double
  public let framesProcessed: Int64
  public let totalFrames: Int64
  public let currentLoudness: Double?
  public let estimatedTimeRemaining: Double?
}
