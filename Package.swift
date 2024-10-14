// swift-tools-version:5.7.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "2.5.2-beta1"
let relaseChecksum = "4f1ab333e22b6908c26e0c0f2250c60f60021010fd474fce045fdcd3b36eb1ea"
let url = "https://github.com/DataDog/dd-sdk-swift-testing/releases/download/\(releaseVersion)/DatadogSDKTesting.zip"

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
