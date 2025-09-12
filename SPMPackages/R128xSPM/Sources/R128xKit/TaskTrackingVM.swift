// (c) (C ver. only) 2012-2013 Manuel Naudin (AGPL v3.0 License or later).
// (c) (this Swift implementation) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(Observation)
import Observation
#endif

// MARK: - ProgressUpdate

/// Progress update structure for AsyncStream
public struct ProgressUpdate: Sendable, Equatable {
  // MARK: Lifecycle

  public init(
    fileId: String,
    percentage: Double,
    framesProcessed: Int64,
    totalFrames: Int64,
    currentLoudness: Double? = nil,
    estimatedTimeRemaining: TimeInterval? = nil
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
  public let estimatedTimeRemaining: TimeInterval?
}

// MARK: - TaskTrackingVM

/// Observable progress view model using AsyncStream
#if canImport(Observation) && !os(Linux)
@Observable @MainActor
#else
@MainActor
#endif

// MARK: - TaskTrackingVM

public final class TaskTrackingVM: Sendable {
  // MARK: Lifecycle

  // MARK: - Initialization

  public init() {
    let (stream, continuation) = AsyncStream<ProgressUpdate>.makeStream()
    self.progressStream = stream
    self.streamContinuation = continuation

    continuation.onTermination = { @Sendable _ in
      // Clean up when stream terminates
    }
  }

  deinit {
    // We use a singleton here, hence no need of deinit().
    // streamContinuation?.finish()
  }

  // MARK: Public

  // MARK: - Public Methods

  /// Send a progress update through the stream
  public func sendProgress(_ update: ProgressUpdate) {
    fileProgress[update.fileId] = update
    streamContinuation?.yield(update)
  }

  /// Complete progress tracking for a file
  public func completeProgress(for fileId: String) {
    fileProgress.removeValue(forKey: fileId)
  }

  /// Start observing the progress stream
  public func startObserving() -> Task<Void, Never> {
    Task { @MainActor in
      for await _ in progressStream {
        // Progress updates are automatically handled by @Observable
        // The UI will automatically react to fileProgress changes
      }
    }
  }

  /// Get progress for a specific file
  public func progress(for fileId: String) -> ProgressUpdate? {
    fileProgress[fileId]
  }

  /// Clear all progress data
  public func clearAllProgress() {
    fileProgress.removeAll()
  }

  // MARK: Internal

  // MARK: - Public Properties

  /// Dictionary to track progress for multiple files
  private(set) var fileProgress: [String: ProgressUpdate] = [:]

  /// The main progress stream
  private(set) var progressStream: AsyncStream<ProgressUpdate>

  // MARK: Private

  /// Stream continuation for sending progress updates
  private var streamContinuation: AsyncStream<ProgressUpdate>.Continuation?
}

// MARK: - Singleton Access

extension TaskTrackingVM {
  /// Shared instance for global access
  public static let shared = TaskTrackingVM()
}
