/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

enum JSONGeneric {
    case string(String)
    indirect case stringDict([String: String])
}

extension JSONGeneric: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .string(let value):
                try container.encode(value)
            case .stringDict(let value):
                try container.encode(value)
        }
    }
}

extension JSONGeneric: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        if let value = try? container.decode([String: String].self) {
            self = .stringDict(value)
            return
        }

        throw DecodingError.dataCorrupted(
            .init(
                codingPath: container.codingPath,
                debugDescription: "Cannot decode JSON"
            )
        )
    }
}
