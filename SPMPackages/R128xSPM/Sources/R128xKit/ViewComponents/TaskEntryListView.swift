// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(SwiftUI)
struct TaskEntryListView: View {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  public var body: some View {
    @Bindable var viewModel = viewModel
    Group {
      if !viewModel.entries.isEmpty {
        subBody
          .searchable(text: $viewModel.searchText, prompt: "searchBar.promptText".i18n)
      } else {
        subBody
      }
    }
  }

  // MARK: Private

  @Environment(MainViewModel.self) private var viewModel

  @ViewBuilder private var subBody: some View {
    Table(viewModel.filteredEntries) {
      TableColumn("".description) { entry in
        TaskEntryView(entry)
          .foregroundStyle(.primary)
          .contextMenu {
            #if os(macOS)
            Button {
              NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            } label: {
              Label("contextMenu.showInFinder".i18n, systemImage: "folder")
            }
            Divider()
            #endif
            Button {
              viewModel.removeEntry(id: entry.id)
            } label: {
              Label("contextMenu.removeThisEntry".i18n, systemImage: "trash")
            }
          }
      }
    }
    .tableColumnHeaders(.hidden)
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
                // The following i18n key automatically differs between iOS and macOS.
                Text("emptyState.dragHint".i18n)
                  .font(.body)
                  .foregroundStyle(.secondary)
                  .multilineTextAlignment(.leading)
              }
            }
            .frame(maxWidth: 300)
            .padding()
          }
      }
    }
  }
}

#endif
