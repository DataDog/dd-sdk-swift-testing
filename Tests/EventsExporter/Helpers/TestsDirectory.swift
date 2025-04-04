/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

@testable import EventsExporter
import Foundation
import XCTest

/// Creates `Directory` pointing to unique subfolder in `/var/folders/`.
/// Does not create the subfolder - it must be later created with `.create()`.
func obtainUniqueTemporaryDirectory() -> Directory {
    let subdirectoryName = "com.datadoghq.ios-sdk-tests-\(UUID().uuidString)"
    let osTemporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(subdirectoryName, isDirectory: true)
    print("💡 Obtained temporary directory URL: \(osTemporaryDirectoryURL)")
    return Directory(url: osTemporaryDirectoryURL)
}

/// `Directory` pointing to subfolder in `/var/folders/`.
/// The subfolder does not exist and can be created and deleted by calling `.create()` and `.delete()`.
let temporaryDirectory = obtainUniqueTemporaryDirectory()

/// Extends `Directory` with set of utilities for convenient work with files in tests.
/// Provides handy methods to create / delete files and directires.
extension Directory {
    /// Creates empty directory with given attributes .
    func testCreate(attributes: [FileAttributeKey: Any]? = nil, file: StaticString = #file, line: UInt = #line) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
            let initialFilesCount = try files().count
            XCTAssert(initialFilesCount == 0, "🔥 `TestsDirectory` is not empty: \(String(describing: url))", file: file, line: line)
        } catch {
            XCTFail("🔥 Failed to create `TestsDirectory`: \(error)", file: file, line: line)
        }
    }

    /// Deletes entire directory with its content.
    func testDelete(file: StaticString = #file, line: UInt = #line) {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                XCTFail("🔥 Failed to delete `TestsDirectory`: \(error)", file: file, line: line)
            }
        }
    }
}
