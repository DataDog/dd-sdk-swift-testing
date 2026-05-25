/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Wire-shape payload for `/api/v2/citestcov`. Built from the
/// `CoverageData` handed to the exporter by a `CoverageProcessor`.
struct TestCodeCoverage: Encodable {
    let sessionId: UInt64
    let suiteId: UInt64
    let spanId: UInt64
    let files: [File]

    struct File: Encodable {
        let name: String
        let bitmap: Data

        enum CodingKeys: String, CodingKey {
            case name = "filename"
            case bitmap
        }
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "test_session_id"
        case suiteId = "test_suite_id"
        case spanId = "span_id"
        case files
    }

    init(sessionId: UInt64, suiteId: UInt64, spanId: UInt64,
         workspace: String?, files: [CoverageFile])
    {
        self.sessionId = sessionId
        self.suiteId = suiteId
        self.spanId = spanId
        // The SDK side hands us absolute paths; strip the workspace root
        // when present so the backend stores repo-relative names.
        let prefix = workspace.map { $0.last == "/" ? $0 : $0 + "/" }
        self.files = files.map { input in
            let name: String
            if let prefix, input.name.hasPrefix(prefix) {
                name = String(input.name.dropFirst(prefix.count))
            } else {
                name = input.name
            }
            return File(name: name, bitmap: input.bitmap)
        }
    }
}
