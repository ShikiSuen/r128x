// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "R128xSPM",
  platforms: [
    // macOS actually requires 14+ for GUI app. But we keep 10.15 for library and CLI support.
    .macOS(.v10_15), .iOS(.v17),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "R128xGUIKit",
      targets: ["R128xGUIKit"]
    ),
    .library(
      name: "R128xCLIKit",
      targets: ["R128xCLIKit"]
    ),
    .executable(
      name: "r128x-cli",
      targets: ["r128x-cli"]
    ),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "EBUR128"
    ),
    .target(
      name: "ExtAudioProcessor",
      dependencies: [
        "EBUR128",
      ]
    ),
    .target(
      name: "R128xCLIKit",
      dependencies: [
        "ExtAudioProcessor",
      ]
    ),
    .target(
      name: "R128xGUIKit",
      dependencies: [
        "ExtAudioProcessor",
      ],
      resources: [
        .process("Resources"),
      ]
    ),
    .executableTarget(
      name: "r128x-cli",
      dependencies: [
        "R128xCLIKit",
      ]
    ),
    .testTarget(
      name: "EBUR128JoinedTests",
      dependencies: ["ExtAudioProcessor", "R128xCLIKit"]
    ),
  ]
)
