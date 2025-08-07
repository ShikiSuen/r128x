# MOV File Support in r128x

## Problem Description

Prior to this fix, r128x was unable to analyze `.MOV` format files for loudness measurement, despite being able to process `.MP4` files successfully. This issue existed from the project's initial version and was present in both GUI and CLI implementations.

## Root Cause Analysis

The issue was caused by Apple's CoreAudio framework (`ExtAudioFileOpenURL` function) not properly recognizing `.mov` file extensions, even though MOV and MP4 files use the same QuickTime container format. CoreAudio appears to have different behavior based on file extensions rather than analyzing the actual container format.

### Technical Details

- **Container Format**: Both MOV and MP4 use the QuickTime container format
- **Audio Processing**: CoreAudio's `ExtAudioFileOpenURL` treats extensions differently
- **File Recognition**: The framework may associate different MIME types or UTI identifiers with `.mov` vs `.mp4` extensions

## Solution Implementation

### 1. Enhanced MOV File Handling

Added special handling in `ExtAudioProcessor.swift` for MOV files:

```swift
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
```

### 2. Improved Error Messages

Added MOV-specific error messages to help users understand potential issues:

```swift
let errorMessage = audioFilePath.lowercased().hasSuffix(".mov") 
  ? "Failed to open MOV file. This may be due to an unsupported audio codec or corrupted file. Try converting to MP4 format."
  : "Failed to open audio file"
```

### 3. Enhanced Debugging Information

Added debug logging for MOV files to help identify codec and format issues:

```swift
// Log file format information for debugging MOV issues
if audioFilePath.lowercased().hasSuffix(".mov") {
  print("DEBUG: MOV file opened successfully")
  print("  - Sample Rate: \(inFileASBD.mSampleRate)")
  print("  - Channels: \(inFileASBD.mChannelsPerFrame)")
  print("  - Format ID: 0x\(String(inFileASBD.mFormatID, radix: 16))")
  print("  - Format Flags: 0x\(String(inFileASBD.mFormatFlags, radix: 16))")
}
```

### 4. Fixed CLI Implementation

- Removed dependency on missing `cExtAudioProcessor` C module
- Updated CLI to use the same Swift implementation as the GUI
- Added proper async handling for CLI processing
- Fixed Package.swift to include the CLI executable target

## Testing Methodology

### Manual Testing Steps

1. **Create test files**:
   ```bash
   # Create identical content in both formats (if ffmpeg available)
   ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -c:a aac test.mp4
   ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -c:a aac test.mov
   ```

2. **Test GUI version**:
   - Open r128x-swiftui
   - Drag both MOV and MP4 files to the interface
   - Verify both files process successfully
   - Compare loudness measurements (should be identical)

3. **Test CLI version**:
   ```bash
   ./cr128x-cli test.mp4 test.mov
   ```

4. **Verify error handling**:
   - Test with corrupted MOV files
   - Test with unsupported audio codecs
   - Verify appropriate error messages are displayed

### Automated Testing

Created unit tests in `MOVHandlingTests.swift` to verify:
- File extension detection
- Error message generation  
- Temporary file handling
- File type support validation

## Compatibility

### Supported Formats

The fix maintains compatibility with all previously supported formats:
- **Audio containers**: MP4, MOV, WAV, AIFF, CAF, M4A
- **Audio codecs**: AAC, ALAC, PCM, MP3, FLAC, AC3
- **Video containers with audio**: MOV, MP4 (audio tracks only)

### System Requirements

- **macOS**: 14.0+ (required for AudioToolbox framework)
- **Architecture**: Universal (Intel and Apple Silicon)

### Limitations

- MOV files with unsupported audio codecs will still fail (by design)
- Very large MOV files may have temporary storage requirements for the symbolic link approach
- Debug output is enabled for MOV files (can be disabled in production builds)

## Future Improvements

1. **Codec Detection**: Add pre-flight codec detection to provide better error messages
2. **UTI-based Recognition**: Explore using Uniform Type Identifiers for better format detection
3. **Performance**: Consider caching successful MOV file processing strategies
4. **Error Recovery**: Add automatic format conversion suggestions

## Known Issues

- Some very old MOV files with legacy codecs may still not be supported
- Files with DRM protection will continue to fail (expected behavior)
- Network-mounted MOV files may have additional latency due to symbolic link creation

## Migration Notes

- No breaking changes to existing API
- Existing MP4 processing remains unchanged
- New error messages provide better user guidance
- Debug output can be disabled by removing print statements in production builds