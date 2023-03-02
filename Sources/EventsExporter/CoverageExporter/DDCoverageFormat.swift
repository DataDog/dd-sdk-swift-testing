/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct DDCoverageFormat: Encodable {
    var version: Int = 2
    var coverages = [Coverage]()

    struct Coverage: Encodable {
        var test_session_id: UInt64
        var test_suite_id: UInt64
        var span_id: UInt64
        var files = [File]()

        struct File: Encodable {
            let filename: String
            let segments: [Segment]
        }

        struct Segment: Encodable {
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
        
        init?(llvmFormat: LLVMSimpleCoverageFormat, testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64, workspacePath: String?) {
            guard let llvmFiles = llvmFormat.data.first?.files else { return nil }

            self.test_session_id = testSessionId
            self.test_suite_id = testSuiteId
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
    
    mutating func addCoverage(llvmFormat: LLVMSimpleCoverageFormat, testSessionId: UInt64, testSuiteId: UInt64, spanId: UInt64, workspacePath: String?) {
        guard let coverage = Coverage(llvmFormat: llvmFormat, testSessionId: testSessionId, testSuiteId: testSuiteId, spanId: spanId, workspacePath: workspacePath) else {
            return
        }
        coverages.append(coverage)
    }

    
}
