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
        exit(0)
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
    // Start observing progress updates
    self.progressObservationTask = viewModel.taskTrackingVM.startObserving()
  }

  // MARK: Internal

  var body: some View {
    NavigationStack {
      taskTableView()
        .navigationTitle("app.windowTitle".i18n)
      #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Add Files".i18n) {
              addFilesButtonDidPress()
            }
          }
          ToolbarItem(placement: .cancellationAction) {
            Button("Clear Table".i18n) {
              viewModel.clearEntries()
            }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Reprocess All".i18n) {
              viewModel.batchProcess(forced: true)
            }
            .disabled(viewModel.entries.isEmpty || viewModel.entries.count(where: \.done) == 0)
          }
        }
        .safeAreaInset(edge: .bottom) {
          controlsView()
            .padding(10)
            .padding(.horizontal, 10)
            .background(.regularMaterial)
        }
    }
    #if os(macOS)
    .frame(minWidth: 800, minHeight: 367, alignment: .center)
    #endif
    .fileImporter(
      isPresented: $isFileImporterPresented,
      allowedContentTypes: MainViewModel.allowedUTTypes,
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case let .success(urls):
        viewModel.addFiles(urls: urls)
      case let .failure(error):
        print("File selection error: \(error)")
      }
    }
  }

  // MARK: Private

  @State private var viewModel = MainViewModel()
  @State private var isFileImporterPresented = false

  private var progressObservationTask: Task<Void, Never>?

  @ViewBuilder
  private func controlsView() -> some View {
    HStack {
      ProgressView(value: viewModel.progressValue) {
        Text(viewModel.queueMessage).controlSize(.small)
      }
      Spacer()
    }
  }

  @ViewBuilder
  private func taskTableView() -> some View {
    Table(viewModel.entries, selection: $viewModel.highlighted) {
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
    }
    .font(.system(.body).monospacedDigit())
    .onDrop(of: [UTType.fileURL], isTargeted: $viewModel.dragOver, perform: viewModel.handleDrop)
    .onChange(of: viewModel.taskTrackingVM.fileProgress) { _, newProgress in
      viewModel.updateProgress(newProgress)
    }
    .onDisappear {
      // Cancel progress observation when view disappears
      progressObservationTask?.cancel()
    }
  }

  private func addFilesButtonDidPress() {
    isFileImporterPresented = true
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
