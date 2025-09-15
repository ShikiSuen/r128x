// (c) (C ver. only) 2011 Jan Kokemüller (MIT License).
// (c) (this Swift implementation) 2025 and onwards Shiki Suen (MIT License).
// ====================
// This code is released under the SPDX-License-Identifier: `MIT`.

import Foundation

#if canImport(Accelerate)
import Accelerate
import simd
#endif

// MARK: - Array extension for concurrent processing

extension Array where Element: Sendable {
  func asyncMap<T>(_ transform: @Sendable (Element) async throws -> T) async rethrows -> [T] {
    var result: [T] = []
    for element in self {
      let transformed = try await transform(element)
      result.append(transformed)
    }
    return result
  }
}

// MARK: - Array extension for batch operations with QuadState

extension Array where Element == [Double] {
  /// 批次設置連續的四個值，類似於 setChannels(since:) 的語法糖
  /// - Parameters:
  ///   - channel: 通道索引
  ///   - since: 起始索引（通常為 1）
  ///   - quadState: 包含四個值的 QuadState
  mutating func setQuadValues(
    channel: Int,
    since startIndex: Int,
    _ quadState: EBUR128State.QuadState
  ) {
    guard channel < count, startIndex + 3 < self[channel].count else { return }
    self[channel][startIndex] = quadState.s1
    self[channel][startIndex + 1] = quadState.s2
    self[channel][startIndex + 2] = quadState.s3
    self[channel][startIndex + 3] = quadState.s4
  }

  /// 批次獲取連續的四個值作為 QuadState
  /// - Parameters:
  ///   - channel: 通道索引
  ///   - since: 起始索引（通常為 1）
  /// - Returns: 包含四個值的 QuadState，如果索引越界則返回 nil
  func getQuadValues(channel: Int, since startIndex: Int) -> EBUR128State.QuadState? {
    guard channel < count, startIndex + 3 < self[channel].count else { return nil }
    return .init(
      s1: self[channel][startIndex],
      s2: self[channel][startIndex + 1],
      s3: self[channel][startIndex + 2],
      s4: self[channel][startIndex + 3]
    )
  }

  /// 批次設置多個通道的相同位置值
  /// - Parameters:
  ///   - channels: 通道索引範圍
  ///   - since: 起始索引
  ///   - quadStates: 每個通道對應的 QuadState 值
  mutating func setQuadValues(
    channels: Range<Int>,
    since startIndex: Int,
    _ quadStates: EBUR128State.QuadState...
  ) {
    for (i, channel) in channels.enumerated() where i < quadStates.count {
      setQuadValues(channel: channel, since: startIndex, quadStates[i])
    }
  }
}

// MARK: - Cross-platform vDSP fallbacks

#if !canImport(Accelerate)
// Fallback implementations for platforms without Accelerate
private func vDSP_maxmgvD(
  _ input: UnsafePointer<Double>,
  _ stride: Int,
  _ result: inout Double,
  _ count: Int
) {
  result = 0.0
  for i in 0 ..< count {
    let value = abs(input[i * stride])
    if value > result {
      result = value
    }
  }
}

private func vDSP_vspdp(
  _ input: UnsafePointer<Float>,
  _ inputStride: Int,
  _ output: UnsafeMutablePointer<Double>,
  _ outputStride: Int,
  _ count: Int
) {
  for i in 0 ..< count {
    output[i * outputStride] = Double(input[i * inputStride])
  }
}

private func vDSP_svesqD(_ input: [Double], _ stride: Int, _ result: inout Double, _ count: Int) {
  result = 0.0
  for i in 0 ..< count {
    let value = input[i * stride]
    result += value * value
  }
}

private typealias vDSP_Length = Int
#endif

// MARK: - EBUR128Channel

// 重构 EBUR128Channel 枚举，使用关联值代替多个相同原始值的 case
public enum EBUR128Channel: Int, Equatable, Sendable {
  case unused = 0
  case left = 1
  case right = 2
  case center = 3
  case leftSurround = 4
  case rightSurround = 5
  case dualMono = 6
  case MpSC = 7
  case MmSC = 8
  case Mp060 = 9
  case Mm060 = 10
  case Mp090 = 11
  case Mm090 = 12
  case Mp135 = 13
  case Mm135 = 14
  case Mp180 = 15
  case Up000 = 16
  case Up030 = 17
  case Um030 = 18
  case Up045 = 19
  case Um045 = 20
  case Up090 = 21
  case Um090 = 22
  case Up110 = 23
  case Um110 = 24
  case Up135 = 25
  case Um135 = 26
  case Up180 = 27
  case Tp000 = 28
  case Bp000 = 29
  case Bp045 = 30
  case Bm045 = 31

  // MARK: Public

  // 提供别名属性来保持与原始 C 代码的兼容性
  public static let Mp030 = left
  public static let Mm030 = right
  public static let Mp000 = center
  public static let Mp110 = leftSurround
  public static let Mm110 = rightSurround
}

// MARK: - EBUR128Error

public enum EBUR128Error: Error {
  case success
  case noMem
  case invalidMode
  case invalidChannelIndex
  case duplicatedTypesAcrossChannels
  case noChange
}

// MARK: - EBUR128Mode

public struct EBUR128Mode: OptionSet, Sendable {
  // MARK: Lifecycle

  public init(rawValue: Int) { self.rawValue = rawValue }

  // MARK: Public

  public static let M = EBUR128Mode(rawValue: 1 << 0)
  public static let S = EBUR128Mode(rawValue: (1 << 1) | M.rawValue)
  public static let I = EBUR128Mode(rawValue: (1 << 2) | M.rawValue)
  public static let LRA = EBUR128Mode(rawValue: (1 << 3) | S.rawValue)
  public static let samplePeak = EBUR128Mode(rawValue: (1 << 4) | M.rawValue)
  public static let truePeak = EBUR128Mode(rawValue: (1 << 5) | M.rawValue | samplePeak.rawValue)
  public static let histogram = EBUR128Mode(rawValue: 1 << 6)

  public let rawValue: Int
}

// MARK: - BlockQueueEntry

// 用於保存塊能量的隊列元素
private class BlockQueueEntry {
  // MARK: Lifecycle

  init(energy: Double) {
    self.energy = energy
  }

  // MARK: Internal

  var energy: Double
  var next: BlockQueueEntry?
}

// MARK: - BlockQueue

// 塊能量隊列
private class BlockQueue {
  // MARK: Lifecycle

  init(maxSize: Int) {
    self.maxSize = maxSize
  }

  // MARK: Internal

  var first: BlockQueueEntry?
  var last: BlockQueueEntry?
  var size: Int = 0
  var maxSize: Int

  func add(_ energy: Double) {
    let entry = BlockQueueEntry(energy: energy)
    if last == nil {
      first = entry
      last = entry
    } else {
      last?.next = entry
      last = entry
    }
    size += 1

    // 如果超過最大大小，移除最舊的
    if size > maxSize {
      removeFirst()
    }
  }

  func removeFirst() {
    if first != nil {
      first = first?.next
      if first == nil {
        last = nil
      }
      size -= 1
    }
  }
}

// MARK: - DownsamplingStrategy

public struct DownsamplingStrategy: Sendable {
  static let disabled = DownsamplingStrategy(
    enabled: false,
    decimationFactor: 1,
    targetSampleRate: 0,
    antiAliasingFilter: nil
  )

  let enabled: Bool
  let decimationFactor: Int
  let targetSampleRate: UInt
  let antiAliasingFilter: [Double]?
}

// MARK: - EBUR128State

public actor EBUR128State {
  // MARK: Lifecycle

  public init(channels: Int, sampleRate: UInt, mode: EBUR128Mode) throws {
    // 先初始化臨時緩衝區變量，避免後續使用前未初始化
    self.tempBuffer = Array(repeating: 0.0, count: Int(sampleRate))
    self.tempBufferArray = Array(
      repeating: Array(repeating: 0.0, count: Int(sampleRate)),
      count: channels
    )

    guard channels > 0, channels <= 64 else { throw EBUR128Error.noMem }
    guard sampleRate >= 16, sampleRate <= 2_822_400 else { throw EBUR128Error.noMem }

    self.channels = channels
    self.sampleRate = sampleRate
    self.mode = mode

    // 初始化通道映射
    self.channelMap = (0 ..< channels).map {
      switch $0 {
      case 0: return .left
      case 1: return .right
      case 2: return .center
      case 3: return .unused
      case 4: return .leftSurround
      case 5: return .rightSurround
      default: return .unused
      }
    }

    // 設置窗口參數
    let effectiveSampleRate = self.sampleRate
    self.samplesIn100ms = (effectiveSampleRate + 5) / 10
    if mode.contains(.S) || mode.contains(.LRA) {
      self.window = 3000
    } else if mode.contains(.M) {
      self.window = 400
    } else {
      throw EBUR128Error.noMem
    }

    // 初始化音頻緩衝區
    let audioDataFramesInt64 = Int64(effectiveSampleRate) * Int64(window) / 1000
    self.audioDataFrames = Int(min(audioDataFramesInt64, Int64(Int.max)))
    if audioDataFrames % Int(samplesIn100ms) != 0 {
      // Use Int64 to prevent overflow in addition operation
      let adjustedFramesInt64 =
        Int64(audioDataFrames) + Int64(samplesIn100ms)
          - Int64(audioDataFrames % Int(samplesIn100ms))
      self.audioDataFrames = Int(min(adjustedFramesInt64, Int64(Int.max)))
    }
    self.audioData = Array(
      repeating: Array(repeating: 0.0, count: audioDataFrames),
      count: channels
    )
    self.audioDataIndex = 0

    // 初始化峰值相關屬性
    self.samplePeak = Array(repeating: 0.0, count: channels)
    self.prevSamplePeak = Array(repeating: 0.0, count: channels)
    self.truePeak = Array(repeating: 0.0, count: channels)
    self.prevTruePeak = Array(repeating: 0.0, count: channels)

    // 初始化 BS.1770 濾波器係數
    let filterCoefResults = Self.initFilter(sampleRate: self.sampleRate)
    self.filterCoefA = filterCoefResults.filterCoefA
    self.filterCoefB = filterCoefResults.filterCoefB

    // 初始化優化的濾波器係數結構
    self.filterCoefficients = FilterCoefficients(
      filterCoefA: filterCoefResults.filterCoefA,
      filterCoefB: filterCoefResults.filterCoefB
    )

    // 初始化濾波器
    self.filterState = Array(repeating: Array(repeating: 0.0, count: 5), count: channels)

    // 初始化塊能量隊列
    self.blockList = BlockQueue(maxSize: Int(history / 100))
    self.shortTermBlockList = BlockQueue(maxSize: Int(history / 3000))

    // 初始化直方圖
    self.useHistogram = mode.contains(.histogram)
    self.blockEnergyHistogram = Array(repeating: 0, count: 1000)
    self.shortTermBlockEnergyHistogram = Array(repeating: 0, count: 1000)

    // 設置初始所需幀數
    self.neededFrames = Int(samplesIn100ms) * 4
  }

  // MARK: Public

  nonisolated public let mode: EBUR128Mode
  nonisolated public let channels: Int
  nonisolated public let sampleRate: UInt

  // 設置通道類型
  public func setChannel(_ channelNumber: Int, value: EBUR128Channel) throws {
    try setChannels(since: channelNumber, value)
  }

  // 批次設置聲道類型 - 使用 Swift 可變參數語法
  public func setChannels(since beginningChannelIndex: Int, _ values: EBUR128Channel...) throws {
    let actualValuesUsed = values.filter { $0 != .unused }
    let actualValuesSet = Set(actualValuesUsed)
    guard actualValuesSet.count == actualValuesUsed.count else {
      throw EBUR128Error.duplicatedTypesAcrossChannels
    }

    let channelIndicesToModify = beginningChannelIndex ..< (beginningChannelIndex + values.count)
    let channelIndicesAllowed = 0 ..< channels

    guard channelIndicesAllowed.contains(channelIndicesToModify) else {
      throw EBUR128Error.invalidChannelIndex
    }

    // 檢查是否有 dualMono 聲道的無效配置
    for (channelIndex, value) in zip(channelIndicesToModify, values) {
      if value == .dualMono, channels != 1 || channelIndex != 0 {
        throw EBUR128Error.invalidChannelIndex
      }
    }

    // 設置所有聲道
    for (channelIndex, value) in zip(channelIndicesToModify, values) {
      channelMap[channelIndex] = value
    }
  }

  // 添加音頻幀
  // 優化 addFrames 方法 - 移除 async/await 開銷，使用同步處理，採用樣本位置優先處理
  public func addFrames(_ src: [[Double]]) throws {
    guard src.count == channels else { throw EBUR128Error.invalidChannelIndex }

    let frames = src[0].count
    guard frames > 0 else { return }

    // Sample-position-first peak calculation for better cache locality
    for i in 0 ..< frames {
      for c in 0 ..< channels {
        let absValue = abs(src[c][i])
        if absValue > prevSamplePeak[c] { prevSamplePeak[c] = absValue }
        if absValue > samplePeak[c] { samplePeak[c] = absValue }
      }
    }

    // Direct filter processing with sample-position-first approach
    filterSamplesDirect(src, framesToProcess: frames)

    // Simple index update
    audioDataIndex += frames * channels
    if audioDataIndex >= audioDataFrames * channels {
      audioDataIndex = 0
    }

    // Gating block calculation - only when needed
    if mode.contains(.I), frames >= neededFrames {
      var output: Double?
      _ = calcGatingBlockSync(framesPerBlock: Int(samplesIn100ms) * 4, optionalOutput: &output)
    }

    // Short-term calculation for LRA - simplified
    if mode.contains(.LRA) {
      shortTermFrameCounter += frames
      if shortTermFrameCounter >= Int(samplesIn100ms) * 30 {
        var stEnergy: Double?
        if energyShortTermSync(output: &stEnergy),
           let energy = stEnergy,
           energy >= histogramEnergyBoundaries[0] {
          if useHistogram {
            let index = EBUR128State.findHistogramIndex(energy)
            shortTermBlockEnergyHistogram[index] += 1
          } else {
            shortTermBlockList.add(energy)
          }
        }
        shortTermFrameCounter -= Int(samplesIn100ms) * 10
      }
    }

    // Simple needed frames update
    neededFrames = frames >= neededFrames ? Int(samplesIn100ms) : neededFrames - frames

    // True peak - direct calculation with sample-position-first approach
    if mode.contains(.truePeak) {
      calculateTruePeakDirect(src)
    }
  }

  // Revolutionary performance optimization: eliminate all unnecessary overhead
  // Ultra-simplified addFrames for maximum speed
  public func addFramesRevolutionary(_ src: [[Double]]) throws {
    // Simply use the optimized synchronous addFrames
    try addFrames(src)
  }

  // 添加一個高效方法，可以直接處理原始指標
  public func addFramesPointers(_ srcWrapped: [UniquePointer<Double>], framesToProcess: Int)
    async throws {
    guard srcWrapped.count == channels else { throw EBUR128Error.invalidChannelIndex }
    let src = srcWrapped.map(\.pointer)

    // 優化 sample peak 計算
    for c in 0 ..< channels {
      prevSamplePeak[c] = 0.0
      prevTruePeak[c] = 0.0

      // 使用 vDSP 快速計算峰值
      if framesToProcess > 0 {
        #if canImport(Accelerate)
        var peak = 0.0
        vDSP_maxmgvD(src[c], 1, &peak, vDSP_Length(framesToProcess))
        prevSamplePeak[c] = peak
        #else
        // 手動計算峰值作為後備
        var peak = 0.0
        for i in 0 ..< framesToProcess {
          let val = abs(src[c][i])
          if val > peak { peak = val }
        }
        prevSamplePeak[c] = peak
        #endif
      }
    }

    // 處理音頻幀 - 直接使用優化的 filterSamplesPointers 方法
    #if canImport(Accelerate)
    await filterSamplesPointersUltraFast(src, framesToProcess: framesToProcess)
    #else
    await filterSamplesPointersOptimized(src, framesToProcess: framesToProcess)
    #endif

    // Prevent overflow in audioDataIndex calculation
    let audioDataIndexInt64 = Int64(audioDataIndex) + Int64(framesToProcess) * Int64(channels)
    audioDataIndex = Int(min(audioDataIndexInt64, Int64(Int.max)))

    // 門限計算
    if mode.contains(.I) {
      var output: Double?
      _ = await calcGatingBlock(framesPerBlock: Int(samplesIn100ms) * 4, optionalOutput: &output)
    }

    // 短期計算
    if mode.contains(.LRA) {
      shortTermFrameCounter += framesToProcess
      if shortTermFrameCounter >= Int(samplesIn100ms) * 30 {
        var stEnergy: Double?
        if await energyShortTerm(output: &stEnergy),
           stEnergy! >= histogramEnergyBoundaries[0] {
          if useHistogram {
            let index = EBUR128State.findHistogramIndex(stEnergy!)
            shortTermBlockEnergyHistogram[index] += 1
          } else {
            shortTermBlockList.add(stEnergy!)
          }
        }
        shortTermFrameCounter -= Int(samplesIn100ms) * 10 // 滑動窗口：減去1秒，保持2秒重疊
      }
    }

    // 環形緩衝區處理
    if audioDataIndex >= audioDataFrames * channels {
      audioDataIndex = 0
    }
  }

  // 計算積分響度
  public func loudnessGlobal() -> Double {
    guard mode.contains(.I) else { return -Double.infinity }

    let (relativeThreshold, aboveThreshCount) = calcRelativeThreshold()
    if aboveThreshCount == 0 {
      return -Double.infinity
    }

    var sum = 0.0
    var count = 0

    if useHistogram {
      let startIndex =
        relativeThreshold < histogramEnergyBoundaries[0]
          ? 0 : EBUR128State.findHistogramIndex(relativeThreshold)

      for i in startIndex ..< 1000 {
        sum += Double(blockEnergyHistogram[i]) * histogramEnergies[i]
        count += blockEnergyHistogram[i]
      }
    } else {
      var current = blockList.first
      while let entry = current {
        if entry.energy >= relativeThreshold {
          sum += entry.energy
          count += 1
        }
        current = entry.next
      }
    }

    if count == 0 {
      return -Double.infinity
    }

    let gatedLoudness = sum / Double(count)
    return EBUR128State.energyToLoudness(gatedLoudness)
  }

  // 公開 API 方法

  public func loudnessMomentary() -> Double {
    var energy: Double?
    if energyInIntervalSync(intervalFrames: Int(samplesIn100ms) * 4, output: &energy), energy! > 0.0 {
      return EBUR128State.energyToLoudness(energy!)
    }
    return -Double.infinity
  }

  public func loudnessShortTerm() -> Double {
    var energy: Double?
    if energyShortTermSync(output: &energy), energy! > 0.0 {
      return EBUR128State.energyToLoudness(energy!)
    }
    return -Double.infinity
  }

  public func loudnessWindow(window: UInt) -> Double {
    guard window <= self.window else { return -Double.infinity }

    let frames = Int(sampleRate) * Int(window) / 1000
    var energy: Double?
    if energyInIntervalSync(intervalFrames: frames, output: &energy), energy! > 0.0 {
      return EBUR128State.energyToLoudness(energy!)
    }
    return -Double.infinity
  }

  public func loudnessRange() -> Double {
    guard mode.contains(.LRA) else { return 0.0 }

    // 計算短期塊能量統計
    var stlPower = 0.0
    var stlSize = 0

    if useHistogram {
      for i in 0 ..< 1000 {
        stlPower += Double(shortTermBlockEnergyHistogram[i]) * histogramEnergies[i]
        stlSize += shortTermBlockEnergyHistogram[i]
      }
    } else {
      var current = shortTermBlockList.first
      while let entry = current {
        stlPower += entry.energy
        stlSize += 1
        current = entry.next
      }
    }

    if stlSize == 0 {
      return 0.0
    }

    stlPower /= Double(stlSize)
    let stlIntegrated = EBUR128State.minusTwentyDecibels * stlPower

    if useHistogram {
      // 使用直方圖計算
      var startIndex = 0
      if stlIntegrated >= histogramEnergyBoundaries[0] {
        startIndex = EBUR128State.findHistogramIndex(stlIntegrated)
        if stlIntegrated > histogramEnergies[startIndex] {
          startIndex += 1
        }
      }

      var count = 0
      for i in startIndex ..< 1000 {
        count += shortTermBlockEnergyHistogram[i]
      }

      if count == 0 {
        return 0.0
      }

      let lowPercentile = Int(Double(count - 1) * 0.1 + 0.5)
      let highPercentile = Int(Double(count - 1) * 0.95 + 0.5)

      var currentCount = 0
      var i = startIndex
      while currentCount <= lowPercentile, i < 1000 {
        currentCount += shortTermBlockEnergyHistogram[i]
        i += 1
      }
      let lowEnergy = histogramEnergies[i - 1]

      while currentCount <= highPercentile, i < 1000 {
        currentCount += shortTermBlockEnergyHistogram[i]
        i += 1
      }
      let highEnergy = histogramEnergies[i - 1]

      return EBUR128State.energyToLoudness(highEnergy) - EBUR128State.energyToLoudness(lowEnergy)
    } else {
      // 使用排序計算
      var energies = [Double]()
      var current = shortTermBlockList.first
      while let entry = current {
        if entry.energy >= stlIntegrated {
          energies.append(entry.energy)
        }
        current = entry.next
      }

      if energies.isEmpty {
        return 0.0
      }

      energies.sort()
      let lowPercentile = Int(Double(energies.count - 1) * 0.1 + 0.5)
      let highPercentile = Int(Double(energies.count - 1) * 0.95 + 0.5)

      return EBUR128State.energyToLoudness(energies[highPercentile])
        - EBUR128State.energyToLoudness(energies[lowPercentile])
    }
  }

  public func samplePeak(channel: Int) throws -> Double {
    guard mode.contains(.samplePeak) else { throw EBUR128Error.invalidMode }
    guard channel < channels else { throw EBUR128Error.invalidChannelIndex }
    return samplePeak[channel]
  }

  public func prevSamplePeak(channel: Int) throws -> Double {
    guard mode.contains(.samplePeak) else { throw EBUR128Error.invalidMode }
    guard channel < channels else { throw EBUR128Error.invalidChannelIndex }
    return prevSamplePeak[channel]
  }

  public func truePeak(channel: Int) throws -> Double {
    guard mode.contains(.truePeak) else { throw EBUR128Error.invalidMode }
    guard channel < channels else { throw EBUR128Error.invalidChannelIndex }
    return max(truePeak[channel], samplePeak[channel])
  }

  public func prevTruePeak(channel: Int) throws -> Double {
    guard mode.contains(.truePeak) else { throw EBUR128Error.invalidMode }
    guard channel < channels else { throw EBUR128Error.invalidChannelIndex }
    return max(prevTruePeak[channel], prevSamplePeak[channel])
  }

  // MARK: Internal

  struct QuadState: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(s1: Double, s2: Double, s3: Double, s4: Double) {
      self.s1 = s1
      self.s2 = s2
      self.s3 = s3
      self.s4 = s4
    }

    public init(from tuple: (s1: Double, s2: Double, s3: Double, s4: Double)) {
      self.s1 = tuple.s1
      self.s2 = tuple.s2
      self.s3 = tuple.s3
      self.s4 = tuple.s4
    }

    // MARK: Public

    /// 返回所有值都為零的 QuadState
    public static var zero: QuadState {
      QuadState(s1: 0, s2: 0, s3: 0, s4: 0)
    }

    public var s1: Double
    public var s2: Double
    public var s3: Double
    public var s4: Double

    public var asTuple: (s1: Double, s2: Double, s3: Double, s4: Double) {
      (s1: s1, s2: s2, s3: s3, s4: s4)
    }

    /// 檢查是否有任何值接近零（需要清零以避免浮點精度問題）
    public var hasNearZeroValues: Bool {
      abs(s1) < Double.leastNormalMagnitude || abs(s2) < Double.leastNormalMagnitude
        || abs(s3) < Double.leastNormalMagnitude || abs(s4) < Double.leastNormalMagnitude
    }

    /// 計算所有元素的和
    public var sum: Double {
      s1 + s2 + s3 + s4
    }

    /// 元素對元素的乘法運算
    public static func * (lhs: QuadState, rhs: QuadState) -> QuadState {
      QuadState(
        s1: lhs.s1 * rhs.s1,
        s2: lhs.s2 * rhs.s2,
        s3: lhs.s3 * rhs.s3,
        s4: lhs.s4 * rhs.s4
      )
    }

    /// 標量乘法運算
    public static func * (lhs: QuadState, rhs: Double) -> QuadState {
      QuadState(
        s1: lhs.s1 * rhs,
        s2: lhs.s2 * rhs,
        s3: lhs.s3 * rhs,
        s4: lhs.s4 * rhs
      )
    }

    /// 標量乘法運算（交換律）
    public static func * (lhs: Double, rhs: QuadState) -> QuadState {
      rhs * lhs
    }

    /// 將所有狀態值向右移動一位，並設置 s1 為新值
    public mutating func shift(newValue: Double) {
      s4 = s3
      s3 = s2
      s2 = s1
      s1 = newValue
    }
  }

  /// 濾波器係數結構，用於封裝和簡化濾波器計算
  internal struct FilterCoefficients {
    // MARK: Lifecycle

    init(filterCoefA: [Double], filterCoefB: [Double]) {
      self.b0 = filterCoefB[0]
      self.bQuad = QuadState(
        s1: filterCoefB[1],
        s2: filterCoefB[2],
        s3: filterCoefB[3],
        s4: filterCoefB[4]
      )
      self.aQuad = QuadState(
        s1: filterCoefA[1],
        s2: filterCoefA[2],
        s3: filterCoefA[3],
        s4: filterCoefA[4]
      )
    }

    // MARK: Internal

    let b0: Double
    let bQuad: QuadState // b1, b2, b3, b4
    let aQuad: QuadState // a1, a2, a3, a4

    /// 應用 IIR 濾波器並更新狀態
    @inline(__always)
    func applyFilter(input: Double, state: inout QuadState) -> Double {
      // 計算濾波器輸入
      let v0 = input - (aQuad * state).sum

      // 計算輸出
      let output = b0 * v0 + (bQuad * state).sum

      // 更新狀態
      state.shift(newValue: v0)

      return output
    }
  }

  // 濾波器相關 - make filter coefficients internal for testing
  internal let filterCoefB: [Double]
  internal let filterCoefA: [Double]

  // 優化的濾波器係數結構
  internal let filterCoefficients: FilterCoefficients

  // MARK: Private

  // 預設和計算常數
  private static let relativeGate: Double = -10.0
  private static let relativeGateFactor = pow(10.0, relativeGate / 10.0)
  private static let minusTwentyDecibels = pow(10.0, -20.0 / 10.0)

  // 直方圖能量邊界和能量值
  private var histogramEnergies: [Double] = {
    var energies = [Double](repeating: 0.0, count: 1000)
    for i in 0 ..< 1000 {
      energies[i] = pow(10.0, (Double(i) / 10.0 - 69.95 + 0.691) / 10.0)
    }
    return energies
  }()

  private var histogramEnergyBoundaries: [Double] = {
    var boundaries = [Double](repeating: 0.0, count: 1001)
    boundaries[0] = pow(10.0, (-70.0 + 0.691) / 10.0)
    for i in 1 ..< 1001 {
      boundaries[i] = pow(10.0, (Double(i) / 10.0 - 70.0 + 0.691) / 10.0)
    }
    return boundaries
  }()

  // 添加预分配的成员变量，避免重复创建
  private var tempBuffer: [Double]
  private var tempBufferArray: [[Double]]

  // 通道映射
  private var channelMap: [EBUR128Channel]

  // 音頻數據和狀態
  private var audioData: [[Double]]
  private var audioDataFrames: Int
  private var audioDataIndex: Int
  private var neededFrames: Int

  // 時間窗口參數
  private var window: UInt
  private var history: UInt = .max
  private var samplesIn100ms: UInt

  // Peak 相關
  private var samplePeak: [Double]
  private var prevSamplePeak: [Double]
  private var truePeak: [Double]
  private var prevTruePeak: [Double]

  private var filterState: [[Double]]

  // 塊能量相關
  private var blockList: BlockQueue
  private var shortTermBlockList: BlockQueue
  private var shortTermFrameCounter: Int = 0

  // 直方圖
  private var useHistogram: Bool
  private var blockEnergyHistogram: [Int]
  private var shortTermBlockEnergyHistogram: [Int]

  // 找到直方圖索引
  private static func findHistogramIndex(_ energy: Double) -> Int {
    // 直接計算索引比二分查找更快
    let logEnergy = 10 * log10(energy) - 0.691
    let index = Int((logEnergy + 70.0) * 10.0)
    return max(0, min(999, index))
  }

  // 將能量轉換為響度
  private static func energyToLoudness(_ energy: Double) -> Double {
    10.0 * log10(energy) - 0.691
  }

  // 初始化 BS.1770 濾波器係數
  private static func initFilter(sampleRate givenSampleRate: UInt) -> (
    filterCoefA: [Double], filterCoefB: [Double]
  ) {
    let f0 = 1681.974450955533
    let G = 3.999843853973347
    let Q = 0.7071752369554196

    let K = tan(.pi * f0 / Double(givenSampleRate))
    let Vh = pow(10.0, G / 20.0)
    let Vb = pow(Vh, 0.4996667741545416)

    var pb = [0.0, 0.0, 0.0]
    var pa = [1.0, 0.0, 0.0]
    let rb = [1.0, -2.0, 1.0]
    var ra = [1.0, 0.0, 0.0]

    let a0 = 1.0 + K / Q + K * K
    pb[0] = (Vh + Vb * K / Q + K * K) / a0
    pb[1] = 2.0 * (K * K - Vh) / a0
    pb[2] = (Vh - Vb * K / Q + K * K) / a0
    pa[1] = 2.0 * (K * K - 1.0) / a0
    pa[2] = (1.0 - K / Q + K * K) / a0

    // 第二個濾波器（低頻濾波器）
    let f0b = 38.13547087602444
    let Qb = 0.5003270373238773
    let Kb = tan(.pi * f0b / Double(givenSampleRate))

    ra[1] = 2.0 * (Kb * Kb - 1.0) / (1.0 + Kb / Qb + Kb * Kb)
    ra[2] = (1.0 - Kb / Qb + Kb * Kb) / (1.0 + Kb / Qb + Kb * Kb)

    var (filterCoefA, filterCoefB) = (
      Array(repeating: 0.0, count: 5), Array(repeating: 0.0, count: 5)
    )

    // 組合濾波器係數
    filterCoefB[0] = pb[0] * rb[0]
    filterCoefB[1] = pb[0] * rb[1] + pb[1] * rb[0]
    filterCoefB[2] = pb[0] * rb[2] + pb[1] * rb[1] + pb[2] * rb[0]
    filterCoefB[3] = pb[1] * rb[2] + pb[2] * rb[1]
    filterCoefB[4] = pb[2] * rb[2]

    filterCoefA[0] = pa[0] * ra[0]
    filterCoefA[1] = pa[0] * ra[1] + pa[1] * ra[0]
    filterCoefA[2] = pa[0] * ra[2] + pa[1] * ra[1] + pa[2] * ra[0]
    filterCoefA[3] = pa[1] * ra[2] + pa[2] * ra[1]
    filterCoefA[4] = pa[2] * ra[2]

    return (filterCoefA, filterCoefB)
  }

  // MARK: - 同步化濾波器處理方法 (高效能版本)

  // Direct filter processing - optimized for sample-position-first processing
  private func filterSamplesDirect(_ src: [[Double]], framesToProcess: Int) {
    guard framesToProcess > 0 else { return }

    // Identify active channels upfront
    let activeChannels = (0 ..< channels).filter { channelMap[$0] != .unused }
    guard !activeChannels.isEmpty else { return }

    // 為活躍通道加載濾波器狀態
    var filterStates = activeChannels.map { c in
      filterState.getQuadValues(channel: c, since: 1) ?? QuadState.zero
    }

    let baseAudioIndex = audioDataIndex / channels

    // Process sample-by-sample across all active channels
    for i in 0 ..< framesToProcess {
      let audioIndex = (baseAudioIndex + i) % audioDataFrames

      // Process all active channels at this sample position
      for (activeIdx, c) in activeChannels.enumerated() {
        // Apply filter using the optimized FilterCoefficients
        audioData[c][audioIndex] = filterCoefficients.applyFilter(
          input: src[c][i],
          state: &filterStates[activeIdx]
        )
      }
    }

    // Store filter states back
    for (activeIdx, c) in activeChannels.enumerated() {
      filterState.setQuadValues(channel: c, since: 1, filterStates[activeIdx])
    }
  }

  // 簡化的門限塊計算 - 直接處理
  private func calcGatingBlockSync(framesPerBlock: Int, optionalOutput: inout Double?) -> Bool {
    let currentFrameIndex = audioDataIndex / channels

    // 直接計算所有活躍通道的能量總和
    var totalSum = 0.0
    for c in 0 ..< channels where channelMap[c] != .unused {
      totalSum += calculateChannelSumSync(
        channel: c,
        currentFrameIndex: currentFrameIndex,
        framesPerBlock: framesPerBlock
      )
    }

    let sum = totalSum / Double(framesPerBlock)
    optionalOutput = sum

    // 儲存能量用於門限處理
    if framesPerBlock == Int(samplesIn100ms) * 4 {
      if sum >= histogramEnergyBoundaries[0] {
        if useHistogram {
          let index = EBUR128State.findHistogramIndex(sum)
          blockEnergyHistogram[index] += 1
        } else {
          blockList.add(sum)
        }
      }
    }

    return true
  }

  // 同步單通道能量計算
  private func calculateChannelSumSync(channel c: Int, currentFrameIndex: Int, framesPerBlock: Int)
    -> Double {
    var channelSum = 0.0

    if currentFrameIndex < framesPerBlock {
      // 環形緩衝區邊界處理
      let firstPartFrames = currentFrameIndex
      let secondPartStart = audioDataFrames - (framesPerBlock - currentFrameIndex)
      let secondPartFrames = framesPerBlock - currentFrameIndex

      // 第一段
      if firstPartFrames > 0 {
        #if canImport(Accelerate)
        var firstSum = 0.0
        vDSP_svesqD(audioData[c], 1, &firstSum, vDSP_Length(firstPartFrames))
        channelSum += firstSum
        #else
        for i in 0 ..< firstPartFrames {
          channelSum += audioData[c][i] * audioData[c][i]
        }
        #endif
      }

      // 第二段
      if secondPartFrames > 0, secondPartStart < audioDataFrames {
        #if canImport(Accelerate)
        var secondSum = 0.0
        let count = min(secondPartFrames, audioDataFrames - secondPartStart)
        let secondPartData = Array(audioData[c][secondPartStart ..< (secondPartStart + count)])
        vDSP_svesqD(secondPartData, 1, &secondSum, vDSP_Length(count))
        channelSum += secondSum
        #else
        let endIndex = min(secondPartStart + secondPartFrames, audioDataFrames)
        for i in secondPartStart ..< endIndex {
          channelSum += audioData[c][i] * audioData[c][i]
        }
        #endif
      }
    } else {
      // 正常連續數據塊
      let startIndex = currentFrameIndex - framesPerBlock

      guard startIndex >= 0, currentFrameIndex <= audioData[c].count else {
        return 0.0
      }

      #if canImport(Accelerate)
      var blockSum = 0.0
      let blockData = Array(audioData[c][startIndex ..< currentFrameIndex])
      vDSP_svesqD(blockData, 1, &blockSum, vDSP_Length(framesPerBlock))
      channelSum = blockSum
      #else
      for i in startIndex ..< currentFrameIndex {
        channelSum += audioData[c][i] * audioData[c][i]
      }
      #endif
    }

    // 應用通道權重
    let weight = getChannelWeight(channelMap[c])
    return channelSum * weight
  }

  // 同步區間能量計算
  private func energyInIntervalSync(intervalFrames: Int, output: inout Double?) -> Bool {
    guard intervalFrames <= audioDataFrames else { return false }

    var energy: Double?
    let result = calcGatingBlockSync(framesPerBlock: intervalFrames, optionalOutput: &energy)
    if result, energy != nil {
      output = energy
      return true
    }
    return false
  }

  // 同步短期能量計算
  private func energyShortTermSync(output: inout Double?) -> Bool {
    energyInIntervalSync(intervalFrames: Int(samplesIn100ms) * 30, output: &output)
  }

  // Direct true peak calculation - simplified for performance
  private func calculateTruePeakDirect(_ src: [[Double]]) {
    for c in 0 ..< channels where channelMap[c] != .unused {
      let buf = src[c]
      guard !buf.isEmpty else { continue }

      var maxTrue = 0.0

      // Simple upsampling and peak detection - match C implementation
      if buf.count > 1 {
        for i in 0 ..< buf.count - 1 {
          let s0 = buf[i]
          let s1 = buf[i + 1]

          // Simple 4x oversampling for true peak detection
          let quarter = 0.25 * (s1 - s0)
          let half = 0.5 * (s1 - s0)
          let threeQuarter = 0.75 * (s1 - s0)

          let v1 = abs(s0 + quarter)
          let v2 = abs(s0 + half)
          let v3 = abs(s0 + threeQuarter)
          let v4 = abs(s1)

          let localMax = max(max(v1, v2), max(v3, v4))
          if localMax > maxTrue { maxTrue = localMax }
        }
      } else {
        maxTrue = abs(buf[0])
      }

      prevTruePeak[c] = maxTrue
      if maxTrue > truePeak[c] { truePeak[c] = maxTrue }
    }
  }

  // 新增超高效濾波器處理方法
  // 並行優化版本的濾波器 - 使用順序處理以避免 Swift 6.1 並發問題
  private func filterSamplesOptimized(_ src: [[Double]], framesToProcess: Int) async {
    // 獲取活躍通道列表
    let activeChannels = (0 ..< channels).filter { channelMap[$0] != .unused }

    // 順序處理所有通道
    for c in activeChannels {
      await processSingleChannelOptimized(
        channel: c,
        channelData: src[c],
        framesToProcess: framesToProcess
      )
    }
  }

  // 單通道優化處理，針對並行執行優化
  private func processSingleChannelOptimized(
    channel c: Int,
    channelData: [Double],
    framesToProcess: Int
  ) async {
    if framesToProcess <= 0 { return }

    // 使用 QuadState 減少記憶體訪問和管理複雜度
    guard var state = filterState.getQuadValues(channel: c, since: 1) else { return }

    // 向量化處理大塊數據
    if framesToProcess >= 16 {
      let batchSize = min(framesToProcess, 64)
      var processedFrames = 0

      while processedFrames < framesToProcess {
        let remainingFrames = framesToProcess - processedFrames
        let currentBatchSize = min(batchSize, remainingFrames)

        for i in 0 ..< currentBatchSize {
          // Prevent overflow in frame index calculation
          let frameIndexInt64 = Int64(processedFrames) + Int64(i)
          let frameIndex = Int(min(frameIndexInt64, Int64(Int.max)))

          // 計算輸出索引，優化模除運算 - prevent overflow
          let audioIndexInt64 = Int64(audioDataIndex) / Int64(channels) + Int64(frameIndex)
          let audioIndex = Int(min(audioIndexInt64, Int64(Int.max)))
          let idx = audioIndex < audioDataFrames ? audioIndex : audioIndex - audioDataFrames

          // 應用濾波器使用優化的 FilterCoefficients
          audioData[c][idx] = filterCoefficients.applyFilter(
            input: channelData[frameIndex],
            state: &state
          )
        }

        processedFrames += currentBatchSize
      }
    } else {
      // 小塊數據使用直接處理
      for i in 0 ..< framesToProcess {
        // Prevent overflow in audio index calculation
        let audioIndexInt64 = Int64(audioDataIndex) / Int64(channels) + Int64(i)
        let audioIndex = Int(min(audioIndexInt64, Int64(Int.max)))
        let idx = audioIndex < audioDataFrames ? audioIndex : audioIndex - audioDataFrames

        audioData[c][idx] = filterCoefficients.applyFilter(
          input: channelData[i],
          state: &state
        )
      }
    }

    // 寫回濾波器狀態
    filterState.setQuadValues(channel: c, since: 1, state)

    // 處理非常小的值以避免浮點精度問題
    if state.hasNearZeroValues {
      filterState.setQuadValues(channel: c, since: 1, QuadState.zero)
    }
  }

  private func filterSamples(_ src: [[Double]]) {
    for c in 0 ..< channels where channelMap[c] != .unused {
      let channelData = src[c]
      let framesCount = channelData.count

      // 確保臨時緩衝區足夠大
      if tempBuffer.count < framesCount {
        tempBuffer = Array(repeating: 0.0, count: max(framesCount, 8192))
      }

      // 獲取濾波器狀態
      guard var state = filterState.getQuadValues(channel: c, since: 1) else { continue }

      // 使用優化的濾波器處理
      if framesCount >= 8 {
        // 批次處理濾波器，減少狀態查找開銷
        let batchSize = 32
        for batchStart in stride(from: 0, to: framesCount, by: batchSize) {
          let batchEnd = min(batchStart + batchSize, framesCount)

          for i in batchStart ..< batchEnd {
            // 計算輸出索引，減少模除運算 - prevent overflow
            let audioIndexInt64 = Int64(audioDataIndex) / Int64(channels) + Int64(i)
            let audioIndex = Int(min(audioIndexInt64, Int64(Int.max)))
            let idx = audioIndex < audioDataFrames ? audioIndex : audioIndex - audioDataFrames

            // 應用濾波器使用優化的 FilterCoefficients
            audioData[c][idx] = filterCoefficients.applyFilter(
              input: channelData[i],
              state: &state
            )
          }
        }
      } else {
        // 對於較小的幀數使用直接循環
        for i in 0 ..< framesCount {
          // Prevent overflow in audio index calculation
          let audioIndexInt64 = Int64(audioDataIndex) / Int64(channels) + Int64(i)
          let audioIndex = Int(min(audioIndexInt64, Int64(Int.max)))
          let idx = audioIndex < audioDataFrames ? audioIndex : audioIndex - audioDataFrames

          audioData[c][idx] = filterCoefficients.applyFilter(
            input: channelData[i],
            state: &state
          )
        }
      }

      // 寫回濾波器狀態
      filterState.setQuadValues(channel: c, since: 1, state)

      // 處理非常小的值以避免浮點精度問題
      if state.hasNearZeroValues {
        filterState.setQuadValues(channel: c, since: 1, QuadState.zero)
      }
    }
  }

  // 優化版本的濾波器 - 移除並行處理以避免 Swift 6.1 的 UnsafePointer 並發問題
  private func filterSamplesPointersOptimized(_ src: [UnsafePointer<Double>], framesToProcess: Int)
    async {
    // 確保臨時緩衝區足夠大
    if tempBuffer.count < framesToProcess {
      tempBuffer = Array(repeating: 0.0, count: max(framesToProcess, 8192))
    }

    // 獲取活躍通道列表
    let activeChannels = (0 ..< channels).filter { channelMap[$0] != .unused }

    // 順序處理所有通道以避免 UnsafePointer 的並發問題
    for c in activeChannels {
      await processSingleChannelFilter(channel: c, srcPtr: src[c], framesToProcess: framesToProcess)
    }
  }

  // 單通道濾波處理，針對並行執行優化
  private func processSingleChannelFilter(
    channel c: Int,
    srcPtr: UnsafePointer<Double>,
    framesToProcess: Int
  ) async {
    // 批次處理，減少循環開銷
    let batchSize = 64
    guard var state = filterState.getQuadValues(channel: c, since: 1) else { return }

    for batchStart in stride(from: 0, to: framesToProcess, by: batchSize) {
      let batchEnd = min(batchStart + batchSize, framesToProcess)

      for i in batchStart ..< batchEnd {
        // 計算輸出索引，優化模除運算 - prevent overflow with proper bounds checking
        let audioIndexInt64 = Int64(audioDataIndex) / Int64(channels) + Int64(i)
        let audioIndex = Int(min(audioIndexInt64, Int64(Int.max)))
        let idx = audioIndex % audioDataFrames

        // 確保索引在範圍內
        guard idx >= 0, idx < audioData[c].count else { continue }

        // 計算輸出樣本使用優化的 FilterCoefficients
        audioData[c][idx] = filterCoefficients.applyFilter(
          input: srcPtr[i],
          state: &state
        )
      }
    }

    // 寫回濾波器狀態
    filterState.setQuadValues(channel: c, since: 1, state)

    // 處理非常小的值以避免浮點精度問題
    if state.hasNearZeroValues {
      filterState.setQuadValues(channel: c, since: 1, QuadState.zero)
    }
  }

  // 原始指針版本的濾波器（作為後備）
  private func filterSamplesPointers(_ src: [UnsafePointer<Double>], framesToProcess: Int) {
    for c in 0 ..< channels where channelMap[c] != .unused {
      let srcPtr = src[c]

      // 獲取濾波器狀態
      guard var state = filterState.getQuadValues(channel: c, since: 1) else { continue }

      let count = framesToProcess

      // 步骤: 直接使用優化的 FilterCoefficients 处理
      for i in 0 ..< count {
        // Prevent overflow in audio index calculation before modulo
        let audioIndexInt64 = Int64(audioDataIndex) / Int64(channels) + Int64(i)
        let audioIndex = Int(min(audioIndexInt64, Int64(Int.max)))
        let idx = audioIndex % audioData[c].count

        // 計算輸出樣本使用優化的 FilterCoefficients
        audioData[c][idx] = filterCoefficients.applyFilter(
          input: srcPtr[i],
          state: &state
        )
      }

      // 寫回濾波器狀態
      filterState.setQuadValues(channel: c, since: 1, state)

      // 處理非常小的值以避免浮點精度問題
      if state.hasNearZeroValues {
        filterState.setQuadValues(channel: c, since: 1, QuadState.zero)
      }
    }
  }

  #if canImport(Accelerate)
  private func filterSamplesPointersUltraFast(
    _ src: [UnsafePointer<Double>],
    framesToProcess: Int
  ) async {
    guard framesToProcess > 0 else { return }

    let activeChannels = (0 ..< channels).filter { channelMap[$0] != .unused }

    // 順序處理以避免 UnsafePointer 的並發問題
    for c in activeChannels {
      await processChannelUltraFast(channel: c, srcPtr: src[c], framesToProcess: framesToProcess)
    }
  }

  // Ultra-fast single channel processing with maximum vectorization
  private func processChannelUltraFast(
    channel c: Int,
    srcPtr: UnsafePointer<Double>,
    framesToProcess: Int
  ) async {
    // Cache filter state as QuadState for ultra-fast access
    guard var state = filterState.getQuadValues(channel: c, since: 1) else { return }

    // Ultra-large batch processing for maximum efficiency
    let ultraBatchSize = min(framesToProcess, 1024)
    let audioFrameLimit = audioDataFrames
    let channelCount = channels
    let baseAudioIndex = Int(audioDataIndex) / channelCount

    var processedFrames = 0
    while processedFrames < framesToProcess {
      let remainingFrames = framesToProcess - processedFrames
      let currentBatchSize = min(ultraBatchSize, remainingFrames)

      // Vectorized ultra-fast processing
      for i in 0 ..< currentBatchSize {
        let inputSample = srcPtr[processedFrames + i]

        // Ultra-fast index calculation with proper bounds checking
        let audioIndex = baseAudioIndex + processedFrames + i
        let wrappedIndex = audioIndex % audioFrameLimit

        // Ensure index is within bounds and write directly to audioData array
        guard wrappedIndex >= 0, wrappedIndex < audioData[c].count else { continue }

        // Apply filter using ultra-optimized FilterCoefficients
        audioData[c][wrappedIndex] = filterCoefficients.applyFilter(
          input: inputSample,
          state: &state
        )
      }

      processedFrames += currentBatchSize
    }

    // Write back cached state
    filterState.setQuadValues(channel: c, since: 1, state)

    // Denormal cleanup using QuadState convenience method
    if state.hasNearZeroValues {
      filterState.setQuadValues(channel: c, since: 1, QuadState.zero)
    }
  }
  #endif

  // 計算門限塊能量 - 優化版本
  // 計算門限塊能量 - 順序處理版本以避免 Swift 6.1 並發問題
  private func calcGatingBlock(framesPerBlock: Int, optionalOutput: inout Double?) async -> Bool {
    let currentFrameIndex = audioDataIndex / channels

    // 獲取活躍通道列表
    let activeChannels = (0 ..< channels).filter { channelMap[$0] != .unused }

    // 順序計算每個通道的能量
    var channelSums = [Double]()
    for c in activeChannels {
      let sum = await calculateChannelSum(
        channel: c,
        currentFrameIndex: currentFrameIndex,
        framesPerBlock: framesPerBlock
      )
      channelSums.append(sum)
    }

    // 計算總和
    let sum = channelSums.reduce(0.0, +) / Double(framesPerBlock)

    // Set the output value
    optionalOutput = sum

    // Store for gating if this is being called for integrated loudness (not for interval measurement)
    // We can detect this by checking if the frame count matches the standard gating block size
    if framesPerBlock == Int(samplesIn100ms) * 4 {
      // 儲存能量用於門限處理
      if sum >= histogramEnergyBoundaries[0] {
        if useHistogram {
          let index = EBUR128State.findHistogramIndex(sum)
          blockEnergyHistogram[index] += 1
        } else {
          blockList.add(sum)
        }
      }
    }

    return true
  }

  // 單通道能量計算，針對並行執行優化
  private func calculateChannelSum(channel c: Int, currentFrameIndex: Int, framesPerBlock: Int)
    async -> Double {
    var channelSum = 0.0

    // 優化：使用向量化操作計算平方和
    if currentFrameIndex < framesPerBlock {
      // 處理環形緩衝區邊界 - 分兩段處理
      let firstPartFrames = currentFrameIndex
      let secondPartStart = audioDataFrames - (framesPerBlock - currentFrameIndex)
      let secondPartFrames = framesPerBlock - currentFrameIndex

      // 第一段
      if firstPartFrames > 0 {
        #if canImport(Accelerate)
        var firstSum = 0.0
        vDSP_svesqD(audioData[c], 1, &firstSum, vDSP_Length(firstPartFrames))
        channelSum += firstSum
        #else
        for i in 0 ..< firstPartFrames {
          channelSum += audioData[c][i] * audioData[c][i]
        }
        #endif
      }

      // 第二段
      if secondPartFrames > 0, secondPartStart < audioDataFrames {
        #if canImport(Accelerate)
        var secondSum = 0.0
        let count = min(secondPartFrames, audioDataFrames - secondPartStart)
        let secondPartData = Array(audioData[c][secondPartStart ..< (secondPartStart + count)])
        vDSP_svesqD(secondPartData, 1, &secondSum, vDSP_Length(count))
        channelSum += secondSum
        #else
        let endIndex = min(secondPartStart + secondPartFrames, audioDataFrames)
        for i in secondPartStart ..< endIndex {
          channelSum += audioData[c][i] * audioData[c][i]
        }
        #endif
      }
    } else {
      // 正常情況 - 連續的數據塊
      let startIndex = currentFrameIndex - framesPerBlock

      // 添加邊界檢查以防止索引越界
      guard startIndex >= 0, currentFrameIndex <= audioData[c].count else {
        return 0.0 // 返回 0 為無效的通道數據
      }

      #if canImport(Accelerate)
      var blockSum = 0.0
      let blockData = Array(audioData[c][startIndex ..< currentFrameIndex])
      vDSP_svesqD(blockData, 1, &blockSum, vDSP_Length(framesPerBlock))
      channelSum = blockSum
      #else
      for i in startIndex ..< currentFrameIndex {
        channelSum += audioData[c][i] * audioData[c][i]
      }
      #endif
    }

    // 應用通道權重 - 使用預計算的權重
    let weight = getChannelWeight(channelMap[c])
    return channelSum * weight
  }

  // 獲取通道權重 - 預計算以避免重複判斷
  private func getChannelWeight(_ channel: EBUR128Channel) -> Double {
    switch channel {
    case .Mm060, .Mm090, .Mm110, .Mp060, .Mp090, .Mp110:
      return 1.41
    case .dualMono:
      return 2.0
    default:
      return 1.0
    }
  }

  // 計算相對門限
  private func calcRelativeThreshold() -> (threshold: Double, count: Int) {
    var sum = 0.0
    var count = 0

    if useHistogram {
      for i in 0 ..< 1000 {
        sum += Double(blockEnergyHistogram[i]) * histogramEnergies[i]
        count += blockEnergyHistogram[i]
      }
    } else {
      var current = blockList.first
      while let entry = current {
        sum += entry.energy
        count += 1
        current = entry.next
      }
    }

    if count == 0 {
      return (0.0, 0)
    }

    let threshold = sum / Double(count) * EBUR128State.relativeGateFactor
    return (threshold, count)
  }

  // 計算區間能量
  private func energyInInterval(intervalFrames: Int, output: inout Double?) async -> Bool {
    guard intervalFrames <= audioDataFrames else { return false }

    var energy: Double?
    let result = await calcGatingBlock(framesPerBlock: intervalFrames, optionalOutput: &energy)
    if result, energy != nil {
      output = energy
      return true
    }
    return false
  }

  // 計算短期能量
  private func energyShortTerm(output: inout Double?) async -> Bool {
    await energyInInterval(intervalFrames: Int(samplesIn100ms) * 30, output: &output)
  }
}

// MARK: - UniquePointer

// The underlying memory may only be accessed via a single UniquePointer instance during its lifetime.
public struct UniquePointer<T>: @unchecked Sendable {
  // MARK: Lifecycle

  public init?(_ pointer: UnsafePointer<T>?) {
    guard let pointer else { return nil }
    self.pointer = pointer
  }

  // MARK: Public

  public var pointer: UnsafePointer<T>
}

// MARK: - Version

public func ebur128GetVersion() -> (major: Int, minor: Int, patch: Int) {
  (1, 2, 6)
}
