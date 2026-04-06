// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let releaseVersion = "2.6.7"
let relaseChecksum = "b55976bc8595b8cb0e2a3cbe1f99005b954b22359ffa39e7b803910fe8b42ca8"
let url = "https://github.com/DataDog/dd-sdk-swift-testing/releases/download/\(releaseVersion)/DatadogSDKTesting.zip"

let package = Package(
    name: "dd-sdk-swift-testing",
    platforms: [.macOS(.v11), .macCatalyst(.v13), .iOS(.v15), .tvOS(.v15)],
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
