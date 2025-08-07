// (c) (C ver. only) 2012-2013 Manuel Naudin (AGPL v3.0 License or later).
// (c) (this Swift implementation) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

#if canImport(Accelerate)
import Accelerate
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif
#if canImport(CoreFoundation)
import CoreFoundation
#endif
import EBUR128
import Foundation

// MARK: - Cross-platform fallbacks

#if !canImport(Accelerate)
// Fallback implementations for platforms without Accelerate
private func vDSP_maxmgvD(_ input: UnsafePointer<Double>, _ stride: Int, _ result: inout Double, _ count: Int) {
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
private typealias AudioBuffer = (mNumberChannels: UInt32, mDataByteSize: UInt32, mData: UnsafeMutableRawPointer?)
private typealias AudioConverterRef = OpaquePointer
private typealias OSStatus = Int32
private let noErr: OSStatus = 0
private let kAudioFormatLinearPCM: UInt32 = 1819304813
private let kAudioFormatFlagIsFloat: UInt32 = 1
private let kAudioFormatFlagIsPacked: UInt32 = 8
private let kExtAudioFileProperty_FileDataFormat: UInt32 = 1717988724
private let kExtAudioFileProperty_ClientDataFormat: UInt32 = 1668971364
private let kExtAudioFileProperty_FileLengthFrames: UInt32 = 1717986662

// Placeholder functions for platforms without AudioToolbox - all return error status
private func ExtAudioFileOpenURL(_ url: CFURL, _ audioFile: inout ExtAudioFileRef?) -> OSStatus { -1 }
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
  // MARK: Public
  
  // Initialize the processor
  public init() {}

  // Progress tracking
  public struct ProcessingProgress {
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
  /// - Returns: Tuple containing (integrated loudness, loudness range, maximum true peak)
  public func processAudioFile(
    at audioFilePath: String,
    fileId: String? = nil,
    progressCallback: ((ProcessingProgress) -> Void)? = nil
  ) async throws
    -> (integratedLoudness: Double, loudnessRange: Double, maxTruePeak: Double) {
    #if canImport(AudioToolbox)
    // Create URL for audio file
    guard let fileURL = URL(string: "file://\(audioFilePath)") else {
      throw NSError(domain: "ExtAudioProcessor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid file path"])
    }

    var audioFile: ExtAudioFileRef?
    var status = ExtAudioFileOpenURL(fileURL as CFURL, &audioFile)
    
    // Special handling for MOV files - CoreAudio may not recognize .mov extension properly
    // even though MOV and MP4 use the same QuickTime container format
    if status != noErr && audioFilePath.lowercased().hasSuffix(".mov") {
      // Try creating a temporary URL with .mp4 extension to help CoreAudio recognize the format
      let tempDir = NSTemporaryDirectory()
      let tempFileName = "\(UUID().uuidString).mp4"
      let tempPath = (tempDir as NSString).appendingPathComponent(tempFileName)
      
      do {
        // Create a symbolic link with .mp4 extension pointing to the original MOV file
        try FileManager.default.createSymbolicLink(atPath: tempPath, withDestinationPath: audioFilePath)
        
        // Try opening the file with the .mp4 extension
        if let tempURL = URL(string: "file://\(tempPath)") {
          status = ExtAudioFileOpenURL(tempURL as CFURL, &audioFile)
          
          // Clean up the temporary symbolic link regardless of success
          defer {
            try? FileManager.default.removeItem(atPath: tempPath)
          }
        }
      } catch {
        // If symlink creation fails, fall through to the original error
      }
    }
    
    guard status == noErr, let audioFile = audioFile else {
      let errorMessage = audioFilePath.lowercased().hasSuffix(".mov") 
        ? "Failed to open MOV file. This may be due to an unsupported audio codec or corrupted file. Try converting to MP4 format."
        : "Failed to open audio file"
      
      throw NSError(
        domain: "ExtAudioProcessor",
        code: Int(status),
        userInfo: [
          NSLocalizedDescriptionKey: errorMessage,
          "OSStatus": status,
          "FilePath": audioFilePath
        ]
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
      let errorMessage = "Failed to get file format. This may indicate an unsupported audio codec in the \(audioFilePath.lowercased().hasSuffix(".mov") ? "MOV" : "") file."
      throw NSError(
        domain: "ExtAudioProcessor",
        code: Int(status),
        userInfo: [
          NSLocalizedDescriptionKey: errorMessage,
          "OSStatus": status,
          "FilePath": audioFilePath,
          "PropertyID": kExtAudioFileProperty_FileDataFormat
        ]
      )
    }

    // Log file format information for debugging MOV issues
    if audioFilePath.lowercased().hasSuffix(".mov") {
      print("DEBUG: MOV file opened successfully")
      print("  - Sample Rate: \(inFileASBD.mSampleRate)")
      print("  - Channels: \(inFileASBD.mChannelsPerFrame)")
      print("  - Format ID: 0x\(String(inFileASBD.mFormatID, radix: 16))")
      print("  - Format Flags: 0x\(String(inFileASBD.mFormatFlags, radix: 16))")
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
    status = ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, propSize, &clientASBD)
    guard status == noErr else {
      let errorMessage = audioFilePath.lowercased().hasSuffix(".mov") 
        ? "Failed to set client format for MOV file. The audio codec may not support the required PCM conversion."
        : "Failed to set client format"
        
      throw NSError(
        domain: "ExtAudioProcessor",
        code: Int(status),
        userInfo: [
          NSLocalizedDescriptionKey: errorMessage,
          "OSStatus": status,
          "FilePath": audioFilePath,
          "PropertyID": kExtAudioFileProperty_ClientDataFormat
        ]
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

    // Prepare processing variables
    let reportIntervalFrames = UInt32(clientASBD.mSampleRate / 10) // 100ms blocks
    var neededFrames = reportIntervalFrames
    var fileFramesRead: UInt32 = 0
    var fileOutBuffer = [Float](repeating: 0, count: Int(DEFAULT_BUFFER_SIZE * clientASBD.mChannelsPerFrame))

    // Prepare for true peak analysis - use Double consistently
    var maxTruePeak = 0.0

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

      // Use TaskGroup to calculate peak values for multiple channels concurrently
      if needsTruePeak {
        let channelPeaks = await withTaskGroup(of: Double.self, returning: [Double].self) { group in
          var results: [Double] = []

          for ch in 0 ..< channels {
            group.addTask {
              let channelBuffer = channelPointers[ch]!
              var channelMax = 0.0
              vDSP_maxmgvD(channelBuffer, 1, &channelMax, vDSP_Length(framesToRead))

              // Oversampling peak (linear interpolation)
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

              return channelMax
            }
          }

          for await result in group {
            results.append(result)
          }
          return results
        }

        let localMax = channelPeaks.max() ?? 0.0
        maxTruePeak = max(maxTruePeak, localMax)
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

        try await ebur128State.addFramesPointers(channelPtrs.compactMap { $0 }, framesToProcess: Int(framesToProcess))

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

        // Send notification for UI
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

    return (
      integratedLoudness: round(integratedLoudness * 10) / 10,
      loudnessRange: round(loudnessRange * 100) / 100,
      maxTruePeak: round(maxTruePeakDB * 10) / 10
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
