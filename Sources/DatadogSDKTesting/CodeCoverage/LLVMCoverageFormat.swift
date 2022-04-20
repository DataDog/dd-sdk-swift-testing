import Foundation

struct LLVMCoverageFormat: Decodable {
    struct Datum: Codable {
        let files: [File]
    }

    struct File: Codable {
        let filename: String
        let segments: [Segment]
    }

    struct Segment: Codable {
        let line: Int
        let column: Int
        let count: Int
    }

    let data: [Datum]
}

extension LLVMCoverageFormat {
    init(data: Data) throws {
        let me = try JSONDecoder().decode(LLVMCoverageFormat.self, from: data)
        self = me
    }

    init?(_ json: String, using encoding: String.Encoding = .utf8) {
        guard let data = json.data(using: encoding) else { return nil }
        try? self.init(data: data)
    }

    init?(fromURL url: URL) {
        guard let data = try? Data(contentsOf: url, options: Data.ReadingOptions.mappedIfSafe) else { return nil }
        do {
            try self.init(data: data)
        } catch {
            Log.print("[process-coverage] Unexpected error in File: \n\(url.path)\nError: \(error)\n")
            return nil
        }
    }
}

extension LLVMCoverageFormat.Segment {
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        do {
            try self.line = container.decode(Int.self)
            try self.column = container.decode(Int.self)
            try self.count = container.decode(Int.self)
        } catch {
            throw DecodingError.typeMismatch(LLVMCoverageFormat.Segment.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Segment"))
        }
    }
}
