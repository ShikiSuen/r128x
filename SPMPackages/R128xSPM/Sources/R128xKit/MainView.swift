// (c) (C ver. only) 2012-2013 Manuel Naudin (AGPL v3.0 License or later).
// (c) (this Swift implementation) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

#if canImport(SwiftUI)

// MARK: - R128xScene

public struct R128xScene: Scene {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  public var body: some Scene {
    WindowGroup {
      MainView().onDisappear {
        NSApplication.shared.terminate(self)
      }
    }.commands {
      CommandGroup(replacing: CommandGroupPlacement.newItem) {}
    }
  }
}

// MARK: - Current File Progress

struct CurrentFileProgress {
  let fileName: String
  let percentage: Double
  let framesProcessed: Int64
  let totalFrames: Int64
  let currentLoudness: Double?
  let estimatedTimeRemaining: TimeInterval?
}

extension TimeInterval {
  func formatted() -> String {
    let minutes = Int(self) / 60
    let seconds = Int(self) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}

// MARK: - MainView

struct MainView: View {
  // MARK: Lifecycle

  // MARK: - Instance.

  public init() {
    Self.comdlg32.allowedContentTypes = Self.allowedUTTypes
  }

  // MARK: Internal

  var progressValue: CGFloat {
    if entries.isEmpty { return 0 }
    return CGFloat(entries.filter(\.done).count) / CGFloat(entries.count)
  }

  var queueMessage: String {
    if entries.isEmpty {
      return "Drag audio files from Finder to the table in this window.".i18n
    }
    let filesPendingProcessing: Int = entries.filter(\.done.negative).count
    let invalidResults: Int = entries.reduce(0) { $0 + ($1.status == .failed ? 1 : 0) }

    // Show detailed progress if we have current processing info
    if let currentProgress = currentFileProgress,
       filesPendingProcessing > 0 {
      let fileName = URL(fileURLWithPath: currentProgress.fileName).lastPathComponent
      let percentage = Int(currentProgress.percentage)
      let remaining = currentProgress.estimatedTimeRemaining?.formatted() ?? "unknown"
      return String(format: "Processing %@ (%d%%, ~%@ remaining)...".i18n, fileName, percentage, remaining)
    }

    guard filesPendingProcessing == 0 else {
      return String(format: "Processing files in the queue: %d remaining.".i18n, filesPendingProcessing)
    }
    guard invalidResults == 0 else {
      return String(format: "All files are processed, excepting %d failed files.".i18n, invalidResults)
    }
    return "All files are processed successfully.".i18n
  }

  var body: some View {
    VStack(spacing: 5) {
      Table(entries, selection: $highlighted) {
        TableColumn("Status".i18n, value: \.statusDisplayed).width(50)
        TableColumn("File Name".i18n, value: \.fileName)
        TableColumn("Program Loudness".i18n, value: \.programLoudnessDisplayed).width(170)
        TableColumn("Loudness Range".i18n, value: \.loudnessRangeDisplayed).width(140)
        TableColumn("dBTP".i18n, value: \.dBTPDisplayed).width(50)
        TableColumn("Progress".i18n, value: \.progressDisplayed).width(80)
      }.onChange(of: entries) { _ in
        batchProcess(forced: false)
      }
      .font(.system(.body).monospacedDigit())
      .onDrop(of: [UTType.fileURL], isTargeted: $dragOver, perform: handleDrop)
      HStack {
        Button("Add Files".i18n) {
          addFilesButtonDidPress()
        }
        Button("Clear Table".i18n) { entries.removeAll() }
        Button("Reprocess All".i18n) { batchProcess(forced: true) }
        ProgressView(value: progressValue) { Text(queueMessage).controlSize(.small) }
        Spacer()
      }.padding(.bottom, 10).padding([.horizontal], 10)
    }.frame(minWidth: 1141, minHeight: 367, alignment: .center)
      .onReceive(
        NotificationCenter.default
          .publisher(for: Notification.Name(ExtAudioProcessor.progressNotificationName))
      ) { notification in
        if let userInfo = notification.userInfo,
           let fileId = userInfo["fileId"] as? String {
          let percentage = userInfo["progress"] as? Double ?? 0.0
          let framesProcessed = userInfo["framesProcessed"] as? UInt32 ?? 0
          let totalFrames = userInfo["totalFrames"] as? Int64 ?? 1
          let currentLoudness = userInfo["currentLoudness"]
          let estimatedTimeRemaining = userInfo["estimatedTimeRemaining"]

          // Find the specific entry by fileId and update its progress
          if let entryIndex = entries.firstIndex(where: { $0.id.uuidString == fileId }) {
            entries[entryIndex].progressPercentage = percentage
            entries[entryIndex].estimatedTimeRemaining = (estimatedTimeRemaining as? TimeInterval)

            // Keep the currentFileProgress for the status message
            currentFileProgress = CurrentFileProgress(
              fileName: entries[entryIndex].fileNamePath,
              percentage: percentage,
              framesProcessed: Int64(framesProcessed),
              totalFrames: totalFrames,
              currentLoudness: (currentLoudness as? Double),
              estimatedTimeRemaining: (estimatedTimeRemaining as? TimeInterval)
            )
          }
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FileProcessingCompleted"))) { _ in
        // Clear current file progress when processing completes
        currentFileProgress = nil
      }
  }

  func batchProcess(forced: Bool = false) {
    // cancel the current task
    currentTask?.cancel()

    // when forced = true, we reset the processing state
    if forced {
      for i in 0 ..< entries.count {
        entries[i].status = .processing
      }
    }

    // create a work item that process concurrently
    currentTask = DispatchWorkItem {
      DispatchQueue.concurrentPerform(iterations: entries.count) { i in
        // copy entry
        var result = entries[i]

        // Create task for async processing
        Task {
          await result.process(forced: forced)

          writerQueue.async {
            entries[i] = result
          }
        }
      }
    }

    // debounce in 0.25 seconds
    if let t = currentTask {
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.25, execute: t)
    }
  }

  // MARK: Private

  private static let allowedSuffixes: [String] = [
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
  private static let allowedUTTypes: [UTType] = Self.allowedSuffixes.compactMap { .init(filenameExtension: $0) }

  private static let comdlg32: NSOpenPanel = {
    let result = NSOpenPanel()
    result.allowsMultipleSelection = true
    result.canChooseDirectories = false
    result.prompt = "Process"
    result.title = "File Selector"
    result.message = "Select files…"
    return result
  }()

  @State private var dragOver = false
  @State private var highlighted: IntelEntry.ID?
  @State private var entries: [IntelEntry] = []
  @State private var currentFileProgress: CurrentFileProgress?

  @State private var currentTask: DispatchWorkItem?

  private let writerQueue = DispatchQueue(label: "r128x.writer")

  private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
    var counter = 0
    defer {
      if counter > 0 {
        batchProcess(forced: false)
      }
    }
    for provider in providers {
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        guard let url else { return }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists, !isDirectory.boolValue else { return }
        let path = url.path
        guard !entries.map(\.fileNamePath).contains(path) else { return }
        entryInsertion: for fileExtension in Self.allowedSuffixes {
          guard path.hasSuffix(".\(fileExtension)") else { continue }
          counter += 1
          entries.append(.init(url: url))
          break entryInsertion
        }
      }
    }
    return true
  }

  private func addFilesButtonDidPress() {
    guard Self.comdlg32.runModal() == .OK else { return }
    let entriesAsPaths: [String] = entries.map(\.fileNamePath)
    let contents: [URL] = Self.comdlg32.urls.filter {
      !entriesAsPaths.contains($0.path)
    }
    entries.append(contentsOf: contents.compactMap {
      var isDirectory: ObjCBool = false
      let exists = FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory)
      guard exists, !isDirectory.boolValue else { return nil }
      return .init(url: $0)
    })
  }
}

extension Bool {
  fileprivate var negative: Bool { !self }
}

#Preview {
  MainView()
    .environment(\.locale, .init(identifier: "en"))
}

#endif
