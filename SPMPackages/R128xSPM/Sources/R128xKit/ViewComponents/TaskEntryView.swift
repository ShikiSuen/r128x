// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(SwiftUI)
struct TaskEntryView: View {
  // MARK: Lifecycle

  public init(_ taskEntry: TaskEntry, isChosen: Bool) {
    self.entry = taskEntry
    self.isChosen = isChosen
  }

  // MARK: Public

  public var body: some View {
    contentView
  }

  // MARK: Private

  @Environment(MainViewModel.self) private var viewModel

  /// This must be a `let` constant to make this view responsive to external changes.
  private let entry: TaskEntry
  private let isChosen: Bool

  private var dynamicallyAccentedPrimaryColor: Color {
    isChosen ? .primary : .accentColor
  }

  @ViewBuilder private var playbackBackgroundLayer: some View {
    RoundedRectangle(cornerRadius: 6)
      .fill(Color.accentColor.opacity(0.1))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
      )
      .scaleEffect(1.1)
  }

  @ViewBuilder private var contentView: some View {
    let isCurrentlyPreviewing = viewModel.isPreviewingTask(id: entry.id)
    HStack {
      entryLeftContent(isCurrentlyPreviewing: isCurrentlyPreviewing)

      if entry.done {
        Divider()
          .overlay(
            !isCurrentlyPreviewing
              ? Color.clear
              : dynamicallyAccentedPrimaryColor
          )
        entryRightContent
      }
    }
    .font(.system(.body).monospacedDigit())
    .contentShape(.rect)
    .background(
      isCurrentlyPreviewing
        ? playbackBackgroundLayer
        : nil
    )
    .animation(.easeInOut(duration: 0.2), value: isCurrentlyPreviewing)
  }

  @ViewBuilder private var entryRightContent: some View {
    ViewThatFits {
      VStack {
        HStack {
          Text("Program Loudness".i18n)
          Spacer()
          Text(entry.programLoudnessDisplayed)
            .fontWeight(.bold)
            .frame(width: 35)
        }
        .font(.caption)
        .help(Text("Program Loudness".i18n))
        HStack {
          Text("fieldTitle.loudnessRange".i18n)
          Spacer()
          Text(entry.loudnessRangeDisplayed)
            .frame(width: 35)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help(Text("fieldTitle.loudnessRange".i18n))
      }
      .fixedSize()
      VStack {
        HStack {
          Text(verbatim: "iL")
          Spacer()
          Text(entry.programLoudnessDisplayed)
            .fontWeight(.bold)
            .frame(width: 35)
        }
        .font(.caption)
        .help(Text("Program Loudness".i18n))
        HStack {
          Text(verbatim: "lRa")
          Spacer()
          Text(entry.loudnessRangeDisplayed)
            .frame(width: 35)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help(Text("fieldTitle.loudnessRange".i18n))
      }
      .fixedSize()
    }
    .colorMultiply(entry.isResultInvalid ? .red : .primary)
  }

  @ViewBuilder
  private func entryLeftContent(isCurrentlyPreviewing: Bool) -> some View {
    VStack(alignment: .leading) {
      let mainLabel = mainLabelView()

      if entry.done {
        VStack(alignment: .leading) {
          mainLabel
          HStack {
            Text(entry.folderPath)
              .lineLimit(1)
              .truncationMode(.head)
              .fontWidth(.condensed)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)

            // Show preview start time
            if isCurrentlyPreviewing, entry.previewStartAtTime != nil {
              HStack(spacing: 2) {
                Image(systemName: "speaker.wave.2.fill")
                  .foregroundStyle(dynamicallyAccentedPrimaryColor)
                  .font(.caption2)
                  .help("contextMenu.previewPlaying".i18n)

                // Show preview start time
                if entry.previewStartAtTime != nil {
                  Text(entry.previewStartAtTimeDisplayedShort)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(dynamicallyAccentedPrimaryColor)
                    .help("Preview starting at \(entry.previewStartAtTimeDisplayed)")
                }
              }
            }
          }
        }
      } else {
        ProgressView(value: entry.guardedProgressValue) {
          mainLabel
        }
        .controlSize(.small)
      }
    }
  }

  @ViewBuilder
  private func mainLabelView() -> some View {
    HStack {
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
        .help(Text("fieldTitle.dBTP".i18n))
      }
    }
  }
}
#endif
