# Scripts

This directory contains utility scripts for r128x users.

## RF64 File Checker

**File:** `rf64_check.swift`

A simple utility to check if an audio file is in RF64 format.

### Usage

```bash
swift rf64_check.swift /path/to/audio/file.wav
```

### Example Output

For an RF64 file:
```
Checking: large_audio.wav
📊 File size: 8.50 GB
✅ RF64 format detected
📝 This is a large audio file using 64-bit size fields
⚠️  r128x will test CoreAudio compatibility automatically
💡 If unsupported, consider using FFmpeg to split or convert the file
```

For a regular WAV file:
```
Checking: normal_audio.wav
📊 File size: 0.05 GB
ℹ️  Not an RF64 file (likely regular WAV or other format)
✅ Should work normally with r128x
```

### What it does

- Checks if a file exists
- Reports file size in GB
- Detects RF64 format by examining file headers
- Provides guidance on compatibility with r128x

This is useful for quickly checking large audio files before processing them with r128x.