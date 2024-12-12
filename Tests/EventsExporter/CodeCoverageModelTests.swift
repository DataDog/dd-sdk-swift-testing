//
//  CodeCoverageModelTests.swift
//  EventsExporterTests
//
//  Created by Yehor Popovych on 12/12/2024.
//

import XCTest
import CodeCoverage
@testable import EventsExporter

final class CodeCoverageModelTests: XCTestCase {
    func testBitmapGeneration() throws {
        let testJson = #"""
        { "files": {
            "Sources/OpenTelemetrySdk/Trace/SpanBuilderSdk.swift": {
                "segments": [
                    {"endColumn":16,"startColumn":32,"endLine":117,"startLine":108},
                    {"location":{"startLine":108,"startColumn":32,"endLine":117,"endColumn":16},"count":1},
                    {"startColumn":5,"endColumn":6,"startLine":42,"endLine":48},
                    {"location":{"endLine":48,"startLine":42,"endColumn":6,"startColumn":5},"count":1},
                    {"endLine":31,"endColumn":49,"startColumn":48,"startLine":31},
                    {"location":{"endColumn":49,"startColumn":48,"startLine":31,"endLine":31},"count":1},
                    {"endColumn":40,"endLine":134,"startLine":120,"startColumn":10},
                    {"count":1,"location":{"startColumn":10,"endLine":134,"startLine":120,"endColumn":40}},
                    {"endColumn":42,"endLine":30,"startColumn":25,"startLine":30},
                    {"location":{"startColumn":25,"endColumn":42,"endLine":30,"startLine":30},"count":1},
                    {"endColumn":6,"endLine":154,"startLine":136,"startColumn":10},
                    {"location":{"startColumn":10,"endLine":154,"startLine":136,"endColumn":6},"count":1},
                    {"startColumn":30,"endLine":159,"endColumn":26,"startLine":156},
                    {"count":1,"location":{"endLine":159,"endColumn":26,"startLine":156,"startColumn":30}},
                    {"endLine":32,"startLine":32,"endColumn":54,"startColumn":42},
                    {"count":1,"location":{"startColumn":42,"endColumn":54,"startLine":32,"endLine":32}},
                    {"startLine":28,"startColumn":28,"endLine":28,"endColumn":45},
                    {"location":{"startLine":28,"endLine":28,"endColumn":45,"startColumn":28},"count":1},
                    {"endLine":163,"startColumn":10,"startLine":161,"endColumn":6},
                    {"count":1,"location":{"endColumn":6,"endLine":163,"startColumn":10,"startLine":161}},
                    {"startColumn":41,"startLine":210,"endLine":214,"endColumn":6},
                    {"count":1,"location":{"startLine":210,"endLine":214,"endColumn":6,"startColumn":41}},
                    {"startLine":208,"endLine":209,"endColumn":9,"startColumn":52},
                    {"count":1,"location":{"endLine":209,"endColumn":9,"startLine":208,"startColumn":52}},
                    {"startColumn":72,"endColumn":10,"endLine":193,"startLine":190},
                    {"location":{"startLine":190,"endColumn":10,"startColumn":72,"endLine":193},"count":1},
                    {"startLine":204,"startColumn":32,"endColumn":9,"endLine":207},
                    {"count":1,"location":{"endLine":207,"startColumn":32,"endColumn":9,"startLine":204}},
                    {"endLine":203,"endColumn":9,"startLine":198,"startColumn":126},
                    {"location":{"startLine":198,"endLine":203,"startColumn":126,"endColumn":9},"count":1},
                    {"startLine":216,"startColumn":95,"endLine":220,"endColumn":9},
                    {"count":1,"location":{"endColumn":9,"startLine":216,"startColumn":95,"endLine":220}},
                    {"endColumn":44,"startLine":34,"startColumn":39,"endLine":34},
                    {"location":{"startColumn":39,"endLine":34,"startLine":34,"endColumn":44},"count":1},
                    {"endLine":222,"endColumn":9,"startLine":221,"startColumn":34},
                    {"count":1,"location":{"startColumn":34,"startLine":221,"endLine":222,"endColumn":9}},
                    {"endLine":225,"startLine":223,"startColumn":23,"endColumn":6},
                    {"location":{"endLine":225,"endColumn":6,"startColumn":23,"startLine":223},"count":1}
                ],
                "name":"Sources/OpenTelemetrySdk/Trace/SpanBuilderSdk.swift"
            } }
        }
        """#
        
        let info = try JSONDecoder().decode(CoverageInfo.self, from: testJson.utf8Data)
        let lines = info.files.values.first!.coveredLines
        let converted = TestCodeCoverage(sessionId: 0, suiteId: 0, spanId: 0, workspace: nil, files: info.files.values)
        
        let bitmapLines = converted.files.first!.bitmap.enumerated().reduce(into: IndexSet()) { (indexes, current) in
            let (index, byte) = current
            for bit in 1...8 {
                if (byte >> (8 - bit)) & 1 != 0 {
                    let line = index * 8 + bit
                    indexes.insert(line)
                }
            }
        }
        
        XCTAssertEqual(lines, bitmapLines)
    }
}
