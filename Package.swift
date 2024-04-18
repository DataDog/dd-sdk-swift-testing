// swift-tools-version:5.7.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "2.4.0"
let relaseChecksum = "c6a92de0407dc8ed42da36f9c15795e2d2eac66b5f16f82d0a22926060f64bfa"
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
