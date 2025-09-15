// (c) (C ver. only) 2012-2013 Manuel Naudin (AGPL v3.0 License or later).
// (c) (this Swift implementation) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import R128xGUIKit
import SwiftUI

#if os(macOS)
import R128xCLIKit
#endif

// MARK: - MainEntry

@main
struct MainEntry {
  static func main() {
    let lowercasedVarArgs = CommandLine.arguments.map { $0.lowercased() }
    #if os(macOS)
    if lowercasedVarArgs.contains("--cli") {
      Task {
        await CliController.runMainAndExit(mas: true)
      }
      RunLoop.main.run()
    } else {
      MainApp.main()
    }
    #else
    MainApp.main()
    #endif
  }
}

// MARK: - MainApp

struct MainApp: App {
  var body: some Scene {
    R128xScene()
  }
}
