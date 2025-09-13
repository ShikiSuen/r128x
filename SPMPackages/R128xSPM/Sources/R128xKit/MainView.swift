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
      #if os(macOS)
      .presentedWindowToolbarStyle(.unifiedCompact)
      #endif
      .onOpenURL { url in
        handleSharedURL(url)
      }
    }
    .commands {
      CommandGroup(replacing: CommandGroupPlacement.newItem) {}
    }
    .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
  }

  // MARK: Private

  private func handleSharedURL(_ url: URL) {
    // Handle shared files from the share extension and other sources
    print("R128xScene: Received shared URL: \(url)")
    // Start accessing security-scoped resource

    let accessing = url.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    Task { @MainActor in
      var urlsToProcess: [URL] = []

      if url.scheme == "file" {
        // Direct file URL
        urlsToProcess.append(url)
      } else if url.isFileURL {
        // Another type of file URL
        urlsToProcess.append(url)
      } else {
        // Handle other URL schemes if needed
        print("Received unsupported URL scheme: \(url.scheme ?? "nil") for URL: \(url)")
        return
      }

      // Filter URLs to only include supported audio files and folders
      let filteredURLs = urlsToProcess.filter { url in
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if !exists {
          return false
        }

        if isDirectory.boolValue {
          return true // Accept folders
        }

        // Check if file has supported extension
        let pathExtension = url.pathExtension.lowercased()
        return MainViewModel.allowedSuffixes.contains(pathExtension)
      }

      if !filteredURLs.isEmpty {
        SharedFileManager.shared.handleSharedFiles(filteredURLs)
      }
    }
  }
}

// MARK: - MainView

struct MainView: View {
  // MARK: Lifecycle

  // MARK: - Instance.

  public init() {}

  // MARK: Internal

  var body: some View {
    NavigationStack {
      mainContentView
        .navigationTitle("app.windowTitle".i18n)
      #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
        .toolbar {
          toolbarContent
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
  @State private var sharedFileManager = SharedFileManager.shared
  @State private var progressObservationTask: Task<Void, Never>?

  @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
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

  @ViewBuilder private var mainContentView: some View {
    Group {
      if !viewModel.entries.isEmpty {
        taskListView()
          .searchable(text: $viewModel.searchText, prompt: "Search files...".i18n)
      } else {
        taskListView()
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
    .onChange(of: sharedFileManager.pendingSharedFiles) { _, pendingFiles in
      if !pendingFiles.isEmpty {
        sharedFileManager.processPendingFiles(with: viewModel)
      }
    }
    .task {
      // Use .task instead of .onAppear for better lifecycle management
      // This automatically cancels when the view disappears and recreates when it reappears
      progressObservationTask = viewModel.taskTrackingVM.startObserving()
    }
    .onAppear {
      // Only handle shared files on appear, not progress observation
      sharedFileManager.processPendingFiles(with: viewModel)
    }
  }

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
                  .truncationMode(.head)
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
