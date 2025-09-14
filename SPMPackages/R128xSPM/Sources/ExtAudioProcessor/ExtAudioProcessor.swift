// (c) (C ver. only) 2012-2013 Manuel Naudin (AGPL v3.0 License or later).
// (c) (this Swift implementation) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import EBUR128
import Foundation

#if canImport(Accelerate)
import Accelerate
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif
#if canImport(CoreFoundation)
import CoreFoundation
#endif

// MARK: - Cross-platform fallbacks

#if !canImport(Accelerate)
// Fallback implementations for platforms without Accelerate
private func vDSP_maxmgvD(
  _ input: UnsafePointer<Double>, _ stride: Int, _ result: inout Double, _ count: Int
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

private typealias vDSP_Length = Int
#endif

#if !canImport(AudioToolbox)
// Placeholder types for platforms without AudioToolbox
private typealias ExtAudioFileRef = OpaquePointer
private typealias CFURL = OpaquePointer
private typealias AudioStreamBasicDescription = (
  mSampleRate: Double,
  mFormatID: UInt32,
  mFormatFlags: UInt32,
  mBytesPerPacket: UInt32,
  mFramesPerPacket: UInt32,
  mBytesPerFrame: UInt32,
  mChannelsPerFrame: UInt32,
  mBitsPerChannel: UInt32,
  mReserved: UInt32
)
private typealias AudioBufferList = (mNumberBuffers: UInt32, mBuffers: AudioBuffer)
private typealias AudioBuffer = (
  mNumberChannels: UInt32, mDataByteSize: UInt32, mData: UnsafeMutableRawPointer?
)
private typealias AudioConverterRef = OpaquePointer
private typealias OSStatus = Int32
private let noErr: OSStatus = 0
private let kAudioFormatLinearPCM: UInt32 = 1_819_304_813
private let kAudioFormatFlagIsFloat: UInt32 = 1
private let kAudioFormatFlagIsPacked: UInt32 = 8
private let kExtAudioFileProperty_FileDataFormat: UInt32 = 1_717_988_724
private let kExtAudioFileProperty_ClientDataFormat: UInt32 = 1_668_971_364
private let kExtAudioFileProperty_FileLengthFrames: UInt32 = 1_717_986_662

// Placeholder functions for platforms without AudioToolbox - all return error status
private func ExtAudioFileOpenURL(_ url: CFURL, _ audioFile: inout ExtAudioFileRef?) -> OSStatus {
  -1
}

private func ExtAudioFileDispose(_ audioFile: ExtAudioFileRef) {}
private func ExtAudioFileGetProperty(
  _ audioFile: ExtAudioFileRef,
  _ propertyID: UInt32,
  _ ioDataSize: inout UInt32,
  _ outData: UnsafeMutableRawPointer
)
  -> OSStatus { -1 }
private func ExtAudioFileSetProperty(
  _ audioFile: ExtAudioFileRef,
  _ propertyID: UInt32,
  _ inDataSize: UInt32,
  _ inData: UnsafeRawPointer
)
  -> OSStatus { -1 }
private func ExtAudioFileRead(
  _ audioFile: ExtAudioFileRef,
  _ ioNumberFrames: inout UInt32,
  _ ioData: UnsafeMutablePointer<AudioBufferList>
)
  -> OSStatus { -1 }
#endif

// MARK: - ExtAudioProcessor

/// Swift implementation of the ExtAudioProcessor functionality using Actor pattern for thread safety
public actor ExtAudioProcessor {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  // Progress tracking
  public struct ProcessingProgress: Codable, Hashable, Sendable {
    public let percentage: Double
    public let framesProcessed: Int64
    public let totalFrames: Int64
    public let currentLoudness: Double?
    public let estimatedTimeRemaining: TimeInterval?
  }

  // Progress notification name
  public static let progressNotificationName = "R128X_Progress"

  // MARK: - Main audio processing function

  /// Process an audio file and measure EBU R128 loudness metrics

  // MARK: - Public interface

  /// Main audio processing function with file identification for concurrent processing
  /// - Parameter audioFilePath: Path to the audio file
  /// - Parameter fileId: Unique identifier for tracking progress (optional)
  /// - Parameter progressCallback: Optional callback for progress updates
  /// - Parameter taskTrackingVM: Progress view model for stream-based updates
  /// - Returns: MeasuredResult containing (integrated loudness, loudness range, maximum true peak), etc.
  public func processAudioFile(
    at audioFilePath: String,
    fileId: String? = nil,
    progressCallback: ((ProcessingProgress) -> Void)? = nil,
    taskTrackingVM: TaskTrackingVMProtocol? = nil
  ) async throws
    -> MeasuredResult {
    #if canImport(AudioToolbox)

    // Add memory pressure handling for large batch processing
    defer {
      // Force memory cleanup after processing
      autoreleasepool {
        // This helps release any retained objects from AudioToolbox
      }
    }

    // Check for RF64 format and provide helpful error messages
    if RF64Support.isRF64File(at: audioFilePath) {
      let supportStatus = RF64Support.getRF64SupportStatus(for: audioFilePath)

      // Test if CoreAudio supports this RF64 file
      if !RF64Support.testCoreAudioRF64Support(at: audioFilePath) {
        throw NSError(
          domain: "ExtAudioProcessor",
          code: -1,
          userInfo: [
            NSLocalizedDescriptionKey: "RF64 format not supported by CoreAudio",
            NSLocalizedRecoverySuggestionErrorKey: supportStatus,
          ]
        )
      }
    }

    // Create URL for audio file
    let fileURL = URL(fileURLWithPath: audioFilePath)

    var audioFile: ExtAudioFileRef?
    var status = ExtAudioFileOpenURL(fileURL as CFURL, &audioFile)
    guard status == noErr, let audioFile = audioFile else {
      // Provide RF64-specific error message if this is an RF64 file
      if RF64Support.isRF64File(at: audioFilePath) {
        let supportStatus = RF64Support.getRF64SupportStatus(for: audioFilePath)
        throw NSError(
          domain: "ExtAudioProcessor",
          code: Int(status),
          userInfo: [
            NSLocalizedDescriptionKey: "Failed to open RF64 audio file",
            NSLocalizedRecoverySuggestionErrorKey: supportStatus,
          ]
        )
      }

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
    status = ExtAudioFileGetProperty(
      audioFile, kExtAudioFileProperty_FileDataFormat, &propSize, &inFileASBD
    )
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
    clientASBD.mBitsPerChannel = 32 // Still use 32-bit float, but internal processing uses Double
    clientASBD.mFramesPerPacket = 1
    clientASBD.mBytesPerFrame = 4 * clientASBD.mChannelsPerFrame
    clientASBD.mBytesPerPacket = clientASBD.mBytesPerFrame

    propSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    status = ExtAudioFileSetProperty(
      audioFile, kExtAudioFileProperty_ClientDataFormat, propSize, &clientASBD
    )
    guard status == noErr else {
      throw NSError(
        domain: "ExtAudioProcessor",
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "Failed to set client format"]
      )
    }

    // Setup oversampling factor for true peak detection
    let overSamplingFactor: Int
    if clientASBD.mSampleRate <= 48000 {
      overSamplingFactor = 4
    } else if clientASBD.mSampleRate <= 96000 {
      overSamplingFactor = 2
    } else {
      overSamplingFactor = 1
    }

    // Setup EBUR128 state
    let channels = Int(clientASBD.mChannelsPerFrame)
    let sampleRate = UInt(clientASBD.mSampleRate)
    let ebur128State = try EBUR128State(
      channels: channels, sampleRate: sampleRate, mode: [.I, .LRA, .truePeak]
    )

    // Get file length
    var fileLengthInFrames: Int64 = 0
    propSize = UInt32(MemoryLayout<Int64>.size)
    status = ExtAudioFileGetProperty(
      audioFile, kExtAudioFileProperty_FileLengthFrames, &propSize, &fileLengthInFrames
    )
    guard status == noErr else {
      throw NSError(
        domain: "ExtAudioProcessor",
        code: Int(status),
        userInfo: [NSLocalizedDescriptionKey: "Failed to get file length"]
      )
    }

    // Prepare processing variables
    let reportIntervalFrames = UInt32(clientASBD.mSampleRate / 10) // 100ms blocks
    var neededFrames = reportIntervalFrames
    var fileFramesRead: UInt32 = 0
    var fileOutBuffer = [Float](
      repeating: 0, count: Int(DEFAULT_BUFFER_SIZE * clientASBD.mChannelsPerFrame)
    )

    // Prepare for true peak analysis - use Double consistently
    var maxTruePeak = 0.0
    var maxTruePeakPosition: Int64 = 0 // Frame position where max true peak occurs

    // Optimization: use a contiguous memory region instead of separate pointer arrays
    let totalFloatBufferSize = Int(DEFAULT_BUFFER_SIZE) * channels
    let floatChannelBuffer = UnsafeMutablePointer<Double>.allocate(capacity: totalFloatBufferSize)
    defer { floatChannelBuffer.deallocate() }

    // Create view pointers for each channel (pre-allocated, reused)
    var channelPointers = [UnsafeMutablePointer<Double>?](repeating: nil, count: channels)
    for ch in 0 ..< channels {
      channelPointers[ch] = floatChannelBuffer.advanced(by: ch * Int(DEFAULT_BUFFER_SIZE))
    }

    // Pre-allocate channelPtrs array to avoid reallocating for each block
    var channelPtrs = [UnsafePointer<Double>?](repeating: nil, count: channels)

    // Use batch processing progress notifications
    var lastProgressNotificationTime = Date()
    let progressNotificationInterval = TimeInterval(0.1) // Update every 100ms for smoother progress
    let startTime = Date()

    // Set processing flag - reduce runtime checks
    let needsTruePeak = ebur128State.mode.contains(.truePeak)

    // Process audio blocks
    var continueReading = true
    while continueReading {
      // Read audio data
      var bufferList = AudioBufferList()
      bufferList.mNumberBuffers = 1
      var buffer = AudioBuffer()
      buffer.mNumberChannels = clientASBD.mChannelsPerFrame
      // Prevent arithmetic overflow when calculating buffer size
      let bufferSizeBytes = Int64(fileOutBuffer.count) * Int64(MemoryLayout<Float>.size)
      buffer.mDataByteSize = UInt32(min(bufferSizeBytes, Int64(UInt32.max)))

      fileOutBuffer.withUnsafeMutableBufferPointer { ptr in
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

      // Prevent overflow in frame counting using the same pattern as neededFrames
      let framesSumNegatable = Int64(fileFramesRead) + Int64(framesToRead)
      fileFramesRead = UInt32(min(framesSumNegatable, Int64(UInt32.max)))

      // Optimization: one-time conversion and de-interleaving of all channels
      fileOutBuffer.withUnsafeBufferPointer { bufferPtr in
        // Use vDSP for de-interleaving and converting Float->Double
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

      // Sample-position-first true peak calculation for better cache locality
      if needsTruePeak {
        var localMax = 0.0
        var localMaxPosition = 0

        // First pass: get basic peaks for all channels using vDSP
        var channelMaxes = [Double](repeating: 0.0, count: channels)
        var channelMaxPositions = [Int](repeating: 0, count: channels)

        for ch in 0 ..< channels {
          let channelBuffer = channelPointers[ch]!
          vDSP_maxmgvD(channelBuffer, 1, &channelMaxes[ch], vDSP_Length(framesToRead))

          // Find the position of the maximum value in this channel
          for i in 0 ..< Int(framesToRead) {
            if abs(channelBuffer[i]) == channelMaxes[ch] {
              channelMaxPositions[ch] = i
              break
            }
          }
        }

        // If oversampling is needed, process sample-by-sample across all channels
        if overSamplingFactor > 1 {
          // Initialize previous samples for all channels
          var prevSamples = [Double](repeating: 0.0, count: channels)
          for ch in 0 ..< channels {
            prevSamples[ch] = channelPointers[ch]![0]
          }

          // Process each sample position across all channels
          for i in 1 ..< Int(framesToRead) {
            for ch in 0 ..< channels {
              let channelBuffer = channelPointers[ch]!
              let nextSample = channelBuffer[i]

              // Linear interpolation for oversampling
              for k in 1 ..< overSamplingFactor {
                let t = Double(k) / Double(overSamplingFactor)
                let value = prevSamples[ch] * (1.0 - t) + nextSample * t
                let absValue = abs(value)
                if absValue > channelMaxes[ch] {
                  channelMaxes[ch] = absValue
                  channelMaxPositions[ch] = i
                }
              }

              prevSamples[ch] = nextSample
            }
          }
        }

        // Find which channel has the overall maximum and its position
        localMax = channelMaxes.max() ?? 0.0
        if let maxChannelIndex = channelMaxes.firstIndex(of: localMax) {
          localMaxPosition = channelMaxPositions[maxChannelIndex]
        }

        // Update global maximum and its position
        if localMax > maxTruePeak {
          maxTruePeak = localMax
          // Calculate absolute frame position: frames already read + position in current buffer
          maxTruePeakPosition = Int64(fileFramesRead - framesToRead) + Int64(localMaxPosition)
        }
      }

      // Optimization: reduce memory allocation, directly process already de-interleaved data
      var framesLeft = framesToRead
      var srcIndex = 0

      while framesLeft > 0 {
        let framesToProcess = min(framesLeft, neededFrames)

        // Fix: Ensure channelPtrs is Array and correctly assigned
        for ch in 0 ..< channels {
          if let basePtr = channelPointers[ch] {
            channelPtrs[ch] = UnsafePointer(basePtr.advanced(by: srcIndex))
          } else {
            channelPtrs[ch] = nil
          }
        }

        try await ebur128State.addFramesPointers(
          channelPtrs.compactMap { UniquePointer<Double>($0) },
          framesToProcess: Int(framesToProcess)
        )

        if framesToProcess >= neededFrames {
          // Note: We removed momentaryLoudness tracking as it wasn't being used

          // Prevent underflow in framesLeft calculation
          let framesLeftNegatable = Int32(framesLeft) - Int32(neededFrames)
          framesLeft = UInt32(max(0, framesLeftNegatable))
          srcIndex += Int(neededFrames)
          neededFrames = reportIntervalFrames
        } else {
          srcIndex += Int(framesToProcess)
          // Prevent underflow in neededFrames calculation
          let neededFramesNegatable = Int32(neededFrames) - Int32(framesToProcess)
          neededFrames = UInt32(max(0, neededFramesNegatable))
          framesLeft = 0
        }

        // Safety check to avoid infinite loop
        if framesToProcess == 0 {
          framesLeft = 0
        }

        // Ensure neededFrames doesn't become 0
        if neededFrames == 0 {
          neededFrames = reportIntervalFrames
        }
      }

      // Send progress notifications in batches
      let now = Date()
      if now.timeIntervalSince(lastProgressNotificationTime) >= progressNotificationInterval {
        let progress = Double(fileFramesRead) / Double(fileLengthInFrames)
        let progressPercentage = progress * 100.0

        // Calculate estimated time remaining
        let elapsed = now.timeIntervalSince(startTime)
        let estimatedTotal = elapsed / progress
        let estimatedRemaining = estimatedTotal - elapsed

        // Get current loudness estimate
        let currentLoudness = await ebur128State.loudnessMomentary()

        let progressInfo = ProcessingProgress(
          percentage: progressPercentage,
          framesProcessed: Int64(fileFramesRead),
          totalFrames: fileLengthInFrames,
          currentLoudness: currentLoudness.isFinite ? currentLoudness : nil,
          estimatedTimeRemaining: estimatedRemaining > 0 ? estimatedRemaining : nil
        )

        // Call progress callback if provided
        progressCallback?(progressInfo)

        // Send progress update through AsyncStream if taskTrackingVM is provided
        if let taskTrackingVM = taskTrackingVM,
           let fileId = fileId {
          let progressUpdate = ProgressUpdate(
            fileId: fileId,
            percentage: progressPercentage,
            framesProcessed: Int64(fileFramesRead),
            totalFrames: fileLengthInFrames,
            currentLoudness: currentLoudness.isFinite ? currentLoudness : nil,
            estimatedTimeRemaining: estimatedRemaining > 0 ? estimatedRemaining : nil
          )

          await MainActor.run {
            taskTrackingVM.sendProgress(progressUpdate)
          }
        }

        // Keep NotificationCenter for backward compatibility (can be removed later)
        var userInfo: [String: any Sendable] = [
          "progress": progressPercentage,
          "framesProcessed": fileFramesRead,
          "totalFrames": fileLengthInFrames,
          "currentLoudness": currentLoudness.isFinite ? currentLoudness : NSNull(),
          "estimatedTimeRemaining": estimatedRemaining > 0 ? estimatedRemaining : NSNull(),
        ]

        // Add fileId to userInfo if provided
        if let fileId = fileId {
          userInfo["fileId"] = fileId
        }

        let userInfoToSend = userInfo

        await MainActor.run {
          NotificationCenter.default.post(
            name: Notification.Name(Self.progressNotificationName),
            object: nil,
            userInfo: userInfoToSend
          )
        }
        lastProgressNotificationTime = now
      }
    }

    // Calculate final results - use Double for consistent data types
    let integratedLoudness = await ebur128State.loudnessGlobal()
    let loudnessRange = await ebur128State.loudnessRange()
    let maxTruePeakDB = 20 * log10(maxTruePeak)

    // Calculate preview time range around dBTP peak position
    let peakTimeInSeconds = Double(maxTruePeakPosition) / Double(sampleRate)
    let totalDurationInSeconds = Double(fileLengthInFrames) / Double(sampleRate)

    // Calculate 3-second preview range centered around the peak
    let previewDuration = 3.0
    let halfPreviewDuration: Double = previewDuration / 2.0

    var previewStartTime: Double = peakTimeInSeconds - halfPreviewDuration
    var previewLength: Double = previewDuration

    // Apply boundary checks
    if previewStartTime < 0 {
      previewStartTime = 0
    }

    if previewStartTime + previewLength > totalDurationInSeconds {
      previewLength = totalDurationInSeconds - previewStartTime
    }

    // Handle edge case: if preview range is longer than total audio duration
    if previewLength > totalDurationInSeconds {
      previewStartTime = 0
      previewLength = totalDurationInSeconds
    }

    // Ensure non-negative values
    previewStartTime = max(0, previewStartTime)
    previewLength = max(0, previewLength)

    return .init(
      integratedLoudness: round(integratedLoudness * 10) / 10,
      loudnessRange: round(loudnessRange * 100) / 100,
      maxTruePeak: round(maxTruePeakDB * 10) / 10,
      previewStartAtTime: previewStartTime,
      previewLength: previewLength
    )
    #else
    // On platforms without AudioToolbox, return placeholder values
    throw NSError(
      domain: "ExtAudioProcessor",
      code: -1,
      userInfo: [NSLocalizedDescriptionKey: "AudioToolbox not available on this platform"]
    )
    #endif
  }

  // MARK: Private

  // Default buffer size matching the C implementation
  private let DEFAULT_BUFFER_SIZE: UInt32 = 192000
}
