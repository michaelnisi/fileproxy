// swift-tools-version:4.2

import PackageDescription

let package = Package(
  name: "fileproxy",
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
    ],
  swiftLanguageVersions: [.v4_2]
)
