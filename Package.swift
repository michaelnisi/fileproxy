// swift-tools-version:5.0
import PackageDescription

let package = Package(
  name: "FileProxy",
  platforms: [
    .iOS(.v11), .macOS(.v10_13)
  ],
  products: [
    .library(
      name: "FileProxy",
      targets: ["FileProxy"]),
    ],
  dependencies: [
  ],
  targets: [
    .target(
      name: "FileProxy",
      dependencies: []),
    .testTarget(
      name: "FileProxyTests",
      dependencies: ["FileProxy"]),
  ]
)
