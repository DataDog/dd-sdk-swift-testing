// swift-tools-version:5.7.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "2.4.0"
let relaseChecksum = "6cbc4f1d4796e3aed7e534a71f9691d4305c9772443bb802a73c75681ec7f92e"
let url = "https://popovy.ch/wp-content/uploads/2024/04/DatadogSDKTesting.xcframework.zip"

let package = Package(
    name: "dd-sdk-swift-testing",
    platforms: [.macOS(.v10_13), .iOS(.v11), .tvOS(.v11)],
    products: [
        .library(name: "DatadogSDKTesting",
                 targets: ["DatadogSDKTesting"]),
    ],
    targets: [
        .binaryTarget(name: "DatadogSDKTesting",
                      url: url,
                      checksum: relaseChecksum)
    ]
)
