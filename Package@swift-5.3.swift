// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "2.2.5"
let relaseChecksum = "79ab9b02fd0c825557a97db9c1550aea4496fef83124a3fcf475444c3f86dbf5"
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
