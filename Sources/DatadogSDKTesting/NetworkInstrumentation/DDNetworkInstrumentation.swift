/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
@_implementationOnly import OpenTelemetryApi
@_implementationOnly import OpenTelemetrySdk
@_implementationOnly import URLSessionInstrumentation

class DDNetworkInstrumentation {
    var urlSessionInstrumentation: URLSessionInstrumentation!

    internal static let acceptableHeaders: Set<String> = {
        let headers: Set = ["CONTENT-TYPE", "CONTENT-LENGTH", "CONTENT-ENCODING", "CONTENT-LANGUAGE", "USER-AGENT", "REFERER", "ACCEPT", "ORIGIN", "ACCESS-CONTROL-ALLOW-ORIGIN", "ACCESS-CONTROL-ALLOW-CREDENTIALS", "ACCESS-CONTROL-ALLOW-HEADERS", "ACCESS-CONTROL-ALLOW-METHODS", "ACCESS-CONTROL-EXPOSE-HEADERS", "ACCESS-CONTROL-MAX-AGE", "ACCESS-CONTROL-REQUEST-HEADERS", "ACCESS-CONTROL-REQUEST-METHOD", "DATE", "EXPIRES", "CACHE-CONTROL", "ALLOW", "SERVER", "CONNECTION", "TRACEPARENT", "X-DATADOG-TRACE-ID", "X-DATADOG-PARENT-ID"]
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
              tracer.propagationContext != nil,
              !self.excludes(request.url)
        else {
            return false
        }

        return true
    }

    func shouldInjectTracingHeaders(request: URLRequest) -> Bool {
        guard injectHeaders == true,
              !excludes(request.url)
        else {
            return false
        }
        return true
    }

    func injectCustomHeaders( request: inout URLRequest, span: Span?) {
        guard injectHeaders == true,
              let tracer = DDTestMonitor.instance?.tracer
        else {
            return
        }
        if request.allHTTPHeaderFields?[DDHeaders.originField.rawValue] == nil {
            tracer.datadogHeaders(forContext: span?.context ?? tracer.propagationContext).forEach {
                request.addValue($0.value, forHTTPHeaderField: $0.key)
            }
        }
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

    func createdRequest(request: URLRequest, span: Span) {
        var headersString = ""
        if let headers = request.allHTTPHeaderFields {
            headersString = DDNetworkInstrumentation.redactHeaders(headers)
                .map { $0.0 + "=" + $0.1 }
                .joined(separator: "\n")
        }

        span.setAttribute(key: DDNetworkInstrumentation.requestHeadersKey, value: headersString)

        storePayloadInSpan(dataOrFile: request.httpBody, span: span, attributeKey: DDNetworkInstrumentation.requestPayloadKey)
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

        storePayloadInSpan(dataOrFile: dataOrFile, span: span, attributeKey: DDNetworkInstrumentation.responsePayloadKey)
    }

    func receivedError(error: Error, dataOrFile: DataOrFile?, status: HTTPStatus, span: Span) {
        storePayloadInSpan(dataOrFile: dataOrFile, span: span, attributeKey: DDNetworkInstrumentation.responsePayloadKey)
    }

    private func storePayloadInSpan(dataOrFile: DataOrFile?, span: Span, attributeKey: String) {
        if DDTestMonitor.instance?.networkInstrumentation?.recordPayload ?? false {
            if let data = dataOrFile as? Data, data.count > 0 {
                let dataSample = data.subdata(in: 0 ..< min(data.count, 512))
                let payload = String(data: dataSample, encoding: .ascii) ?? "<unknown>"
                span.setAttribute(key: attributeKey, value: payload)
            } else if let fileUrl = dataOrFile as? URL {
                span.setAttribute(key: attributeKey, value: fileUrl.path)
            } else {
                span.setAttribute(key: attributeKey, value: "<empty>")
            }
        } else {
            span.setAttribute(key: attributeKey, value: "<disabled>")
        }
    }

    func endAndCleanAliveSpans() {
        urlSessionInstrumentation.startedRequestSpans.forEach {
            $0.end()
        }
    }

    init() {
        excludedURLs = DDTestMonitor.instance?.tracer.endpointURLs() ?? []

        let configuration = URLSessionInstrumentationConfiguration(shouldRecordPayload: shouldRecordPayload,
                                                                   shouldInstrument: shouldInstrumentRequest,
                                                                   shouldInjectTracingHeaders: shouldInjectTracingHeaders,
                                                                   injectCustomHeaders: injectCustomHeaders,
                                                                   createdRequest: createdRequest,
                                                                   receivedResponse: receivedResponse,
                                                                   receivedError: receivedError)

        urlSessionInstrumentation = URLSessionInstrumentation(configuration: configuration)
    }
}
