// (c) (C ver. only) 2011 Jan Kokemüller (MIT License).
// (c) (this Swift implementation) 2025 and onwards Shiki Suen (MIT License).
// ====================
// This code is released under the SPDX-License-Identifier: `MIT`.

import Accelerate
import Foundation

// MARK: - EBUR128Channel

// 重构 EBUR128Channel 枚举，使用关联值代替多个相同原始值的 case
public enum EBUR128Channel: Int, Equatable {
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
  case noChange
}

// MARK: - EBUR128Mode

public struct EBUR128Mode: OptionSet {
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

// MARK: - EBUR128State

public class EBUR128State {
  // MARK: Lifecycle

  public init(channels: Int, sampleRate: UInt, mode: EBUR128Mode) throws {
    // 先初始化臨時緩衝區變量，避免後續使用前未初始化
    self.tempBuffer = Array(repeating: 0.0, count: Int(sampleRate))
    self.tempBufferArray = Array(repeating: Array(repeating: 0.0, count: Int(sampleRate)), count: channels)

    guard channels > 0, channels <= 64 else { throw EBUR128Error.noMem }
    guard sampleRate >= 16, sampleRate <= 2822400 else { throw EBUR128Error.noMem }

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
    self.samplesIn100ms = (sampleRate + 5) / 10
    if mode.contains(.S) {
      self.window = 3000
    } else if mode.contains(.M) {
      self.window = 400
    } else {
      throw EBUR128Error.noMem
    }

    // 初始化音頻緩衝區
    self.audioDataFrames = Int(sampleRate) * Int(window) / 1000
    if audioDataFrames % Int(samplesIn100ms) != 0 {
      self.audioDataFrames = audioDataFrames + Int(samplesIn100ms) - (audioDataFrames % Int(samplesIn100ms))
    }
    self.audioData = Array(repeating: Array(repeating: 0.0, count: audioDataFrames), count: channels)
    self.audioDataIndex = 0

    // 初始化峰值相關屬性
    self.samplePeak = Array(repeating: 0.0, count: channels)
    self.prevSamplePeak = Array(repeating: 0.0, count: channels)
    self.truePeak = Array(repeating: 0.0, count: channels)
    self.prevTruePeak = Array(repeating: 0.0, count: channels)

    // 初始化濾波器
    self.filterCoefB = Array(repeating: 0.0, count: 5)
    self.filterCoefA = Array(repeating: 0.0, count: 5)
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

    // 初始化濾波器
    try initFilter()
  }

  // MARK: Public

  public let mode: EBUR128Mode
  public private(set) var channels: Int
  public private(set) var sampleRate: UInt

  // 釋放資源
  public func destroy() {
    // Swift 會自動處理內存，不需要顯式釋放
  }

  // 設置通道類型
  public func setChannel(_ channelNumber: Int, value: EBUR128Channel) throws {
    guard channelNumber < channels else { throw EBUR128Error.invalidChannelIndex }
    if value == .dualMono, channels != 1 || channelNumber != 0 {
      throw EBUR128Error.invalidChannelIndex
    }
    channelMap[channelNumber] = value
  }

  // 添加音頻幀
  // 優化 addFrames 方法
  public func addFrames(_ src: [[Double]]) throws {
    guard src.count == channels else { throw EBUR128Error.invalidChannelIndex }
    let frames = src[0].count

    // 使用預分配的陣列而非每次都創建
    // 這避免了頻繁的記憶體分配和釋放
    var srcChunk = Array(repeating: Array(repeating: 0.0, count: neededFrames), count: channels)

    // 更新 sample peak
    for c in 0 ..< channels {
      prevSamplePeak[c] = 0.0
      prevTruePeak[c] = 0.0
      for i in 0 ..< frames {
        let val = abs(src[c][i])
        if val > prevSamplePeak[c] { prevSamplePeak[c] = val }
      }
    }

    // 處理音頻幀
    var srcIndex = 0
    var framesLeft = frames

    while framesLeft > 0 {
      if framesLeft >= neededFrames {
        // 複製資料而非創建新陣列
        for c in 0 ..< channels {
          if srcIndex + neededFrames <= src[c].count {
            for i in 0 ..< neededFrames {
              srcChunk[c][i] = src[c][srcIndex + i]
            }
          }
        }

        filterSamples(srcChunk)

        srcIndex += neededFrames
        framesLeft -= neededFrames
        audioDataIndex += neededFrames * channels

        // 計算門限塊
        if mode.contains(.I) {
          var output: Double?
          _ = calcGatingBlock(framesPerBlock: Int(samplesIn100ms) * 4, optionalOutput: &output)
        }

        // 處理短期塊（LRA）
        if mode.contains(.LRA) {
          shortTermFrameCounter += neededFrames
          if shortTermFrameCounter == Int(samplesIn100ms) * 30 {
            var stEnergy: Double?
            if energyShortTerm(output: &stEnergy),
               stEnergy! >= EBUR128State.histogramEnergyBoundaries[0] {
              if useHistogram {
                let index = EBUR128State.findHistogramIndex(stEnergy!)
                shortTermBlockEnergyHistogram[index] += 1
              } else {
                shortTermBlockList.add(stEnergy!)
              }
            }
            shortTermFrameCounter = Int(samplesIn100ms) * 20
          }
        }

        // 第一個塊後的所有塊僅需要 100ms
        neededFrames = Int(samplesIn100ms)

        // 環形緩衝區處理
        if audioDataIndex == audioDataFrames * channels {
          audioDataIndex = 0
        }
      } else {
        // 處理剩餘幀
        let srcChunk = src.map { Array($0[srcIndex ..< (srcIndex + framesLeft)]) }
        filterSamples(srcChunk)

        audioDataIndex += framesLeft * channels
        if mode.contains(.LRA) {
          shortTermFrameCounter += framesLeft
        }
        neededFrames -= framesLeft
        framesLeft = 0
      }
    }

    // 計算 True Peak（使用 4x 線性插值）
    if mode.contains(.truePeak) {
      for c in 0 ..< channels {
        let buf = src[c]
        var maxTrue = 0.0
        if buf.count > 1 {
          for i in 0 ..< (buf.count - 1) {
            let s0 = buf[i]
            let s1 = buf[i + 1]
            // 4x 線性插值
            for k in 0 ..< 4 {
              let t = Double(k) / 4.0
              let v = s0 * (1.0 - t) + s1 * t
              let absV = abs(v)
              if absV > maxTrue { maxTrue = absV }
            }
          }
        } else if buf.count == 1 {
          maxTrue = abs(buf[0])
        }
        prevTruePeak[c] = maxTrue
        if maxTrue > truePeak[c] { truePeak[c] = maxTrue }
      }
    }

    // 更新 samplePeak
    for c in 0 ..< channels {
      if prevSamplePeak[c] > samplePeak[c] {
        samplePeak[c] = prevSamplePeak[c]
      }
    }
  }

  // 添加一個高效方法，可以直接處理原始指標
  public func addFramesPointers(_ src: [UnsafePointer<Double>], framesToProcess: Int) throws {
    guard src.count == channels else { throw EBUR128Error.invalidChannelIndex }

    // 更新 sample peak
    for c in 0 ..< channels {
      prevSamplePeak[c] = 0.0
      prevTruePeak[c] = 0.0

      // 使用 vDSP 快速計算峰值
      if framesToProcess > 0 {
        var peak = 0.0
        vDSP_maxmgvD(src[c], 1, &peak, vDSP_Length(framesToProcess))
        prevSamplePeak[c] = peak
      }
    }

    // 處理音頻幀 - 直接使用 filterSamplesPointers 方法
    filterSamplesPointers(src, framesToProcess: framesToProcess)

    audioDataIndex += framesToProcess * channels

    // 門限計算
    if mode.contains(.I) {
      var output: Double?
      _ = calcGatingBlock(framesPerBlock: Int(samplesIn100ms) * 4, optionalOutput: &output)
    }

    // 短期計算
    if mode.contains(.LRA) {
      shortTermFrameCounter += framesToProcess
      if shortTermFrameCounter >= Int(samplesIn100ms) * 30 {
        var stEnergy: Double?
        if energyShortTerm(output: &stEnergy),
           stEnergy! >= EBUR128State.histogramEnergyBoundaries[0] {
          if useHistogram {
            let index = EBUR128State.findHistogramIndex(stEnergy!)
            shortTermBlockEnergyHistogram[index] += 1
          } else {
            shortTermBlockList.add(stEnergy!)
          }
        }
        shortTermFrameCounter = Int(samplesIn100ms) * 20
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
      let startIndex = relativeThreshold < EBUR128State.histogramEnergyBoundaries[0] ?
        0 :
        EBUR128State.findHistogramIndex(relativeThreshold)

      for i in startIndex ..< 1000 {
        sum += Double(blockEnergyHistogram[i]) * EBUR128State.histogramEnergies[i]
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
    if energyInInterval(intervalFrames: Int(samplesIn100ms) * 4, output: &energy), energy! > 0.0 {
      return EBUR128State.energyToLoudness(energy!)
    }
    return -Double.infinity
  }

  public func loudnessShortTerm() -> Double {
    var energy: Double?
    if energyShortTerm(output: &energy), energy! > 0.0 {
      return EBUR128State.energyToLoudness(energy!)
    }
    return -Double.infinity
  }

  public func loudnessWindow(window: UInt) -> Double {
    guard window <= self.window else { return -Double.infinity }

    let frames = Int(sampleRate) * Int(window) / 1000
    var energy: Double?
    if energyInInterval(intervalFrames: frames, output: &energy), energy! > 0.0 {
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
        stlPower += Double(shortTermBlockEnergyHistogram[i]) * EBUR128State.histogramEnergies[i]
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
      if stlIntegrated >= EBUR128State.histogramEnergyBoundaries[0] {
        startIndex = EBUR128State.findHistogramIndex(stlIntegrated)
        if stlIntegrated > EBUR128State.histogramEnergies[startIndex] {
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
      let lowEnergy = EBUR128State.histogramEnergies[i - 1]

      while currentCount <= highPercentile, i < 1000 {
        currentCount += shortTermBlockEnergyHistogram[i]
        i += 1
      }
      let highEnergy = EBUR128State.histogramEnergies[i - 1]

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

      return EBUR128State.energyToLoudness(energies[highPercentile]) -
        EBUR128State.energyToLoudness(energies[lowPercentile])
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

  // MARK: Private

  // 預設和計算常數
  private static let relativeGate: Double = -10.0
  private static let relativeGateFactor = pow(10.0, relativeGate / 10.0)
  private static let minusTwentyDecibels = pow(10.0, -20.0 / 10.0)

  // 直方圖能量邊界和能量值
  private static var histogramEnergies: [Double] = {
    var energies = [Double](repeating: 0.0, count: 1000)
    for i in 0 ..< 1000 {
      energies[i] = pow(10.0, (Double(i) / 10.0 - 69.95 + 0.691) / 10.0)
    }
    return energies
  }()

  private static var histogramEnergyBoundaries: [Double] = {
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

  // 濾波器相關
  private var filterCoefB: [Double]
  private var filterCoefA: [Double]
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

  private func filterSamples(_ src: [[Double]]) {
    for c in 0 ..< channels where channelMap[c] != .unused {
      let channelData = src[c]
      let framesCount = channelData.count

      // 快速路径: 如果有足够多的数据，使用向量化操作
      if framesCount >= 8 {
        // 使用vDSP批量处理滤波器操作
        var v0 = [Double](repeating: 0, count: framesCount)

        // 为每个样本应用滤波器的第一阶段
        for i in 0 ..< framesCount {
          v0[i] = channelData[i] -
            filterCoefA[1] * filterState[c][1] -
            filterCoefA[2] * filterState[c][2] -
            filterCoefA[3] * filterState[c][3] -
            filterCoefA[4] * filterState[c][4]

          let idx = (audioDataIndex / channels + i) % audioData[c].count

          // 应用滤波器的第二阶段
          audioData[c][idx] = filterCoefB[0] * v0[i] +
            filterCoefB[1] * filterState[c][1] +
            filterCoefB[2] * filterState[c][2] +
            filterCoefB[3] * filterState[c][3] +
            filterCoefB[4] * filterState[c][4]

          // 更新滤波器状态
          filterState[c][4] = filterState[c][3]
          filterState[c][3] = filterState[c][2]
          filterState[c][2] = filterState[c][1]
          filterState[c][1] = v0[i]
        }
      } else {
        // 对于较小的帧数使用原始循环
        for i in 0 ..< framesCount {
          // 應用 IIR 濾波器
          var v0 = channelData[i]
          v0 -= filterCoefA[1] * filterState[c][1]
          v0 -= filterCoefA[2] * filterState[c][2]
          v0 -= filterCoefA[3] * filterState[c][3]
          v0 -= filterCoefA[4] * filterState[c][4]

          let idx = (audioDataIndex / channels + i) % audioData[c].count
          audioData[c][idx] = filterCoefB[0] * v0 +
            filterCoefB[1] * filterState[c][1] +
            filterCoefB[2] * filterState[c][2] +
            filterCoefB[3] * filterState[c][3] +
            filterCoefB[4] * filterState[c][4]

          // 更新濾波器狀態
          filterState[c][4] = filterState[c][3]
          filterState[c][3] = filterState[c][2]
          filterState[c][2] = filterState[c][1]
          filterState[c][1] = v0
        }
      }

      // 处理非常小的值 - 一次性处理整个状态数组
      for j in 1 ... 4 {
        if abs(filterState[c][j]) < Double.leastNormalMagnitude {
          filterState[c][j] = 0.0
        }
      }
    }
  }

  // 優化指針版本的濾波器，使用SIMD加速
  private func filterSamplesPointers(_ src: [UnsafePointer<Double>], framesToProcess: Int) {
    // 安全處理臨時緩衝區，避免懸掛指針問題
    tempBuffer.withUnsafeMutableBufferPointer { v0Buffer in
      for c in 0 ..< channels where channelMap[c] != .unused {
        let srcPtr = src[c]

        // 步骤1: 提前计算滤波器系数相关部分
        let a1Term = filterCoefA[1] * filterState[c][1]
        let a2Term = filterCoefA[2] * filterState[c][2]
        let a3Term = filterCoefA[3] * filterState[c][3]
        let a4Term = filterCoefA[4] * filterState[c][4]

        // 步骤2: 使用 vDSP 计算第一部分
        let count = min(framesToProcess, v0Buffer.count)
        for i in 0 ..< count {
          v0Buffer[i] = srcPtr[i] - a1Term - a2Term - a3Term - a4Term
        }

        // 步骤3: 计算输出并更新滤波器状态
        for i in 0 ..< count {
          let idx = (audioDataIndex / channels + i) % audioData[c].count

          // 计算输出样本
          audioData[c][idx] = filterCoefB[0] * v0Buffer[i] +
            filterCoefB[1] * filterState[c][1] +
            filterCoefB[2] * filterState[c][2] +
            filterCoefB[3] * filterState[c][3] +
            filterCoefB[4] * filterState[c][4]

          // 更新滤波器状态
          if i < framesToProcess - 1 {
            filterState[c][4] = filterState[c][3]
            filterState[c][3] = filterState[c][2]
            filterState[c][2] = filterState[c][1]
            filterState[c][1] = v0Buffer[i]
          } else {
            // 对最后一个样本特殊处理，确保状态正确
            filterState[c][4] = filterState[c][3]
            filterState[c][3] = filterState[c][2]
            filterState[c][2] = filterState[c][1]
            filterState[c][1] = v0Buffer[i]
          }
        }

        // 处理非常小的值以避免浮点精度问题
        for j in 1 ... 4 {
          if abs(filterState[c][j]) < Double.leastNormalMagnitude {
            filterState[c][j] = 0.0
          }
        }
      }
    }
  }

  // 初始化 BS.1770 濾波器係數
  private func initFilter() throws {
    let f0 = 1681.974450955533
    let G = 3.999843853973347
    let Q = 0.7071752369554196

    let K = tan(.pi * f0 / Double(sampleRate))
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
    let Kb = tan(.pi * f0b / Double(sampleRate))

    ra[1] = 2.0 * (Kb * Kb - 1.0) / (1.0 + Kb / Qb + Kb * Kb)
    ra[2] = (1.0 - Kb / Qb + Kb * Kb) / (1.0 + Kb / Qb + Kb * Kb)

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
  }

  // 計算門限塊能量
  private func calcGatingBlock(framesPerBlock: Int, optionalOutput: inout Double?) -> Bool {
    var sum = 0.0

    for c in 0 ..< channels {
      if channelMap[c] == .unused {
        continue
      }

      var channelSum = 0.0
      if audioDataIndex < framesPerBlock * channels {
        // 處理環形緩衝區邊界
        for i in 0 ..< (audioDataIndex / channels) {
          channelSum += audioData[c][i] * audioData[c][i]
        }
        for i in (audioDataFrames - (framesPerBlock - audioDataIndex / channels)) ..< audioDataFrames {
          channelSum += audioData[c][i] * audioData[c][i]
        }
      } else {
        // 正常情況
        for i in (audioDataIndex / channels - framesPerBlock) ..< (audioDataIndex / channels) {
          channelSum += audioData[c][i] * audioData[c][i]
        }
      }

      // 應用通道權重
      if channelMap[c] == .Mp110 || channelMap[c] == .Mm110 ||
        channelMap[c] == .Mp060 || channelMap[c] == .Mm060 ||
        channelMap[c] == .Mp090 || channelMap[c] == .Mm090 {
        channelSum *= 1.41
      } else if channelMap[c] == .dualMono {
        channelSum *= 2.0
      }

      sum += channelSum
    }

    sum /= Double(framesPerBlock)

    if optionalOutput != nil {
      optionalOutput = sum
      return true
    }

    // 儲存能量用於門限處理
    if sum >= EBUR128State.histogramEnergyBoundaries[0] {
      if useHistogram {
        let index = EBUR128State.findHistogramIndex(sum)
        blockEnergyHistogram[index] += 1
      } else {
        blockList.add(sum)
      }
    }

    return true
  }

  // 計算相對門限
  private func calcRelativeThreshold() -> (threshold: Double, count: Int) {
    var sum = 0.0
    var count = 0

    if useHistogram {
      for i in 0 ..< 1000 {
        sum += Double(blockEnergyHistogram[i]) * EBUR128State.histogramEnergies[i]
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
  private func energyInInterval(intervalFrames: Int, output: inout Double?) -> Bool {
    guard intervalFrames <= audioDataFrames else { return false }

    var energy: Double?
    let result = calcGatingBlock(framesPerBlock: intervalFrames, optionalOutput: &energy)
    if result, energy != nil {
      output = energy
      return true
    }
    return false
  }

  // 計算短期能量
  private func energyShortTerm(output: inout Double?) -> Bool {
    energyInInterval(intervalFrames: Int(samplesIn100ms) * 30, output: &output)
  }
}

// MARK: - Version

public func ebur128GetVersion() -> (major: Int, minor: Int, patch: Int) {
  (1, 2, 6)
}
