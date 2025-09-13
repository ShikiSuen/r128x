// (c) (C ver. only) 2012-2013 Manuel Naudin (AGPL v3.0 License or later).
// (c) (this Swift implementation) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.
// ====================
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

import Foundation
import R128xKit

// MARK: - CliController

public class CliController {
  // MARK: Lifecycle

  public init(path thePath: String) {
    self.filePath = thePath
  }

  // MARK: Public

  public private(set) var filePath: String
  public private(set) var il: Double = .nan
  public private(set) var lra: Double = .nan
  public private(set) var maxTP: Double = .nan
  public private(set) var status: Int32 = 0

  public var result: String {
    var blocks: [String] = []
    blocks.append((filePath as NSString).lastPathComponent)
    if status == 0 {
      blocks.append(String(format: "%.1f", arguments: [il]))
      blocks.append(String(format: "%.1f", arguments: [lra]))
      blocks.append(String(format: "%.1f", arguments: [maxTP]))
    } else {
      blocks.append("// Conversion Failed.")
    }
    return blocks.joined(separator: "\t")
  }

  public func doMeasure() async {
    do {
      let processor = ExtAudioProcessor()
      let (integratedLoudness, loudnessRange, maxTruePeak) = try await processor.processAudioFile(
        at: filePath,
        fileId: String?.none
      ) { progress in
        // Update progress for CLI
        let value = Float(progress.percentage)
        print(String(format: "%3d%% \n\033[F\033[J", Int(floor(value))))
      }

      il = integratedLoudness
      lra = loudnessRange
      maxTP = maxTruePeak
      status = 0
    } catch {
      status = -1
      resetNumericValues()

      // Print detailed error information for better user experience
      if let nsError = error as NSError? {
        print(
          "Error processing \((filePath as NSString).lastPathComponent): \(nsError.localizedDescription)"
        )
        if let recoverySuggestion = nsError.localizedRecoverySuggestion {
          print("  \(recoverySuggestion)")
        }
      } else {
        print(
          "Error processing \((filePath as NSString).lastPathComponent): \(error.localizedDescription)"
        )
      }
    }
  }

  // MARK: Internal

  func resetNumericValues() {
    il = .nan
    lra = .nan
    maxTP = .nan
  }
}

guard CommandLine.argc >= 2 else {
  print("Missing arguments\nYou should specify at least one audio file\nr128x /some/file\n")
  exit(1)
}

// Table Header.
print("FILE\tIL (LUFS)\tLRA (LU)\tMAXTP (dBTP)")

let formatter = NumberFormatter()
formatter.maximumFractionDigits = 2
formatter.minimumFractionDigits = 0

// Process files sequentially (async)
Task {
  for currentArg in CommandLine.arguments.dropFirst(1) {
    let controller = CliController(path: currentArg.description)
    await controller.doMeasure()
    print(controller.result)
  }
  exit(0)
}

// Keep the process alive for async tasks
RunLoop.main.run()
