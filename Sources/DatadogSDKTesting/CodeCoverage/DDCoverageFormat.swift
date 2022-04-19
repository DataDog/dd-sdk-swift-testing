import Foundation

struct DDCoverageFormat: Encodable {
    var type: String = "coverage"
    var version: String = "1"
    var content: CoverageContent

    struct CoverageContent: Encodable {
        var testId: String
        var files = [File]()
    }

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

    init?(llvmFormat: LLVMCoverageFormat, testId: String) {
        guard let llvmFiles = llvmFormat.data.first?.files else { return nil }

        content = CoverageContent(testId: testId)

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
                let filename = llvmFile.filename
                let file = File(filename: filename, segments: segments)
                content.files.append(file)
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
