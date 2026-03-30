/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import OpenTelemetrySdk

/// This structs the minimum data we need from a Span to be serialized together with the crash if it happens,
/// so it can be reconstructed when processing the crash report
internal struct SimpleSpanData: Codable, Equatable {
    var traceIdHi: UInt64
    var traceIdLo: UInt64
    var spanId: UInt64
    var name: String
    var startTime: Date
    var stringAttributes = [String: String]()
    var sessionStartTime: Date
    var moduleStartTime: Date
    var suiteStartTime: Date?

    init(spanData: SpanData, sessionStartTime: Date, moduleStartTime: Date, suiteStartTime: Date? = nil) {
        self.traceIdHi = spanData.traceId.rawHigherLong
        self.traceIdLo = spanData.traceId.rawLowerLong
        self.spanId = spanData.spanId.rawValue
        self.name = spanData.name
        self.startTime = spanData.startTime
        self.stringAttributes = spanData.attributes.mapValues { $0.description }
        self.moduleStartTime = moduleStartTime
        self.suiteStartTime = suiteStartTime
        self.sessionStartTime = sessionStartTime
    }

    internal init(traceIdHi: UInt64, traceIdLo: UInt64, spanId: UInt64, name: String, startTime: Date, stringAttributes: [String: String] = [String: String](), sessionStartTime: Date, moduleStartTime: Date, suiteStartTime: Date? = nil) {
        self.traceIdHi = traceIdHi
        self.traceIdLo = traceIdLo
        self.spanId = spanId
        self.name = name
        self.startTime = startTime
        self.stringAttributes = stringAttributes
        self.sessionStartTime = sessionStartTime
        self.moduleStartTime = moduleStartTime
        self.suiteStartTime = suiteStartTime
    }
}


extension TestModule {
    var toCrashData: SimpleSpanData {
        var attributes = tags
        for metric in metrics {
            attributes[metric.key] = String(metric.value)
        }
        return .init(traceIdHi: 0,
                     traceIdLo: 0,
                     spanId: id.rawValue,
                     name: name,
                     startTime: startTime,
                     stringAttributes: attributes,
                     sessionStartTime: session.startTime,
                     moduleStartTime: startTime)
    }
}


extension TestSuite {
    var toCrashData: SimpleSpanData {
        var attributes = tags
        for metric in metrics {
            attributes[metric.key] = String(metric.value)
        }
        return .init(traceIdHi: 0,
                     traceIdLo: 0,
                     spanId: id.rawValue,
                     name: name,
                     startTime: startTime,
                     stringAttributes: attributes,
                     sessionStartTime: session.startTime,
                     moduleStartTime: module.startTime,
                     suiteStartTime: startTime)
    }
}

extension Test {
    var toCrashData: SimpleSpanData {
        .init(spanData: span.toSpanData(),
              sessionStartTime: session.startTime,
              moduleStartTime: module.startTime,
              suiteStartTime: suite.startTime)
    }
}
