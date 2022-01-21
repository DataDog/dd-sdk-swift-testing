/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

internal enum SimpleSpanSerializer {
    static func serializeSpan(simpleSpan: SimpleSpanData) -> Data {
        var encodedData = Data()
        do {
            encodedData = try JSONEncoder().encode(simpleSpan)
        } catch {
            Log.debug("Failed encoding span: \(simpleSpan.name)")
        }
        return encodedData
    }

    static func deserializeSpan(data: Data) -> SimpleSpanData? {
        var spanData: SimpleSpanData?
        do {
            spanData = try JSONDecoder().decode(SimpleSpanData.self, from: data)
        } catch {
            Log.debug("Failed decoding span: \(data)")
        }
        return spanData
    }
}
