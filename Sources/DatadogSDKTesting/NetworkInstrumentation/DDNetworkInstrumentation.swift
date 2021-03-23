/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import URLSessionInstrumentation

class DDNetworkInstrumentation {
    var networkInstrumentation: URLSessionInstrumentation!

    internal static let acceptableHeaders: Set<String> = {
        let headers: Set = ["CONTENT-TYPE", "CONTENT-LENGTH", "CONTENT-ENCODING", "CONTENT-LANGUAGE", "USER-AGENT", "REFERER", "ACCEPT", "ORIGIN", "ACCESS-CONTROL-ALLOW-ORIGIN", "ACCESS-CONTROL-ALLOW-CREDENTIALS", "ACCESS-CONTROL-ALLOW-HEADERS", "ACCESS-CONTROL-ALLOW-METHODS", "ACCESS-CONTROL-EXPOSE-HEADERS", "ACCESS-CONTROL-MAX-AGE", "ACCESS-CONTROL-REQUEST-HEADERS", "ACCESS-CONTROL-REQUEST-METHOD", "DATE", "EXPIRES", "CACHE-CONTROL", "ALLOW", "SERVER", "CONNECTION"]
        if let extraHeaders = DDTestMonitor.instance?.tracer.env.extraHTTPHeaders {
            return headers.union(extraHeaders)
        }
        return headers
    }()

    static let requestHeadersKey = "http.request.headers"
    static let responseHeadersKey = "http.response.headers"
    static let requestPayloadKey = "http.request.payload"
    static let responsePayloadKey = "http.response.payload"
    static let unfinishedKey = "http.unfinished"

    var recordPayload: Bool {
        return DDTestMonitor.instance?.recordPayload ?? false
    }

    private var injectHeaders: Bool {
        return DDTestMonitor.instance?.injectHeaders ?? false
    }

    var excludedURLs = Set<String>()

    func shouldRecordPayload(session: URLSession) -> Bool {
        return self.recordPayload
    }

    private func excludes(_ url: URL?) -> Bool {
        if let absoluteString = url?.absoluteString {
            return excludedURLs.contains {
                absoluteString.starts(with: $0)
            }
        }
        return false
    }

    func shouldInstrumentRequest(request: URLRequest) -> Bool {
        guard let tracer = DDTestMonitor.instance?.tracer,
              tracer.activeSpan != nil || tracer.launchSpanContext != nil,
              !self.excludes(request.url)
        else {
            return false
        }
        
        return true
    }

    func shouldInjectTracingHeaders( request: inout URLRequest) -> Bool {
        guard injectHeaders == true,
              let tracer = DDTestMonitor.instance?.tracer,
              tracer.activeSpan != nil,
              !excludes(request.url)
        else {
            return false
        }
        tracer.datadogHeaders().forEach {
            request.addValue($0.value, forHTTPHeaderField: $0.key)
        }

        return true
    }

    private static func redactHeaders(_ headers: [String: String]) -> [String: String] {
        return Dictionary(uniqueKeysWithValues: headers.map {
            if acceptableHeaders.contains($0.uppercased()) {
                return ($0, $1)
            } else {
                return ($0, "*********")
            }
        })
    }

    func createdRequest(request: URLRequest, builder: SpanBuilder) {
        var headersString = ""
        if let headers = request.allHTTPHeaderFields {
            headersString = DDNetworkInstrumentation.redactHeaders(headers)
                .map { $0.0 + "=" + $0.1 }
                .joined(separator: "\n")
        }

        builder.setAttribute(key: DDNetworkInstrumentation.requestHeadersKey, value: headersString)

        if DDTestMonitor.instance?.networkInstrumentation?.recordPayload ?? false {
            if let data = request.httpBody, data.count > 0 {
                let dataSample = data.subdata(in: 0 ..< min(data.count, 512))
                let payload = String(data: dataSample, encoding: .ascii) ?? "<unknown>"
                builder.setAttribute(key: DDNetworkInstrumentation.requestPayloadKey, value: payload)
            } else {
                builder.setAttribute(key: DDNetworkInstrumentation.requestPayloadKey, value: "<empty>")
            }
        } else {
            builder.setAttribute(key: DDNetworkInstrumentation.requestPayloadKey, value: "<disabled>")
        }
    }

    func receivedResponse(response: URLResponse, dataOrFile: DataOrFile?, span: Span) {
        if let response = response as? HTTPURLResponse,
           let headers = response.allHeaderFields as? [String: String]
        {
            let headersString = DDNetworkInstrumentation.redactHeaders(headers)
                .map { $0.0 + "=" + $0.1 }
                .joined(separator: "\n")
            span.setAttribute(key: DDNetworkInstrumentation.responseHeadersKey, value: AttributeValue.string(headersString))
        }

        if DDTestMonitor.instance?.networkInstrumentation?.recordPayload ?? false {
            if let data = dataOrFile as? Data, data.count > 0 {
                let dataSample = data.subdata(in: 0 ..< min(data.count, DDTestMonitor.instance?.maxPayloadSize ?? DDTestMonitor.defaultPayloadSize))
                let payload = String(data: dataSample, encoding: .ascii) ?? "<unknown>"
                span.setAttribute(key: DDNetworkInstrumentation.responsePayloadKey, value: payload)
            } else if let fileUrl = dataOrFile as? URL {
                span.setAttribute(key: DDNetworkInstrumentation.responsePayloadKey, value: fileUrl.path)
            } else {
                span.setAttribute(key: DDNetworkInstrumentation.responsePayloadKey, value: "<empty>")
            }
        } else {
            span.setAttribute(key: DDNetworkInstrumentation.responsePayloadKey, value: "<disabled>")
        }
    }

    func receivedError(error: Error, dataOrFile: DataOrFile?, status: HTTPStatus, span: Span) {
        if DDTestMonitor.instance?.networkInstrumentation?.recordPayload ?? false {
            if let data = dataOrFile as? Data, data.count > 0 {
                let dataSample = data.subdata(in: 0..<min(data.count, 512))
                let payload = String(data: dataSample, encoding: .ascii) ?? "<unknown>"
                span.setAttribute(key: DDNetworkInstrumentation.responsePayloadKey, value: payload)
            } else if let fileUrl = dataOrFile as? URL {
                span.setAttribute(key: DDNetworkInstrumentation.responsePayloadKey, value: fileUrl.path)
            } else {
                span.setAttribute(key: DDNetworkInstrumentation.responsePayloadKey, value: "<empty>")
            }
        } else {
            span.setAttribute(key: DDNetworkInstrumentation.responsePayloadKey, value: "<disabled>")
        }
    }

//
//    static func endAndCleanAliveSpans() {
//        spanDictQueue.sync {
//            spanDict.forEach {
//                $0.value.setAttribute(key: unfinishedKey, value: "true")
//                $0.value.end()
//            }
//            spanDict.removeAll()
//        }
//    }

    init() {
        excludedURLs = ["https://mobile-http-intake.logs",
                        "https://public-trace-http-intake.logs.",
                        "https://rum-http-intake.logs."]

        let configuration = URLSessionConfiguration(shouldRecordPayload: shouldRecordPayload,
                                                    shouldInstrument: shouldInstrumentRequest,
                                                    shouldInjectTracingHeaders: shouldInjectTracingHeaders,
                                                    createdRequest: createdRequest,
                                                    receivedResponse: receivedResponse,
                                                    receivedError: receivedError)

        networkInstrumentation = URLSessionInstrumentation(configuration: configuration)
    }
}
