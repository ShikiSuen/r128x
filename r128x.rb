class R128x < Formula
  desc "CLI tool for loudness measurement using EBU R128 standard"
  homepage "https://github.com/ShikiSuen/r128x"
  url "https://github.com/ShikiSuen/r128x.git",
      tag:      "v0.8.0",
      revision: "97026aac2a447d62e1a27ba1eedcbc77966bb6ef"
  license "GPL-3.0-or-later"
  head "https://github.com/ShikiSuen/r128x.git", branch: "master"

  on_macos do
    depends_on xcode: :build
    depends_on macos: :sequoia
  end

  def install
    odie "r128x-cli is only supported on macOS." unless OS.mac?

    unless MacOS::Xcode.installed?
      odie <<~EOS
        A full installation of Xcode.app is required to compile this software.
        Installing just the Command Line Tools is not sufficient.
        Please install Xcode from the App Store or from:
          https://developer.apple.com/download/
        After installing Xcode, you may need to run:
          sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
      EOS
    end

    xcode_ver = MacOS::Xcode.version&.to_s
    if xcode_ver
      x_major = xcode_ver.split(".").first.to_i
      if Version.new(xcode_ver) < Version.new("16.4") && x_major < 17
        odie "Xcode 16.3 is known-broken for this build; please install Xcode 16.4 or later."
      end
    end

    # 明确使用 begin/rescue（不带显式 StandardError 类），满足 RuboCop 要求
    swift_out = ""
    begin
      swift_out = Utils.safe_popen_read("swift", "--version")
    rescue => e
      # 不要中断安装流程在这里 —— 后面会以更明确的错误消息提示用户
      swift_out = ""
      opoo "Unable to run 'swift --version': #{e.message}"
    end

    swift_ver = swift_out[/Apple Swift version (\d+\.\d+(\.\d+)?)/, 1] ||
                swift_out[/Swift version (\d+\.\d+(\.\d+)?)/, 1]

    if swift_ver.nil?
      odie <<~EOS
        Unable to determine Swift compiler version. Ensure a full Xcode with Swift >= 6.1 is installed.
      EOS
    end

    if Version.new(swift_ver) < Version.new("6.1")
      odie "r128x-cli requires Swift 6.1 or newer (Xcode 16.4+). Detected Swift #{swift_ver}."
    end

    ENV["SWIFTPM_DISABLE_SANDBOX_SHOULD_NOT_BE_USED"] = "1"
    ENV["HOMEBREW_NO_SANDBOX"] = "1"

    cd "SPMPackages/R128xSPM" do
      system "swift", "build", "--product", "r128x-cli", "-c", "release", "--disable-sandbox"

      arch = Hardware::CPU.arm? ? "arm64-apple-macosx" : "x86_64-apple-macosx"
      bin.install ".build/#{arch}/release/r128x-cli" => "r128x-cli"
    end
  end

  def caveats
    <<~EOS
      r128x-cli measures audio loudness according to EBU R128 standard.

      Usage:
        r128x-cli /path/to/audio/file.wav
    EOS
  end

  test do
    output = shell_output("#{bin}/r128x-cli 2>&1", 1)
    assert_match "Missing arguments", output
  end
end
