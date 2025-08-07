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
          format: "Processing files in the queue: %d remaining (~%@ remaining)...".i18n,
          filesPendingProcessing,
          remaining
        )
      } else {
        return String(format: "Processing files in the queue: %d remaining.".i18n, filesPendingProcessing)
      }
    }

    guard invalidResults == 0 else {
      return String(format: "All files are processed, excepting %d failed files.".i18n, invalidResults)
    }
    return "All files are processed successfully.".i18n
  }

  var body: some View {
    VStack(spacing: 5) {
      Table(entries, selection: $highlighted) {
        TableColumn("🕰️") { entry in
          Text(entry.timeRemainingDisplayed)
            .font(.caption2)
        }
        .width(30)
        .alignment(.numeric)
        TableColumn("File Name".i18n) { entry in
          HStack {
            VStack(alignment: .leading) {
              ProgressView(value: entry.guardedProgressValue) {
                HStack {
                  Text(entry.fileName)
                    .fontWeight(.bold)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                  if entry.status == .processing {
                    Text("\(entry.progressDisplayed)")
                      .font(.caption2)
                      .fixedSize()
                  }
                }
              }
              .controlSize(.small)
            }
            .contentShape(.rect)
            .help(entry.fileName)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            if entry.done {
              VStack {
                HStack {
                  Text("Program Loudness".i18n)
                    .frame(maxWidth: .infinity, alignment: .leading)
                  Text(entry.programLoudnessDisplayed)
                    .fontWeight(.bold)
                    .fontWidth(.standard)
                    .frame(width: 35, alignment: .trailing)
                }
                .font(.caption)
                HStack {
                  Text("Loudness Range".i18n)
                    .frame(maxWidth: .infinity, alignment: .leading)
                  Text(entry.loudnessRangeDisplayed)
                    .fontWidth(.condensed)
                    .frame(width: 35, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
              }
              .fixedSize()
              .fontWidth(.compressed)
            }
          }
        }
        .width(400)
        TableColumn("dBTP".i18n) { entry in
          Text(entry.dBTPDisplayed)
            .fontWeight(entry.dBTP == 0 ? .bold : .regular)
        }
        .width(45)
        .alignment(.numeric)
        TableColumn("Location".i18n) { entry in
          Text(entry.folderPath)
            .fontWidth(.condensed)
            .help(entry.folderPath)
        }
      }.onChange(of: entries) {
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
          .disabled(entries.isEmpty || entries.count(where: \.done) == 0)
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
          let currentLoudness = userInfo["currentLoudness"]
          let estimatedTimeRemaining = userInfo["estimatedTimeRemaining"]

          // Find the specific entry by fileId and update its progress
          if let entryIndex = entries.firstIndex(where: { $0.id.uuidString == fileId }) {
            entries[entryIndex].progressPercentage = percentage
            entries[entryIndex].estimatedTimeRemaining = (estimatedTimeRemaining as? TimeInterval)
            entries[entryIndex].currentLoudness = (currentLoudness as? Double)
          }
        }
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
