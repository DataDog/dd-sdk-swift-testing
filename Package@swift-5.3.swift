// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "2.2.6-beta.1"
let relaseChecksum = "5ae1a7a5270686f8178ee22ae1a515b014d732850aaa96b639ec6acfb500e3ef"
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
