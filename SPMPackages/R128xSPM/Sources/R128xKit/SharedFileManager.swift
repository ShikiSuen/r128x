// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation
import SwiftUI

// MARK: - SharedFileManager

@Observable
@MainActor
public final class SharedFileManager {
  // MARK: Lifecycle

  private init() {}

  // MARK: Public

  public static let shared = SharedFileManager()

  public var pendingSharedFiles: [URL] = []

  public func handleSharedFiles(_ urls: [URL]) {
    // Log incoming shared files for debugging
    print("SharedFileManager: Received \(urls.count) shared file(s)")
    for url in urls {
      print("  - \(url.path)")
    }

    // Process shared files with security-scoped resource access
    var validURLs: [URL] = []

    for url in urls {
      // Start accessing security-scoped resource for shared files
      let accessing = url.startAccessingSecurityScopedResource()
      defer {
        if accessing {
          url.stopAccessingSecurityScopedResource()
        }
      }

      // Verify file exists and is accessible
      if FileManager.default.fileExists(atPath: url.path) {
        validURLs.append(url)
      } else {
        print("SharedFileManager: File not accessible: \(url.path)")
      }
    }

    // Add to pending files, avoiding duplicates
    let newURLs = validURLs.filter { newURL in
      !pendingSharedFiles.contains { $0.path == newURL.path }
    }

    pendingSharedFiles.append(contentsOf: newURLs)

    if !newURLs.isEmpty {
      print("SharedFileManager: Added \(newURLs.count) new file(s) to pending queue")
    }
  }

  public func processPendingFiles(with viewModel: MainViewModel) {
    guard !pendingSharedFiles.isEmpty else { return }

    print("SharedFileManager: Processing \(pendingSharedFiles.count) pending file(s)")

    // Use the existing addFiles method which handles both files and folders
    viewModel.addFiles(urls: pendingSharedFiles)

    // Clear pending files after processing
    pendingSharedFiles.removeAll()

    print("SharedFileManager: Completed processing shared files")
  }

  public func clearPendingFiles() {
    print("SharedFileManager: Clearing \(pendingSharedFiles.count) pending file(s)")
    pendingSharedFiles.removeAll()
  }
}
