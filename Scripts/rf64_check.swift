#!/usr/bin/env swift

// RF64 File Checker - A simple utility to check if a file is RF64 format
// Usage: swift rf64_check.swift <audio_file>

import Foundation

guard CommandLine.argc >= 2 else {
    print("RF64 File Checker")
    print("Usage: swift rf64_check.swift <audio_file>")
    print("\nThis utility checks if an audio file is in RF64 format.")
    exit(1)
}

let filePath = CommandLine.arguments[1]

// Simple RF64 detection function
func isRF64File(at path: String) -> Bool {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else {
        return false
    }
    
    guard data.count >= 12 else { return false }
    
    let riffChunkID = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
    let format = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }
    
    return riffChunkID == 0x34364652 && format == 0x45564157 // "RF64" and "WAVE"
}

func getFileSize(at path: String) -> String {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attributes[.size] as? Int64 else {
        return "Unknown"
    }
    
    let sizeGB = Double(size) / (1024.0 * 1024.0 * 1024.0)
    return String(format: "%.2f GB", sizeGB)
}

func checkFile(at path: String) {
    let fileURL = URL(fileURLWithPath: path)
    let fileName = fileURL.lastPathComponent
    
    print("Checking: \(fileName)")
    
    guard FileManager.default.fileExists(atPath: path) else {
        print("❌ File not found")
        return
    }
    
    let fileSize = getFileSize(at: path)
    print("📊 File size: \(fileSize)")
    
    if isRF64File(at: path) {
        print("✅ RF64 format detected")
        print("📝 This is a large audio file using 64-bit size fields")
        print("⚠️  r128x will test CoreAudio compatibility automatically")
        print("💡 If unsupported, consider using FFmpeg to split or convert the file")
    } else {
        print("ℹ️  Not an RF64 file (likely regular WAV or other format)")
        print("✅ Should work normally with r128x")
    }
}

checkFile(at: filePath)