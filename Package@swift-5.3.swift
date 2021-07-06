// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "0.9.1"
let relaseChecksum = "215dd1bb17e15699f27e2a3b4d6a43ebe672ae053a2cb181d60ace30b8dd993e"
let url = "https://github.com/DataDog/dd-sdk-swift-testing/releases/download/\(releaseVersion)/DatadogSDKTesting.zip"

let package = Package(
    name: "dd-sdk-swift-testing",
    platforms: [.macOS(.v10_13),
                .iOS(.v12),
                .tvOS(.v12)],
    products: [
        .library(
            name: "DatadogSDKTesting",
            targets: [
                "DatadogSDKTesting",
            ]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "DatadogSDKTesting",
            url: url,
            checksum: relaseChecksum
        )
    ]
)
