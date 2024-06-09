// This file is part of r128x.
//
// r128x is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// r128x is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with r128x.  If not, see <http://www.gnu.org/licenses/>.
// copyright Manuel Naudin 2012-2013

import SwiftUI
import UniformTypeIdentifiers

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
      }.onChange(of: entries) { _ in
        batchProcess(forced: false)
      }
      .font(.system(.body).monospacedDigit())
      .onDrop(of: [UTType.fileURL], isTargeted: $dragOver) { providers -> Bool in
        var counter = 0
        defer {
          if counter > 0 {
            batchProcess(forced: false)
          }
        }
        for provider in providers {
          _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            let path = url.path
            guard !entries.map(\.fileName).contains(path) else { return }
            entryInsertion: for fileExtension in Self.allowedSuffixes {
              guard path.hasSuffix(".\(fileExtension)") else { continue }
              counter += 1
              entries.append(.init(fileName: path))
              break entryInsertion
            }
          }
        }
        return true
      }
      HStack {
        Button("Add Files".i18n) {
          guard Self.comdlg32.runModal() == .OK else { return }
          let entriesAsPaths: [String] = entries.map(\.fileName)
          let contents: [URL] = Self.comdlg32.urls.filter {
            !entriesAsPaths.contains($0.path)
          }
          entries.append(contentsOf: contents.map { .init(fileName: $0.path) })
        }
        Button("Clear Table".i18n) { entries.removeAll() }
        Button("Reprocess All".i18n) { batchProcess(forced: true) }
        ProgressView(value: progressValue) { Text(queueMessage).controlSize(.small) }
        Spacer()
      }.padding(.bottom, 10).padding([.horizontal], 10)
    }.frame(minWidth: 971, minHeight: 367, alignment: .center)
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
        result.process(forced: forced)

        writerQueue.async {
          entries[i] = result
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
    "mp3",
    "mp2",
    "m4a",
    "wav",
    "aif",
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

  private let writerQueue = DispatchQueue(label: "r128x.writer")
  @State private var currentTask: DispatchWorkItem?
}

extension Bool {
  fileprivate var negative: Bool { !self }
}

#Preview {
  MainView()
    .environment(\.locale, .init(identifier: "en"))
}
