class R128x < Formula
  desc "CLI tool for loudness measurement using EBU R128 standard"
  homepage "https://github.com/ShikiSuen/r128x"
  url "https://github.com/ShikiSuen/r128x.git",
      tag:      "v0.8.0",
      revision: "16563f22dce6ad9e12994f09934d977339e78d82"
  license "GPL-3.0-or-later"
  head "https://github.com/ShikiSuen/r128x.git", branch: "master"

  # Requires Swift 6.1 /Xcode 16.4 for compilation
  depends_on xcode: ["16.4", :build]

  # Requires macOS 15+ as what required by Xcode 16.4
  depends_on macos: :sequoia

  def install
    # Set environment variables to avoid SwiftPM sandbox issues
    ENV["SWIFTPM_DISABLE_SANDBOX_SHOULD_NOT_BE_USED"] = "1"
    ENV["HOMEBREW_NO_SANDBOX"] = "1"

    # Navigate to the SPM package directory
    cd "SPMPackages/R128xSPM" do
      # Build the release version of r128x-cli with sandbox disabled
      system "swift", "build", "--product", "r128x-cli", "-c", "release", "--disable-sandbox"

      # Detect the architecture and install the appropriate binary
      arch = Hardware::CPU.arm? ? "arm64-apple-macosx" : "x86_64-apple-macosx"
      bin.install ".build/#{arch}/release/r128x-cli" => "r128x-cli"
    end
  end

  def caveats
    <<~EOS
      r128x-cli measures audio loudness according to EBU R128 standard.

      Usage:
        r128x-cli /path/to/audio/file.wav

      Output format:
        FILE    IL (LUFS)    LRA (LU)    MAXTP (dBTP)

      Supported formats: Any format supported by macOS CoreAudio
      (WAV, AIFF, CAF, MP3, AAC, FLAC, etc.)

      Note: RF64 files are detected but may require conversion for processing.
    EOS
  end

  test do
    # Test that the binary exists and shows help when run without arguments
    output = shell_output("#{bin}/r128x-cli 2>&1", 1)
    assert_match "Missing arguments", output
    assert_match "You should specify at least one audio file", output

    # Verify binary is executable and reports correct format
    assert_match "r128x", shell_output("#{bin}/r128x-cli 2>&1", 1)
  end
end
