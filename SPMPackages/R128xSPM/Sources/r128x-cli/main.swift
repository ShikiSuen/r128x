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

import R128xSharedBackend

// MARK: - CliController

@objcMembers
public class CliController: NSObject {
  // MARK: Lifecycle

  public init(path thePath: String) {
    self.filePath = NSString(string: thePath)
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(progressUpdate(_:)),
      name: .init("R128X_Progress"),
      object: nil
    )
  }

  // MARK: Public

  public private(set) var filePath: NSString
  public private(set) var il: Double = .nan
  public private(set) var lra: Double = .nan
  public private(set) var maxTP: Float32 = .nan
  public private(set) var status: OSStatus = noErr

  public var result: String {
    var blocks: [String] = []
    blocks.append(filePath.lastPathComponent)
    if status == noErr {
      blocks.append(String(format: "%.1f", arguments: [il]))
      blocks.append(String(format: "%.1f", arguments: [lra]))
      blocks.append(String(format: "%.1f", arguments: [maxTP]))
    } else {
      blocks.append("// Conversion Failed.")
    }
    return blocks.joined(separator: "\t")
  }

  public func doMeasure() {
    status = ExtAudioReader(filePath as CFString, &il, &lra, &maxTP)
    if status != noErr { resetNumericValues() }
  }

  public func progressUpdate(_ notification: NSNotification) {
    let value = notification.object as? Float ?? 114_514.0
    print(String(format: "%3d%% \n\033[F\033[J", Int(floor(value))))
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

for currentArg in CommandLine.arguments.dropFirst(1) {
  let controller = CliController(path: currentArg.description)
  controller.doMeasure()
  print(controller.result)
}

exit(0)
