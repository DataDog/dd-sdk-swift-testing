/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

struct DDCoverageFormat: Encodable {
    var version: String = "1"
    var trace_id: String
    var span_id: String
    var files = [File]()

    struct File: Encodable {
        let filename: String
        let segments: [Segment]
    }

    struct Segment: Codable {
        var startLine = 0
        var startColumn = 0
        var endLine = 0
        var endColumn = 0
        var count = 0

        func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(startLine)
            try container.encode(startColumn)
            try container.encode(endLine)
            try container.encode(endColumn)
            try container.encode(count)
        }

        init() {}
    }

    init?(llvmFormat: LLVMCoverageFormat, traceId: String, spanId: String, workspacePath: String?) {
        guard let llvmFiles = llvmFormat.data.first?.files else { return nil }

        self.trace_id = traceId
        self.span_id = spanId

        for llvmFile in llvmFiles {
            var segments = [Segment]()
            var currentSegment = Segment()
            var previousCount = 0
            for segment in llvmFile.segments {
                let line = segment.line
                let column = segment.column
                let count = segment.count
                if previousCount == 0 {
                    if count == 0 {
                        continue
                    } else {
                        // start Boundary
                        currentSegment.startLine = line
                        currentSegment.startColumn = column
                        currentSegment.count = count
                        previousCount = count
                    }
                } else {
                    if count == 0 {
                        // end Segment
                        currentSegment.endLine = line
                        currentSegment.endColumn = column
                        segments.append(currentSegment)
                        currentSegment = Segment()
                        previousCount = 0
                    } else if count == previousCount {
                        // continue boundary
                    } else {
                        // change Segment
                        if column > 0 {
                            currentSegment.endLine = line
                            currentSegment.endColumn = column - 1
                        } else {
                            currentSegment.endLine = line - 1
                            currentSegment.endColumn = column
                        }
                        segments.append(currentSegment)
                        currentSegment = Segment()
                        currentSegment.startLine = line
                        currentSegment.startColumn = column
                        currentSegment.count = count
                        previousCount = count
                    }
                }
            }
            if segments.count > 0 {
                var filename = llvmFile.filename
                if let workspacePath = workspacePath {
                    filename = filename.replacingOccurrences(of: workspacePath + "/", with: "")
                }
                let file = File(filename: filename, segments: segments)
                files.append(file)
            }
        }
    }
}

extension DDCoverageFormat {
    var jsonData: Data? {
        return try? JSONEncoder().encode(self)
    }

    var json: String? {
        guard let data = self.jsonData else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
