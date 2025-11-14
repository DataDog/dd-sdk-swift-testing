/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import CodeCoverageParser

public struct TestCodeCoverage: Encodable {
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
            var coveredLines = IndexSet()
            for location in info.segments.keys {
                coveredLines.insert(integersIn: Int(location.startLine)...Int(location.endLine))
            }
            self.init(name: info.name, workspace: workspace, lines: coveredLines)
        }
        
        init(name: String, workspace: String?, lines: IndexSet) {
            if let workspace = workspace, name.count >= workspace.count {
                self.name = name.replacingOccurrences(
                    of: workspace, with: "",
                    range: name.startIndex..<name.index(name.startIndex, offsetBy: workspace.count)
                )
            } else {
                self.name = name
            }
            guard let lastLine = lines.last else {
                self.bitmap = Data()
                return
            }
            var bitmap = Data(repeating: 0, count: lastLine % 8 == 0 ? lastLine / 8 : lastLine / 8 + 1)
            bitmap.withUnsafeMutableBytes { bytes in
                for line in lines {
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
    
    init(sessionId: UInt64, suiteId: UInt64, spanId: UInt64, workspace: String?, files: Dictionary<String, IndexSet>) {
        self.sessionId = sessionId
        self.suiteId = suiteId
        self.spanId = spanId
        let workspacePath = workspace.map { $0.last == "/" ? $0 : $0 + "/" }
        self.files = files.map { File(name: $0.key, workspace: workspacePath, lines: $0.value) }
    }
}
