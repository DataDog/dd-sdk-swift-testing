/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

struct LLVMTotalsCoverageFormat: Codable {
    struct Datum: Codable {
        let totals: Totals
    }

    struct Statistics: Codable {
        var count: Int
        var covered: Int
        var percent: Double
    }

    struct Totals: Codable {
        let branches: Statistics
        let functions: Statistics
        let instantiations: Statistics
        let lines: Statistics
        let regions: Statistics
    }

    let data: [Datum]
}

extension LLVMTotalsCoverageFormat {
    init?(data: Data) throws {
        let me = try JSONDecoder().decode(LLVMTotalsCoverageFormat.self, from: data)
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
            Log.print("Error reading module coverage format: \n\(url.path)\nError: \(error)")
            return nil
        }
    }
}
