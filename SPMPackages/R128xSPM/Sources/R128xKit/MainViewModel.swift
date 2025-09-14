// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// MARK: - MainViewModel

@MainActor
@Observable
public final class MainViewModel {
  // MARK: Public

  // Static properties moved here to avoid main actor isolation issues
  public static let allowedSuffixes: [String] = [
    "mov",
    "mp4",
    "mp3",
    "mp2",
    "m4a",
    "wav",
    "aif",
    "ogg",
    "aiff",
    "caf",
    "alac",
    "sd2",
    "ac3",
    "flac",
  ]

  public static let allowedUTTypes: [UTType] = allowedSuffixes.compactMap {
    .init(filenameExtension: $0)
  }

  public var entries: [TaskEntry] = []
  public var dragOver = false
  public var highlighted: TaskEntry.ID?
  public var searchText: String = ""
  @ObservationIgnored public let progressDebouncer: ProgressDebouncer = .init(delay: 0.1)
  @ObservationIgnored public var currentTask: Task<Void, Never>?

  public let taskTrackingVM = TaskTrackingVM.shared
  public let audioPreviewManager = AudioPreviewManager.shared

  public var filteredEntries: [TaskEntry] {
    if searchText.isEmpty {
      return entries
    }
    let searchLowercase = searchText.lowercased()
    return entries.filter { entry in
      entry.fileNamePath.lowercased().contains(searchLowercase)
    }
  }

  public var progressValue: CGFloat {
    if entries.isEmpty { return 0 }

    // Filter out entries with invalid results
    let validEntries = entries.filter { $0.status != .failed }

    if validEntries.isEmpty { return 0 }

    let totalProgress = validEntries.compactMap(\.guardedProgressValue).reduce(0, +)
    return CGFloat(totalProgress) / CGFloat(validEntries.count)
  }

  public var queueMessage: String {
    if entries.isEmpty {
      return "queueMsg.blankQueueStandBy".i18n
    }
    let filesPendingProcessing: Int = entries.filter(\.done.negative).count
    let invalidResults: Int = entries.reduce(0) { $0 + ($1.status == .failed ? 1 : 0) }

    // Show detailed progress if we have any processing files
    if filesPendingProcessing > 0 {
      let processingEntries = entries.filter { $0.status == .processing }

      // Find the entry with the longest estimated time remaining
      let longestRemainingEntry = processingEntries.max { entry1, entry2 in
        let time1 = entry1.estimatedTimeRemaining ?? 0
        let time2 = entry2.estimatedTimeRemaining ?? 0
        return time1 < time2
      }

      if let longestEntry = longestRemainingEntry,
         let estimatedTime = longestEntry.estimatedTimeRemaining {
        let remaining = estimatedTime.formatted()
        return String(
          format: "queueMsg.workingRemaining:%d%@".i18n,
          filesPendingProcessing,
          remaining
        )
      } else {
        return String(
          format: "queueMsg.workingRemaining:%d".i18n, filesPendingProcessing
        )
      }
    }

    guard invalidResults == 0 else {
      return String(
        format: "queueMsg.allDoneExcept:%d".i18n, invalidResults
      )
    }
    return "queueMsg.allDone".i18n
  }

  // MARK: - Methods

  public func getEntry(uuid: UUID?) -> TaskEntry? {
    guard let uuid else { return nil }
    return entries.first { $0.id == uuid }
  }

  public func batchProcess(forced: Bool = false) {
    // When forced = true, reset processing state for ALL entries
    if forced {
      // Cancel any existing task only for forced processing
      currentTask?.cancel()

      for i in 0 ..< entries.count {
        entries[i].status = .processing
        // Reset progress data only when forced
        entries[i].progressPercentage = nil
        entries[i].estimatedTimeRemaining = nil
        entries[i].currentLoudness = nil
      }
    } else {
      // For non-forced processing, DON'T cancel existing tasks to avoid interrupting ongoing processes
      // Only set status for entries that need processing
      for i in 0 ..< entries.count {
        let entry = entries[i]
        // Only set to processing if it's a new entry that hasn't been processed yet
        if entry.status != .processing, entry.status != .succeeded {
          entries[i].status = .processing
          // Don't reset progress data for existing entries
        }
      }

      // Check if there are any files that need processing
      let hasFilesToProcess = entries.contains { entry in
        (entry.status == .processing && entry.progressPercentage == nil) || entry.status == .failed
      }

      guard hasFilesToProcess else {
        // No files need processing, exit early
        return
      }
    }

    // Create a new task that properly handles main actor isolation
    let newTask = Task { @MainActor [weak self] in
      // Add debounce delay
      try? await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds

      guard let self = self, !Task.isCancelled else { return }

      // Create a copy of entry data for concurrent processing, only for entries that need processing
      let entrySnapshots = self.entries.enumerated().compactMap {
        index, entry -> (index: Int, entry: TaskEntry)? in

        if forced {
          // For forced processing, process all entries
          return (index: index, entry: entry)
        } else {
          // For regular processing, only process entries that actually need processing
          // Skip entries that are already completed successfully
          guard entry.status != .succeeded else { return nil }

          // Only skip entries that are actively being processed by a different task
          // If we don't have a current task or it's cancelled, we should process this entry
          if entry.status == .processing,
             entry.progressPercentage != nil,
             let currentTask = self.currentTask,
             !currentTask.isCancelled {
            return nil
          }

          return (index: index, entry: entry)
        }
      }

      guard !entrySnapshots.isEmpty else { return }

      // Process entries concurrently with proper isolation
      await withTaskGroup(of: (Int, TaskEntry)?.self) { group in
        for snapshot in entrySnapshots {
          group.addTask {
            guard !Task.isCancelled else { return nil }

            var entry = snapshot.entry
            await entry.process(forced: forced, taskTrackingVM: self.taskTrackingVM)
            return (snapshot.index, entry)
          }
        }

        // Collect results back to main actor
        for await result in group {
          guard let (index, updatedEntry) = result,
                index < self.entries.count,
                !Task.isCancelled
          else { continue }

          self.entries[index] = updatedEntry
        }
      }
    }

    // Only update currentTask if we're not already processing or if forced
    if forced || currentTask == nil || currentTask?.isCancelled == true {
      currentTask = newTask
    }
  }

  public func handleDrop(_ providers: [NSItemProvider]) -> Bool {
    Task { @MainActor in
      var counter = 0
      let allowedSuffixes = Self.allowedSuffixes
      let currentEntries = entries
      var allEntriesPaths = Set(currentEntries.map(\.fileNamePath)) // Use a Set for faster lookups

      for provider in providers {
        if let url = await withCheckedContinuation({ continuation in
          _ = provider.loadObject(ofClass: URL.self) { url, _ in
            continuation.resume(returning: url)
          }
        }) {
          // Start accessing security-scoped resource for drag-and-drop
          let accessing = url.startAccessingSecurityScopedResource()
          defer {
            if accessing {
              url.stopAccessingSecurityScopedResource()
            }
          }

          var isDirectory: ObjCBool = false
          let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false), isDirectory: &isDirectory
          )
          guard exists else { continue }

          if isDirectory.boolValue {
            // Handle folder drop - recursively enumerate audio files
            let audioFiles = recursivelyEnumerateAudioFiles(
              in: url, allowedSuffixes: allowedSuffixes
            )
            for audioFile in audioFiles {
              let path = audioFile.path(percentEncoded: false)
              guard !allEntriesPaths.contains(path) else { continue }
              counter += 1
              entries.append(.init(url: audioFile))
              allEntriesPaths.insert(path) // Track newly added paths
            }
          } else {
            // Handle individual file drop
            let path = url.path(percentEncoded: false)
            guard !allEntriesPaths.contains(path) else { continue }

            for fileExtension in allowedSuffixes {
              guard path.hasSuffix(".\(fileExtension)") else { continue }
              counter += 1
              entries.append(.init(url: url))
              allEntriesPaths.insert(path) // Track newly added paths
              break
            }
          }
        }
      }

      if counter > 0 {
        batchProcess(forced: false)
      }
    }
    return true
  }

  public func addFiles(urls: [URL]) {
    let entriesAsPaths: [String] = entries.map(\.fileNamePath)
    var newEntries: [TaskEntry] = []
    var allEntriesPaths = Set(entriesAsPaths) // Use a Set for faster lookups

    for url in urls {
      guard !allEntriesPaths.contains(url.path(percentEncoded: false)) else { continue }

      // Start accessing security-scoped resource for file importer and shared files
      let accessing = url.startAccessingSecurityScopedResource()
      defer {
        if accessing {
          url.stopAccessingSecurityScopedResource()
        }
      }

      var isDirectory: ObjCBool = false
      let exists = FileManager.default.fileExists(
        atPath: url.path(percentEncoded: false), isDirectory: &isDirectory
      )
      guard exists else { continue }

      if isDirectory.boolValue {
        // Handle folder - recursively enumerate audio files
        let audioFiles = recursivelyEnumerateAudioFiles(
          in: url, allowedSuffixes: Self.allowedSuffixes
        )
        for audioFile in audioFiles {
          guard !allEntriesPaths.contains(audioFile.path(percentEncoded: false)) else { continue }
          newEntries.append(TaskEntry(url: audioFile))
          allEntriesPaths.insert(audioFile.path(percentEncoded: false)) // Track newly added paths
        }
      } else {
        // Handle individual file
        newEntries.append(TaskEntry(url: url))
        allEntriesPaths.insert(url.path(percentEncoded: false)) // Track newly added paths
      }
    }

    guard !newEntries.isEmpty else { return }

    entries.append(contentsOf: newEntries)

    // Only trigger batch processing when new files are actually added
    batchProcess(forced: false)
  }

  public func clearEntries() {
    entries.removeAll()
  }

  public func removeEntry(id: UUID) {
    // Stop preview if this entry is currently being previewed
    if audioPreviewManager.isPreviewingTask(id: id) {
      audioPreviewManager.stopPreview()
    }

    entries.removeAll {
      $0.id == id
    }
  }

  // MARK: - Audio Preview Methods

  /// Start audio preview for a given entry
  public func startPreview(for entry: TaskEntry) {
    // Only start preview if the entry has valid preview data
    guard entry.previewStartAtTime != nil,
          entry.previewLength != nil,
          entry.previewLength! > 0
    else {
      print("Cannot preview entry \(entry.fileName): No preview data available")
      return
    }

    audioPreviewManager.startPreview(for: entry)
  }

  /// Stop the current audio preview
  public func stopPreview() {
    audioPreviewManager.stopPreview()
  }

  /// Check if a specific task is currently being previewed
  public func isPreviewingTask(id: UUID) -> Bool {
    audioPreviewManager.isPreviewingTask(id: id)
  }

  public func updateProgress(_ newProgress: [String: ProgressUpdate]) {
    for (fileId, progressUpdate) in newProgress {
      if let entryIndex = entries.firstIndex(where: { $0.id.uuidString == fileId }) {
        // Only update if the entry is still in processing state to avoid unnecessary updates
        guard entries[entryIndex].status == .processing else { continue }

        // Ensure progress is monotonically increasing to avoid jumping backwards
        let currentProgress = entries[entryIndex].progressPercentage ?? 0.0
        let newProgressValue = max(currentProgress, progressUpdate.percentage)

        entries[entryIndex].progressPercentage = newProgressValue
        entries[entryIndex].estimatedTimeRemaining = progressUpdate.estimatedTimeRemaining
        entries[entryIndex].currentLoudness = progressUpdate.currentLoudness
      }
    }
  }

  // MARK: Private

  @ObservationIgnored private let writerQueue = DispatchQueue(label: "r128x.writer")

  private func recursivelyEnumerateAudioFiles(in directoryURL: URL, allowedSuffixes: [String])
    -> [URL] {
    var audioFiles: [URL] = []

    guard let enumerator = FileManager.default.enumerator(
      at: directoryURL,
      includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    )
    else {
      return audioFiles
    }

    for case let fileURL as URL in enumerator {
      do {
        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        if let isRegularFile = resourceValues.isRegularFile, isRegularFile {
          let path = fileURL.path(percentEncoded: false)
          for fileExtension in allowedSuffixes {
            if path.hasSuffix(".\(fileExtension)") {
              audioFiles.append(fileURL)
              break
            }
          }
        }
      } catch {
        // Skip files that can't be checked
        continue
      }
    }

    return audioFiles
  }
}

extension Bool {
  fileprivate var negative: Bool { !self }
}
