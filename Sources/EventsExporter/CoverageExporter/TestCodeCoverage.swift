/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import CodeCoverage

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
        
        init(info: CoverageInfo.File, workspace: String?) {
            if let workspace = workspace, info.name.count >= workspace.count {
                self.name = info.name.replacingOccurrences(
                    of: workspace, with: "",
                    range: info.name.startIndex..<info.name.index(info.name.startIndex, offsetBy: workspace.count)
                )
            } else {
                self.name = info.name
            }
            let coveredLines = info.coveredLines
            guard let lastLine = coveredLines.last else {
                self.bitmap = Data()
                return
            }
            var bitmap = Data(repeating: 0, count: lastLine % 8 == 0 ? lastLine / 8 : lastLine / 8 + 1)
            bitmap.withUnsafeMutableBytes { bytes in
                for line in coveredLines {
                    let line0 = line - 1
                    let index = line0 / 8
                    let byte = bytes[index]
                    bytes[index] = byte | (1 << (7 - (line0 % 8)))
                }
            }
            self.bitmap = bitmap
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "test_session_id"
        case suiteId = "test_suite_id"
        case spanId = "span_id"
        case files
    }
    
    init(sessionId: UInt64, suiteId: UInt64, spanId: UInt64, workspace: String?, files: Dictionary<String, CoverageInfo.File>.Values) {
        self.sessionId = sessionId
        self.suiteId = suiteId
        self.spanId = spanId
        let workspacePath = workspace.map { $0.last == "/" ? $0 : $0 + "/" }
        self.files = files.map { File(info: $0, workspace: workspacePath) }
    }
}

extension CoverageInfo.File {
    var coveredLines: IndexSet {
        var indexes = IndexSet()
        for location in segments.keys {
            indexes.insert(integersIn: Int(location.startLine)...Int(location.endLine))
        }
        return indexes
    }
}
