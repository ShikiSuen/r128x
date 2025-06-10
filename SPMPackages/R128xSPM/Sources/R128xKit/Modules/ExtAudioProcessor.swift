// (c) (C ver. only) 2012-2013 Manuel Naudin (AGPL v3.0 License or later).
// (c) (this Swift implementation) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Accelerate
import AudioToolbox
import EBUR128
import Foundation
import os.lock

// MARK: - ExtAudioProcessor

/// Swift implementation of the ExtAudioProcessor functionality
public class ExtAudioProcessor {
  // MARK: Public

  // Progress notification name
  public static let progressNotificationName = "R128X_Progress"

  // MARK: - Main audio processing function

  /// Process an audio file and measure EBU R128 loudness metrics
  /// - Parameter audioFilePath: Path to the audio file
  /// - Returns: Tuple containing (integrated loudness, loudness range, maximum true peak)
  public static func processAudioFile(at audioFilePath: String) throws
    -> (integratedLoudness: Double, loudnessRange: Double, maxTruePeak: Double) {
    // Create URL for audio file
    guard let fileURL = URL(string: "file://\(audioFilePath)") else {
      throw NSError(domain: "ExtAudioProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid file path"])
    }

    var audioFile: ExtAudioFileRef?
    var status = ExtAudioFileOpenURL(fileURL as CFURL, &audioFile)
    guard status == noErr, let audioFile = audioFile else {
      throw NSError(
        domain: "ExtAudioProcessor",
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "Failed to open audio file"]
      )
    }

    defer {
      ExtAudioFileDispose(audioFile)
    }

    // Get input file format
    var inFileASBD = AudioStreamBasicDescription()
    var propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    status = ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileDataFormat, &propSize, &inFileASBD)
    guard status == noErr else {
      throw NSError(
        domain: "ExtAudioProcessor",
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "Failed to get file format"]
      )
    }

    // Setup client format (float)
    var clientASBD = AudioStreamBasicDescription()
    clientASBD.mChannelsPerFrame = inFileASBD.mChannelsPerFrame
    clientASBD.mSampleRate = inFileASBD.mSampleRate
    clientASBD.mFormatID = kAudioFormatLinearPCM
    clientASBD.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
    clientASBD.mBitsPerChannel = 32 // 仍然使用32位浮点，但内部处理使用Double
    clientASBD.mFramesPerPacket = 1
    clientASBD.mBytesPerFrame = 4 * clientASBD.mChannelsPerFrame
    clientASBD.mBytesPerPacket = clientASBD.mBytesPerFrame

    propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    status = ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, propSize, &clientASBD)
    guard status == noErr else {
      throw NSError(
        domain: "ExtAudioProcessor",
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "Failed to set client format"]
      )
    }

    // Setup AudioConverter for oversampling (needed for true peak detection)
    var converterInASBD = clientASBD
    var converterOutASBD = clientASBD

    let overSamplingFactor: Int
    if clientASBD.mSampleRate <= 48000 {
      overSamplingFactor = 4
    } else if clientASBD.mSampleRate <= 96000 {
      overSamplingFactor = 2
    } else {
      overSamplingFactor = 1
    }

    converterOutASBD.mSampleRate = Float64(overSamplingFactor) * clientASBD.mSampleRate

    var converterRef: AudioConverterRef?
    status = AudioConverterNew(&converterInASBD, &converterOutASBD, &converterRef)
    guard status == noErr, let converterRef = converterRef else {
      throw NSError(
        domain: "ExtAudioProcessor",
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"]
      )
    }

    defer {
      AudioConverterDispose(converterRef)
    }

    // Setup EBUR128 state
    let channels = Int(clientASBD.mChannelsPerFrame)
    let sampleRate = UInt(clientASBD.mSampleRate)
    let ebur128State = try EBUR128State(channels: channels, sampleRate: sampleRate, mode: [.I, .LRA, .truePeak])

    // Get file length
    var fileLengthInFrames: Int64 = 0
    propSize = UInt32(MemoryLayout<Int64>.size)
    status = ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileLengthFrames, &propSize, &fileLengthInFrames)
    guard status == noErr else {
      throw NSError(
        domain: "ExtAudioProcessor",
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "Failed to get file length"]
      )
    }

    // Prepare user data - 使用 Double 数组
    let reportIntervalFrames = UInt32(clientASBD.mSampleRate / 10) // 100ms blocks
    let userData = ExtAudioData(
      audioFile: audioFile,
      state: ebur128State,
      bufferSize: Int(DEFAULT_BUFFER_SIZE * clientASBD.mChannelsPerFrame),
      reportIntervalFrames: reportIntervalFrames
    )
    userData.fileLengthInFrames = fileLengthInFrames

    // Prepare for true peak analysis - 统一使用 Double
    var maxTruePeak = 0.0

    // 优化：直接使用连续内存区域而非独立指针数组
    let totalFloatBufferSize = Int(DEFAULT_BUFFER_SIZE) * channels
    let floatChannelBuffer = UnsafeMutablePointer<Double>.allocate(capacity: totalFloatBufferSize)
    defer { floatChannelBuffer.deallocate() }

    // 为每个通道创建视图指针（預先分配，重複利用）
    var channelPointers = [UnsafeMutablePointer<Double>?](repeating: nil, count: channels)
    for ch in 0 ..< channels {
      channelPointers[ch] = floatChannelBuffer.advanced(by: ch * Int(DEFAULT_BUFFER_SIZE))
    }

    // 預先分配 channelPtrs 陣列，避免每個 block 重新分配
    var channelPtrs = [UnsafePointer<Double>?](repeating: nil, count: channels)

    // 使用批次处理进度通知
    var lastProgressNotificationTime = Date()
    let progressNotificationInterval = TimeInterval(0.5)

    // 设置处理标志 - 减少运行时检查
    let needsTruePeak = ebur128State.mode.contains(.truePeak)

    // 处理音频区块
    var continueReading = true
    while continueReading {
      // 读取音频数据
      var bufferList = AudioBufferList()
      bufferList.mNumberBuffers = 1
      var buffer = AudioBuffer()
      buffer.mNumberChannels = clientASBD.mChannelsPerFrame
      buffer.mDataByteSize = UInt32(userData.fileOutBuffer.count * MemoryLayout<Float>.size)

      userData.fileOutBuffer.withUnsafeMutableBufferPointer { ptr in
        buffer.mData = UnsafeMutableRawPointer(ptr.baseAddress)
      }
      bufferList.mBuffers = buffer

      var framesToRead: UInt32 = DEFAULT_BUFFER_SIZE
      status = ExtAudioFileRead(audioFile, &framesToRead, &bufferList)

      guard status == noErr else {
        throw NSError(
          domain: "ExtAudioProcessor",
          code: Int(status),
          userInfo: [NSLocalizedDescriptionKey: "Failed to read audio data"]
        )
      }

      if framesToRead == 0 {
        continueReading = false
        continue
      }

      userData.fileFramesRead += framesToRead

      // 优化：一次性转换并去交错所有通道
      userData.fileOutBuffer.withUnsafeBufferPointer { bufferPtr in
        // 使用 vDSP 去交錯並轉型 Float->Double
        for ch in 0 ..< channels {
          let channelBuffer = channelPointers[ch]!
          // vDSP_vspdp: float* to double*
          vDSP_vspdp(
            bufferPtr.baseAddress!.advanced(by: ch),
            channels,
            channelBuffer,
            1,
            vDSP_Length(framesToRead)
          )
        }
      }

      // 使用vDSP一次性找出最大峰值值
      if needsTruePeak {
        var localMax = 0.0

        // 合併峰值與過採樣峰值計算
        for ch in 0 ..< channels {
          let channelBuffer = channelPointers[ch]!
          var channelMax = 0.0
          vDSP_maxmgvD(channelBuffer, 1, &channelMax, vDSP_Length(framesToRead))

          // 過採樣峰值（線性插值）
          if overSamplingFactor > 1 {
            var prevSample = channelBuffer[0]
            for i in 1 ..< Int(framesToRead) {
              let nextSample = channelBuffer[i]
              for k in 1 ..< overSamplingFactor {
                let t = Double(k) / Double(overSamplingFactor)
                let value = prevSample * (1.0 - t) + nextSample * t
                channelMax = max(channelMax, abs(value))
              }
              prevSample = nextSample
            }
          }

          localMax = max(localMax, channelMax)
        }
        maxTruePeak = max(maxTruePeak, localMax)
      }

      // 优化：减少内存分配，直接处理已解交错的数据
      var framesLeft = framesToRead
      var srcIndex = 0

      while framesLeft > 0 {
        let framesToProcess = min(framesLeft, userData.neededFrames)

        // 修正：確保 channelPtrs 是 Array 並正確指派
        for ch in 0 ..< channels {
          if let basePtr = channelPointers[ch] {
            channelPtrs[ch] = UnsafePointer(basePtr.advanced(by: srcIndex))
          } else {
            channelPtrs[ch] = nil
          }
        }

        try ebur128State.addFramesPointers(channelPtrs.compactMap { $0 }, framesToProcess: Int(framesToProcess))

        if framesToProcess >= userData.neededFrames {
          let momentaryLoudness = ebur128State.loudnessMomentary()
          userData.blocks.append(momentaryLoudness)

          framesLeft -= userData.neededFrames
          srcIndex += Int(userData.neededFrames)
          userData.neededFrames = reportIntervalFrames
        } else {
          srcIndex += Int(framesToProcess)
          userData.neededFrames -= framesToProcess
          framesLeft = 0
        }

        // 安全檢查，避免無限循環
        if framesToProcess == 0 {
          framesLeft = 0
        }

        // 確保 neededFrames 不會變為 0
        if userData.neededFrames == 0 {
          userData.neededFrames = reportIntervalFrames
        }
      }

      // 批次發送進度通知
      let now = Date()
      if now.timeIntervalSince(lastProgressNotificationTime) >= progressNotificationInterval {
        let progress = Double(userData.fileFramesRead) / Double(userData.fileLengthInFrames) * 100.0
        NotificationCenter.default.post(
          name: Notification.Name(progressNotificationName),
          object: nil,
          userInfo: ["progress": progress]
        )
        lastProgressNotificationTime = now
      }
    }

    // Calculate final results - 使用Double统一数据类型
    let integratedLoudness = ebur128State.loudnessGlobal()
    let loudnessRange = ebur128State.loudnessRange()
    let maxTruePeakDB = 20 * log10(maxTruePeak)

    return (
      integratedLoudness: round(integratedLoudness * 10) / 10,
      loudnessRange: round(loudnessRange * 10) / 10,
      maxTruePeak: round(maxTruePeakDB * 10) / 10
    )
  }

  // MARK: Private

  // MARK: - Main class for audio processing state

  private class ExtAudioData {
    // MARK: Lifecycle

    init(audioFile: ExtAudioFileRef?, state: EBUR128State, bufferSize: Int, reportIntervalFrames: UInt32) {
      self.audioFile = audioFile
      self.state = state
      self.fileOutBuffer = [Float](repeating: 0, count: bufferSize)
      self.reportIntervalFrames = reportIntervalFrames
      self.neededFrames = reportIntervalFrames
    }

    // MARK: Internal

    var audioFile: ExtAudioFileRef?
    var state: EBUR128State
    var fileOutBuffer: [Float] // 保持这个作为原始读取缓冲区
    var fileFramesRead: UInt32 = 0
    var framesProduced: UInt32 = 0
    var neededFrames: UInt32
    var reportIntervalFrames: UInt32
    var fileLengthInFrames: Int64 = 0
    var blocks: [Double] = [] // For storing momentary loudness blocks
  }

  // Default buffer size matching the C implementation
  private static let DEFAULT_BUFFER_SIZE: UInt32 = 192000

  // 用於線程安全訪問的鎖 (使用 os_unfair_lock 替代已弃用的 OSSpinLock)
  private static var truePeakLock = os_unfair_lock()
}

// 用於原子操作的輔助函數
private func Float32Bits(_ value: Float) -> Int32 {
  Int32(bitPattern: UInt32(value.bitPattern))
}
