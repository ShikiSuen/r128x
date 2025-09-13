// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import Foundation

#if canImport(AudioToolbox)
import AudioToolbox
#endif

// MARK: - RF64Support

/// RF64 format support utilities for handling large WAV files (>4GB)
/// RF64 is an extension of WAV that uses 64-bit size fields
public enum RF64Support {
  // MARK: Public

  // MARK: - RF64 Errors

  public enum RF64Error: Error, LocalizedError {
    case invalidHeader
    case invalidDS64Chunk
    case notRF64File
    case coreAudioUnsupported
    case fileReadError

    // MARK: Public

    public var errorDescription: String? {
      switch self {
      case .invalidHeader:
        return "Invalid RF64 file header"
      case .invalidDS64Chunk:
        return "Invalid or missing ds64 chunk in RF64 file"
      case .notRF64File:
        return "File is not an RF64 format file"
      case .coreAudioUnsupported:
        return "CoreAudio does not support RF64 format on this system"
      case .fileReadError:
        return "Failed to read RF64 file data"
      }
    }
  }

  // MARK: - Public Interface

  /// Check if a file is in RF64 format
  /// - Parameter filePath: Path to the audio file
  /// - Returns: True if the file is RF64 format, false otherwise
  public static func isRF64File(at filePath: String) -> Bool {
    do {
      let fileURL = URL(fileURLWithPath: filePath)
      let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])

      guard data.count >= 12 else { return false }

      let header = try RF64Header(data: data)
      return header.riffChunkID == RF64_CHUNK_ID && header.format == WAVE_FORMAT_ID
    } catch {
      return false
    }
  }

  /// Attempt to test RF64 support in CoreAudio
  /// - Parameter filePath: Path to an RF64 file
  /// - Returns: True if CoreAudio can handle the RF64 file natively
  @available(macOS 10.5, iOS 2.0, *)
  public static func testCoreAudioRF64Support(at filePath: String) -> Bool {
    #if canImport(AudioToolbox)
    guard isRF64File(at: filePath) else { return false }

    let fileURL = URL(fileURLWithPath: filePath)
    var audioFile: ExtAudioFileRef?
    let status = ExtAudioFileOpenURL(fileURL as CFURL, &audioFile)

    if status == noErr, let audioFile = audioFile {
      ExtAudioFileDispose(audioFile)
      return true
    }

    return false
    #else
    return false
    #endif
  }

  /// Parse RF64 file header and extract format information
  /// - Parameter filePath: Path to the RF64 file
  /// - Returns: Tuple containing (dataSize, sampleCount, isValidRF64)
  public static func parseRF64Info(at filePath: String) throws -> (
    dataSize: UInt64, sampleCount: UInt64, isValidRF64: Bool
  ) {
    let fileURL = URL(fileURLWithPath: filePath)
    let fileHandle = try FileHandle(forReadingFrom: fileURL)
    defer { fileHandle.closeFile() }

    // Read initial header
    let headerData = fileHandle.readData(ofLength: 12)
    guard headerData.count == 12 else {
      throw RF64Error.fileReadError
    }

    let header = try RF64Header(data: headerData)

    // Check if this is actually an RF64 file
    guard header.riffChunkID == RF64_CHUNK_ID,
          header.format == WAVE_FORMAT_ID
    else {
      throw RF64Error.notRF64File
    }

    // Look for ds64 chunk
    var currentOffset = 12
    while true {
      fileHandle.seek(toFileOffset: UInt64(currentOffset))
      let chunkHeader = fileHandle.readData(ofLength: 8)
      guard chunkHeader.count == 8 else {
        throw RF64Error.invalidDS64Chunk
      }

      let chunkID = chunkHeader.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
      let chunkSize = chunkHeader.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }

      if chunkID == DS64_CHUNK_ID {
        // Found ds64 chunk - read it
        fileHandle.seek(toFileOffset: UInt64(currentOffset))
        let ds64Data = fileHandle.readData(ofLength: Int(8 + chunkSize))
        let ds64Chunk = try DS64Chunk(data: ds64Data, offset: 0)

        return (
          dataSize: ds64Chunk.dataSize,
          sampleCount: ds64Chunk.sampleCount,
          isValidRF64: true
        )
      }

      // Move to next chunk
      currentOffset += 8 + Int(chunkSize)
      if chunkSize % 2 == 1 {
        currentOffset += 1 // WAV chunks are padded to even boundaries
      }

      // Safety check to avoid infinite loop
      if currentOffset >= 1024 * 1024 { // Don't search beyond 1MB
        break
      }
    }

    throw RF64Error.invalidDS64Chunk
  }

  /// Get a user-friendly error message for RF64 issues
  /// - Parameter filePath: Path to the RF64 file
  /// - Returns: A descriptive error message about RF64 support status
  public static func getRF64SupportStatus(for filePath: String) -> String {
    guard isRF64File(at: filePath) else {
      return "File is not in RF64 format"
    }

    #if canImport(AudioToolbox)
    if testCoreAudioRF64Support(at: filePath) {
      return "RF64 format supported by CoreAudio on this system"
    } else {
      do {
        let info = try parseRF64Info(at: filePath)
        let dataSizeGB = Double(info.dataSize) / (1024.0 * 1024.0 * 1024.0)
        return String(
          format:
          "RF64 file detected (%.2f GB data). CoreAudio does not support RF64 on this system. Consider converting to multiple smaller WAV files or using a different tool.",
          dataSizeGB
        )
      } catch {
        return
          "RF64 file detected but could not parse file information: \(error.localizedDescription)"
      }
    }
    #else
    return "RF64 format detected but AudioToolbox not available on this platform"
    #endif
  }

  // MARK: Private

  // MARK: - RF64 Header Structures

  /// RF64 file header structure
  private struct RF64Header {
    // MARK: Lifecycle

    init(data: Data) throws {
      guard data.count >= 12 else {
        throw RF64Error.invalidHeader
      }

      self.riffChunkID = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
      self.chunkSize = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
      self.format = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }
    }

    // MARK: Internal

    var riffChunkID: UInt32 // "RF64"
    var chunkSize: UInt32 // Set to 0xFFFFFFFF for RF64
    var format: UInt32 // "WAVE"
  }

  /// ds64 chunk structure containing 64-bit size information
  private struct DS64Chunk {
    // MARK: Lifecycle

    init(data: Data, offset: Int) throws {
      let requiredSize = 36 // 9 * 4 bytes
      guard data.count >= offset + requiredSize else {
        throw RF64Error.invalidDS64Chunk
      }

      let chunkData = data.subdata(in: offset ..< (offset + requiredSize))

      // Initialize all properties directly from the byte data
      self.chunkID = chunkData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
      self.chunkSize = chunkData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
      self.riffSizeHigh = chunkData.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }
      self.riffSizeLow = chunkData.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self) }
      self.dataSizeHigh = chunkData.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt32.self) }
      self.dataSizeLow = chunkData.withUnsafeBytes { $0.load(fromByteOffset: 20, as: UInt32.self) }
      self.sampleCountHigh = chunkData.withUnsafeBytes {
        $0.load(fromByteOffset: 24, as: UInt32.self)
      }
      self.sampleCountLow = chunkData.withUnsafeBytes {
        $0.load(fromByteOffset: 28, as: UInt32.self)
      }
      self.tableLength = chunkData.withUnsafeBytes { $0.load(fromByteOffset: 32, as: UInt32.self) }
    }

    // MARK: Internal

    var chunkID: UInt32 // "ds64"
    var chunkSize: UInt32 // Size of ds64 chunk data
    var riffSizeHigh: UInt32 // High 32 bits of RIFF chunk size
    var riffSizeLow: UInt32 // Low 32 bits of RIFF chunk size
    var dataSizeHigh: UInt32 // High 32 bits of data chunk size
    var dataSizeLow: UInt32 // Low 32 bits of data chunk size
    var sampleCountHigh: UInt32 // High 32 bits of sample count
    var sampleCountLow: UInt32 // Low 32 bits of sample count
    var tableLength: UInt32 // Number of entries in chunk size table

    var riffSize: UInt64 {
      (UInt64(riffSizeHigh) << 32) | UInt64(riffSizeLow)
    }

    var dataSize: UInt64 {
      (UInt64(dataSizeHigh) << 32) | UInt64(dataSizeLow)
    }

    var sampleCount: UInt64 {
      (UInt64(sampleCountHigh) << 32) | UInt64(sampleCountLow)
    }
  }

  // MARK: - RF64 Format Constants

  /// RF64 RIFF chunk identifier
  private static let RF64_CHUNK_ID: UInt32 = 0x3436_4652 // "RF64" in little-endian

  /// Standard WAV RIFF chunk identifier
  private static let RIFF_CHUNK_ID: UInt32 = 0x4646_4952 // "RIFF" in little-endian

  /// ds64 chunk identifier (contains 64-bit size information)
  private static let DS64_CHUNK_ID: UInt32 = 0x3436_7364 // "ds64" in little-endian

  /// WAVE format identifier
  private static let WAVE_FORMAT_ID: UInt32 = 0x4556_4157 // "WAVE" in little-endian
}
