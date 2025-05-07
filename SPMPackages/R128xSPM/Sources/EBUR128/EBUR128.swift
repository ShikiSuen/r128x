import Foundation

// MARK: - EBUR128

/// libebur128 - a Swift library for loudness measurement according to the EBU R128 standard.
public enum EBUR128 {
  /// Channel types for EBU R128 analysis.
  /// See definitions in ITU R-REC-BS 1770-4
  public enum Channel: Int {
    case unused = 0 // unused channel (for example LFE channel)
    case left = 1 // or itu M+030
    case right = 2 // or itu M-030
    case center = 3 // or itu M+000
    case leftSurround = 4 // or itu M+110
    case rightSurround = 5 // or itu M-110
    case dualMono = 6 // a channel that is counted twice
    case mpSC = 7 // itu M+SC
    case mmSC = 8 // itu M-SC
    case mp060 = 9 // itu M+060
    case mm060 = 10 // itu M-060
    case mp090 = 11 // itu M+090
    case mm090 = 12 // itu M-090
    case mp135 = 13 // itu M+135
    case mm135 = 14 // itu M-135
    case mp180 = 15 // itu M+180
    case up000 = 16 // itu U+000
    case up030 = 17 // itu U+030
    case um030 = 18 // itu U-030
    case up045 = 19 // itu U+045
    case um045 = 20 // itu U-045
    case up090 = 21 // itu U+090
    case um090 = 22 // itu U-090
    case up110 = 23 // itu U+110
    case um110 = 24 // itu U-110
    case up135 = 25 // itu U+135
    case um135 = 26 // itu U-135
    case up180 = 27 // itu U+180
    case tp000 = 28 // itu T+000
    case bp000 = 29 // itu B+000
    case bp045 = 30 // itu B+045
    case bm045 = 31 // itu B-045
  }

  /// Processing modes for EBU R128 analysis
  public struct Mode: OptionSet, Sendable {
    // MARK: Lifecycle

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    // MARK: Public

    /// Can call loudnessMomentary()
    public static let momentary = Mode(rawValue: 1 << 0)

    /// Can call loudnessShortterm()
    public static let shortTerm = Mode(rawValue: 1 << 1)

    /// Can call loudnessGlobal() and relativeThreshold()
    public static let integrated = Mode(rawValue: 1 << 2)

    /// Can call loudnessRange()
    public static let loudnessRange = Mode(rawValue: 1 << 3)

    /// Can call samplePeak()
    public static let samplePeak = Mode(rawValue: 1 << 4)

    /// Can call truePeak()
    public static let truePeak = Mode(rawValue: 1 << 5)

    /// Uses histogram algorithm to calculate loudness
    public static let histogram = Mode(rawValue: 1 << 6)

    public static let all: Mode = [.momentary, .shortTerm, .integrated, .loudnessRange, .samplePeak, .truePeak]

    public let rawValue: Int
  }

  /// Error codes for EBUR128 operations
  public enum Error: Swift.Error {
    case nomem
    case invalidMode
    case invalidChannelIndex
    case noChange
  }

  /// Library version
  public static let versionMajor = 1
  public static let versionMinor = 2
  public static let versionPatch = 6
}

// MARK: - BlockEntry

/// Represents a linked list entry for block energies
class BlockEntry {
  // MARK: Lifecycle

  init(energy: Double) {
    self.energy = energy
    self.next = nil
  }

  // MARK: Internal

  let energy: Double
  var next: BlockEntry?
}

// MARK: - BlockQueue

/// Represents a queue of block entries
class BlockQueue {
  // MARK: Lifecycle

  init(maxSize: Int) {
    self.maxSize = maxSize
  }

  // MARK: Internal

  var first: BlockEntry?
  var last: BlockEntry?
  var size: Int = 0
  var maxSize: Int

  func append(_ energy: Double) {
    let entry = BlockEntry(energy: energy)

    if size == maxSize {
      // Remove first entry when queue is full
      removeFirst()
    }

    if last == nil {
      first = entry
      last = entry
    } else {
      last?.next = entry
      last = entry
    }

    size += 1
  }

  func removeFirst() {
    guard let firstEntry = first else { return }
    first = firstEntry.next
    if first == nil {
      last = nil
    }
    size -= 1
  }

  func forEach(_ body: (Double) throws -> Void) rethrows {
    var current = first
    while let entry = current {
      try body(entry.energy)
      current = entry.next
    }
  }

  func clear() {
    first = nil
    last = nil
    size = 0
  }
}
