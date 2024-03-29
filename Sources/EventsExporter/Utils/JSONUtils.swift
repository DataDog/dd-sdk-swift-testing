/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

extension JSONEncoder {
    static func `default`() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatted = iso8601DateFormatter.string(from: date)
            try container.encode(formatted)
        }
        if #available(iOS 13.0, OSX 10.15, watchOS 6.0, tvOS 13.0, *) {
            encoder.outputFormatting = [.withoutEscapingSlashes]
        }
        return encoder
    }
}

protocol JSONable {
    var jsonData: Data? { get }
    var jsonString: String { get }
}

extension JSONable where Self: Encodable {
    var jsonData: Data? {
        return try? JSONEncoder().encode(self)
    }

    var jsonString: String {
        guard let data = self.jsonData else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
