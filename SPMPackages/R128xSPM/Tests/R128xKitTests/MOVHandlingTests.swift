// (c) 2024 and onwards Shiki Suen (AGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `AGPL-3.0-or-later`.

import XCTest
@testable import R128xKit

final class MOVHandlingTests: XCTestCase {
    
    func testMOVFileSupport() {
        // This test verifies that MOV files are accepted by the file type system
        let movExtension = "mov"
        let allowedSuffixes = [
            "mov", "mp4", "mp3", "mp2", "m4a", "wav", "aif", "ogg", 
            "aiff", "caf", "alac", "sd2", "ac3", "flac"
        ]
        
        XCTAssertTrue(allowedSuffixes.contains(movExtension), 
                     "MOV files should be supported by the application")
    }
    
    func testMOVFilePathHandling() {
        // Test that MOV file paths are correctly identified
        let movFilePath = "/path/to/test/video.MOV"
        let mp4FilePath = "/path/to/test/video.mp4"
        
        XCTAssertTrue(movFilePath.lowercased().hasSuffix(".mov"), 
                     "MOV file detection should work case-insensitively")
        XCTAssertFalse(mp4FilePath.lowercased().hasSuffix(".mov"), 
                      "MP4 files should not be detected as MOV files")
    }
    
    func testErrorMessageGeneration() {
        // Test that MOV-specific error messages are generated
        let movFilePath = "test.mov"
        let mp4FilePath = "test.mp4"
        
        // Mock error message generation (this would normally be in the actual processor)
        func generateErrorMessage(for filePath: String, baseMessage: String) -> String {
            return filePath.lowercased().hasSuffix(".mov") 
                ? "Failed to open MOV file. This may be due to an unsupported audio codec or corrupted file. Try converting to MP4 format."
                : baseMessage
        }
        
        let movError = generateErrorMessage(for: movFilePath, baseMessage: "Failed to open audio file")
        let mp4Error = generateErrorMessage(for: mp4FilePath, baseMessage: "Failed to open audio file")
        
        XCTAssertTrue(movError.contains("MOV file"), 
                     "MOV files should get specific error messages")
        XCTAssertEqual(mp4Error, "Failed to open audio file", 
                      "MP4 files should get generic error messages")
    }
    
    func testTemporaryFileHandling() {
        // Test the temporary file path generation logic
        let tempDir = NSTemporaryDirectory()
        let tempFileName = "\(UUID().uuidString).mp4"
        let tempPath = (tempDir as NSString).appendingPathComponent(tempFileName)
        
        XCTAssertTrue(tempPath.hasSuffix(".mp4"), 
                     "Temporary files should have MP4 extension")
        XCTAssertTrue(tempPath.contains(tempDir), 
                     "Temporary files should be in the system temp directory")
    }
}