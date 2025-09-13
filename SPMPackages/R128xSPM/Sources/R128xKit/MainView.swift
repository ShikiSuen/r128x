// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
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
      .presentedWindowToolbarStyle(.unifiedCompact)
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
      Group {
        if !viewModel.entries.isEmpty {
          taskListView() // taskTableView()
            .searchable(text: $viewModel.searchText, prompt: "Search files...".i18n)
        } else {
          taskListView() // taskTableView()
        }
      }
      .onDrop(
        of: [UTType.fileURL], isTargeted: $viewModel.dragOver, perform: viewModel.handleDrop
      )
      .onChange(of: viewModel.taskTrackingVM.fileProgress) { _, newProgress in
        Task { @MainActor in
          await viewModel.progressDebouncer.debounceProgress(newProgress) { progress in
            viewModel.updateProgress(progress)
          }
        }
      }
      .onDisappear {
        // Cancel progress observation when view disappears
        progressObservationTask?.cancel()
      }
      .navigationTitle("app.windowTitle".i18n)
      #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button {
              addFilesButtonDidPress()
            } label: {
              Label("Add Files".i18n, systemImage: "folder.badge.plus")
            }
            .help("Add Files".i18n)
          }
          if !viewModel.entries.isEmpty {
            ToolbarItem(placement: .cancellationAction) {
              Button {
                viewModel.clearEntries()
              } label: {
                Label("Clear Table".i18n, systemImage: "trash")
              }
              .help("Clear Table".i18n)
            }
            ToolbarItem(placement: .confirmationAction) {
              Button {
                viewModel.batchProcess(forced: true)
              } label: {
                Label("Reprocess All".i18n, systemImage: "gobackward")
              }
              .disabled(viewModel.entries.isEmpty || viewModel.entries.count(where: \.done) == 0)
              .help("Reprocess All".i18n)
            }
          }
        }
        .safeAreaInset(edge: .bottom) {
          if !viewModel.entries.isEmpty {
            controlsView()
              .padding(10)
              .padding(.horizontal, 10)
              .background(.regularMaterial)
          }
        }
    }
    #if os(macOS)
    .frame(minWidth: 300, minHeight: 367, alignment: .center)
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

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass: UserInterfaceSizeClass?

  private var progressObservationTask: Task<Void, Never>?

  @ViewBuilder
  private func controlsView() -> some View {
    HStack {
      ProgressView(value: viewModel.progressValue) {
        Text(viewModel.queueMessage)
          .font(.caption)
      }
      .controlSize(.small)
      Spacer()
    }
  }

  @ViewBuilder
  private func taskListView() -> some View {
    List {
      ForEach(Array(viewModel.filteredEntries.enumerated()), id: \.offset) { index, entry in
        HStack {
          VStack(alignment: .leading) {
            let mainLabel = HStack {
              HStack {
                Text(entry.fileName)
                  .fontWeight(.bold)
                  .font(.caption)
                  .lineLimit(1)
                  .help(entry.folderPath)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              if entry.status == .processing {
                Text("\(entry.progressDisplayed)")
                  .font(.caption2)
                  .fixedSize()
              }
              if entry.done {
                HStack {
                  Text(verbatim: "dBTP")
                  Text(entry.dBTPDisplayed)
                    .fontWeight(entry.dBTP == 0 ? .bold : .regular)
                }
                .font(.caption2)
                .help(Text("dBTP".i18n))
              }
            }
            if entry.done {
              VStack(alignment: .leading) {
                mainLabel
                Text(entry.folderPath)
                  .lineLimit(1)
                  .truncationMode(.tail)
                  .fontWidth(.condensed)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            } else {
              ProgressView(value: entry.guardedProgressValue) {
                mainLabel
              }
              .controlSize(.small)
            }
          }
          if entry.done {
            Divider()
            VStack {
              HStack {
                Text(verbatim: "iL")
                Spacer()
                Text(entry.programLoudnessDisplayed)
                  .fontWeight(.bold)
              }
              .font(.caption)
              .help(Text("Program Loudness".i18n))
              HStack {
                Text(verbatim: "lRa")
                Spacer()
                Text(entry.loudnessRangeDisplayed)
              }
              .font(.caption2)
              .foregroundStyle(.secondary)
              .help(Text("Loudness Range".i18n))
            }
            .frame(width: 60)
            .colorMultiply(entry.isResultInvalid ? .red : .primary)
          }
        }
        .font(.system(.body).monospacedDigit())
        #if os(macOS)
          .padding(.horizontal, 10)
        #else
          .listRowBackground(index % 2 == 0 ? Color.gray.opacity(0.2) : Color.clear)
        #endif
      }
    }
    #if os(macOS)
    .listStyle(.bordered(alternatesRowBackgrounds: true))
    #else
    .listStyle(.plain)
    #endif
    .overlay {
      if viewModel.entries.isEmpty {
        Color.clear.background(.regularMaterial)
          .overlay {
            VStack(spacing: 16) {
              Image(systemName: "waveform.path")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

              VStack(spacing: 8) {
                Text("emptyState.title".i18n)
                  .font(.title3)
                  .fontWeight(.medium)

                #if os(macOS)
                Text("emptyState.dragHint.macOS".i18n)
                  .font(.body)
                  .foregroundStyle(.secondary)
                  .multilineTextAlignment(.center)
                #else
                Text("emptyState.dragHint.iOS".i18n)
                  .font(.body)
                  .foregroundStyle(.secondary)
                  .multilineTextAlignment(.center)
                #endif
              }
            }
            .frame(maxWidth: 300)
            .padding()
          }
      }
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
