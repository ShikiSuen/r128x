# r128x, a tool for loudness measurement of files on macOS. #

Both the GUI version and the CLI version require macOS 14 since v0.7.0 release.

> This OS-requirement change is due to some needs of using newer SwiftUI APIs.
> 
> Tests proved that precompiled libraries in Audionuma's repo are still executable on macOS 15 (despite the CodeSign issues). Otherwise, I would probably hesistate to drop macOS 13 and earlier.
> 
> P.S.: Apple Silicon mac is a strong recommendation to run my fork since the libEBUR128 is completely written in Swift and the rewritten version is not hardware-accelerated as the previous C-language version. The C-language version has compilation issues on Apple Silicon while being archived for Mac App Store, hence the rewrite in Swift.

![r128x-swiftui](./screenshot.png)

r128x is released under GPLv3 license.

> For releases earlier than 0.4, please check the repo under the previous maintainer:
> - https://github.com/audionuma/r128x 

Note: GPLv3 does not hinder the copies of the compiled binaries to be sold as long as the source code is publicly available.

## Binaries ##

Binaries of all versions are not provided anymore since the release of v0.5.1.

You are expected to either compile the binary by yourself or buy at Mac App Store.

The charged fee is not mandatory since you can always compile the binaries for your own purposes.

### How to Compile ###

Xcode 26 or Swift 6.1 is recommended for the compilation. Apple always eager to push its latest toolchain as a hard requirement for compiling modern Xcode projects.

#### 1. GUI app ####

> **WARNING**: If you compile for distributing to someone else, you MUST change both the developer ID and the bundle identifier of the app in the Xcode project settings. You can go to `Targets` -> `r128x-swiftui` -> `Signing & Capabilities` and change these configurations.

1. Use Xcode to open the `r128x.xcodeproj` project file.
2. Menu: Product -> Archive.
3. After the compilation finishes, the organizer shows up. If it doesn't show up, check Menu: Window -> Organizer.
4. In the organizer, find your compiled archive, and then click the "Distribute App" button -> "Custom" -> "Direct Distribution".
5. Specify your developer certificate during the process and finish the code-signing & notarization process.
6. Export the app once the notarization is succeeded.

If not compile-for-share but for this computer only:

1. Use Xcode to open the `r128x.xcodeproj` project file.
2. Menu: Product -> Run.

#### 2. CLI app ####

1. Use Xcode to open the `R128xSPM` SPM Package from the `./SPMPackages` folder.
2. Menu: Project -> Archive.
3. After the compilation finishes, the organizer shows up. If it doesn't show up, check Menu: Window -> Organizer.
4. In the organizer, find your compiled archive, and then click the "Distribute App" button -> "Custom" -> "Direct Distribution".
5. Specify your developer certificate during the process and finish the code-signing & notarization process.
6. Export the app once the notarization is succeeded.

If not compile-for-share but for this computer only, you can use commandline to compile the project. Please refer to related Swift documentation.

## Description ##
r128x is a tool for measuring Integrated Loudness, Loudness range and Maximum True Peak of audio files on the Mac OS X system with an Intel processor.

It uses libebur128 (https://github.com/jiixyj/libebur128) for the Integrated Loudness and Loudness Range measures.

It uses CoreAudio's AudioConverter service to oversample audio data and obtain the Maximum True Peak.

It uses CoreAudio ExtAudioFile's service to read the samples from an audio file.

You can build two different binaries from the sources : a command line utility (r128x-cli) and a graphical interface utility (r128x-swiftui).

## Installation ##
You can build the executables from the Xcode project, or use the provided executables.

Just drag the executable file to your hard drive.
/usr/local/bin/ should be a nice place to put the command line binary r128x-cli if you want it to be in your $PATH.

## Usage ##
r128x-cli /some/audio/file.wav
Will print out the file name, the Integrated Loudness in LUFS, the Loudness range in LU, the Maximum True Peak in dBTP.
Will print an error message in case of unsupported file or if an error occurs during processing.

r128x-swiftui supports drag and drop of audio files. You can also use the file selector.

## Issues ##
Channel mapping is static, using the default libebur128 channel mapping :
L / R / C / LFE / Ls / Rs.
You will have incorrect results if your file's channels mapping is different.
As r128x uses CoreAudio to read audio files, only file formats/codecs supported by CoreAudio are supported by r128x.
** CoreAudio may support new formats per certain macOS releases. Please file issues if new formats are implementable in r128x.**

## Notice regarding the end of the French translation support in this Repository ##

The current maintainer Shiki Suen can only use the following languages:

- English, Japanese, Simplified Chinese, Traditional Chinese

Therefore, the French localization has to be discontinued.

The App still offers the French UI (translated using DeepL). Pull Requests for improving French Translations are still welcomed.
