// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "2.2.0"
let relaseChecksum = "22bf4f00ee824e365d9ed623d9472ba3c886b13f232276f3df53254d0e8818fe"
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
