import Foundation

struct LLVMCoverageFormat: Codable {
    struct Datum: Codable {
        let files: [File]
    }

    struct File: Codable {
        let filename: String
        let segments: [[Segment]]
    }

    enum Segment: Codable {
        case bool(Bool)
        case integer(Int)
    }

    let version: String
    let type: String
    let data: [Datum]
}

extension LLVMCoverageFormat {
    init?(data: Data) {
        do {
            let me = try JSONDecoder().decode(LLVMCoverageFormat.self, from: data)
            self = me
        } catch {
            print("[Scope] [process-coverage] Unexpected error: \(error).")
            return nil
        }
    }

    init?(_ json: String, using encoding: String.Encoding = .utf8) {
        guard let data = json.data(using: encoding) else { return nil }
        self.init(data: data)
    }

    init?(fromURL url: URL) {
        guard let data = try? Data(contentsOf: url, options: Data.ReadingOptions.mappedIfSafe) else { return nil }
        self.init(data: data)
    }

    var jsonData: Data? {
        return try? JSONEncoder().encode(self)
    }

    var json: String? {
        guard let data = self.jsonData else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension LLVMCoverageFormat.Segment {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Bool.self) {
            self = .bool(x)
            return
        }
        if let x = try? container.decode(Int.self) {
            self = .integer(x)
            return
        }
        throw DecodingError.typeMismatch(LLVMCoverageFormat.Segment.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Segment"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(x):
            try container.encode(x)
        case let .integer(x):
            try container.encode(x)
        }
    }

    var intValue: Int {
        switch self {
        case let .bool(num):
            return num ? 1 : 0
        case let .integer(num):
            return num
        }
    }
}
