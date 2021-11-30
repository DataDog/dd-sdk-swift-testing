// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "1.0.2"
let relaseChecksum = "5efc8d9986700f63b2d6eb92bdb9869d0064e8e8d691ee85acc2a141d9a7edab"
let url = "https://github.com/DataDog/dd-sdk-swift-testing/releases/download/\(releaseVersion)/DatadogSDKTesting.zip"

let package = Package(
    name: "dd-sdk-swift-testing",
    platforms: [.macOS(.v10_13),
                .iOS(.v11),
                .tvOS(.v11)],
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
