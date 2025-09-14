// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(Observation)
import Observation
#endif

// MARK: - TaskTrackingVMProtocol

@MainActor
public protocol TaskTrackingVMProtocol: AnyObject, Sendable {
  func sendProgress(_ update: ProgressUpdate)
}

// MARK: - TaskTrackingVM

@available(macOS 14.0, *)
@Observable @MainActor
public final class TaskTrackingVM: TaskTrackingVMProtocol {
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

  // MARK: - Public Properties

  /// Dictionary to track progress for multiple files
  public private(set) var fileProgress: [String: ProgressUpdate] = [:]

  /// The main progress stream
  public private(set) var progressStream: AsyncStream<ProgressUpdate>

  // MARK: - Public Methods

  /// Send a progress update through the stream
  public func sendProgress(_ update: ProgressUpdate) {
    // Always update the progress dictionary to maintain the latest state
    // This ensures that concurrent processing doesn't overwrite each other's progress
    fileProgress[update.fileId] = update
    streamContinuation?.yield(update)
  }

  /// Complete progress tracking for a file
  public func completeProgress(for fileId: String) {
    // Only remove from tracking if the file actually completed
    // This prevents premature removal during concurrent processing
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

  // MARK: Private

  /// Stream continuation for sending progress updates
  private var streamContinuation: AsyncStream<ProgressUpdate>.Continuation?
}

// MARK: - Singleton Access

@available(macOS 14.0, *)
extension TaskTrackingVM {
  /// Shared instance for global access
  public static let shared = TaskTrackingVM()
}
