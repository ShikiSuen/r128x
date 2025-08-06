// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "R128xSPM",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "R128xKit",
      targets: ["R128xKit"]
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
      name: "libebur128"
    ),
    .target(
      name: "R128xKit",
      dependencies: [
        "R128xSharedBackend",
      ]
    ),
    .target(
      name: "R128xSharedBackend",
      dependencies: [
        "libebur128",
      ]
    ),
    .executableTarget(
      name: "r128x-cli",
      dependencies: [
        "libebur128",
        "R128xSharedBackend",
      ]
    ),
  ]
)
