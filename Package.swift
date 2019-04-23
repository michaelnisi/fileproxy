// swift-tools-version:5.0
import PackageDescription

let package = Package(
  name: "fileproxy",
  platforms: [
    .iOS(.v11), .macOS(.v10_13)
  ],
  products: [
    .library(
      name: "fileproxy",
      targets: ["fileproxy"]),
    ],
  dependencies: [
  ],
  targets: [
    .target(
      name: "fileproxy",
      dependencies: []),
    .testTarget(
      name: "fileproxyTests",
      dependencies: ["fileproxy"]),
  ]
)
