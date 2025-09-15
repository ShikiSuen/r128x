// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

#if canImport(Darwin)
import Foundation

// MARK: - ProgressDebouncer

/// A specialized debouncer for progress updates that ensures the latest update is always processed
public actor ProgressDebouncer {
  // MARK: Lifecycle

  public init(delay: TimeInterval) {
    self.delay = delay
  }

  // MARK: Public

  /// Debounces progress updates while ensuring the latest data is always processed
  public func debounceProgress<T: Sendable>(
    _ data: T, action: @escaping @MainActor (T) async -> Void
  ) async {
    // Store the latest data
    latestData = data

    // If no task is running, start a new one
    if task == nil {
      task = Task { @MainActor [weak self] in
        guard let self else { return }

        // Wait for the debounce delay
        try await Task.sleep(nanoseconds: UInt64(self.delay * 1_000_000_000))

        // Get the latest data and process it
        let dataToProcess = await self.getLatestData() as? T
        if let dataToProcess = dataToProcess {
          await action(dataToProcess)
        }

        // Clear the task
        await self.clearTask()
      }
    }
    // If a task is already running, just update the latest data
    // The running task will pick up the latest data when it executes
  }

  // MARK: Private

  private var task: Task<Void, Error>?
  private var latestData: (any Sendable)?
  private let delay: TimeInterval

  private func getLatestData() -> (any Sendable)? {
    latestData
  }

  private func clearTask() {
    task = nil
    latestData = nil
  }
}
#endif
