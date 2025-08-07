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
      name: "cr128x-cli",
      targets: ["cr128x-cli"]
    ),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "EBUR128"
    ),
    .target(
      name: "R128xKit",
      dependencies: [
        "EBUR128",
      ],
      resources: [
        .process("Resources"),
      ]
    ),
    .executableTarget(
      name: "cr128x-cli",
      dependencies: [
        "R128xKit",
      ]
    ),
    .testTarget(
      name: "EBUR128Tests",
      dependencies: ["EBUR128", "R128xKit"]
    ),
    .testTarget(
      name: "R128xKitTests", 
      dependencies: ["R128xKit"]
    ),
  ]
)
