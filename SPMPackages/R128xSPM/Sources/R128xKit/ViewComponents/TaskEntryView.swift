// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

#if canImport(SwiftUI)
import SwiftUI
#endif

#if canImport(SwiftUI)
struct TaskEntryView: View {
  // MARK: Lifecycle

  public init(_ taskEntry: TaskEntry) {
    self.entry = taskEntry
  }

  // MARK: Public

  public var body: some View {
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
            .help(Text("fieldTitle.dBTP".i18n))
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
    }
    .font(.system(.body).monospacedDigit())
    .contentShape(.rect)
  }

  // MARK: Private

  /// This must be a `let` constant to make this view responsive to external changes.
  private let entry: TaskEntry
}
#endif
