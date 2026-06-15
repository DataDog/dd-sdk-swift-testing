/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import OpenTelemetryApi

class DDNetworkInstrumentation {
    var urlSessionInstrumentation: URLSessionInstrumentation!

    internal static let acceptableHeaders: Set<String> = {
        let headers: Set = ["CONTENT-TYPE", "CONTENT-LENGTH", "CONTENT-ENCODING", "CONTENT-LANGUAGE", "USER-AGENT", "REFERER", "ACCEPT", "ORIGIN", "ACCESS-CONTROL-ALLOW-ORIGIN", "ACCESS-CONTROL-ALLOW-CREDENTIALS", "ACCESS-CONTROL-ALLOW-HEADERS", "ACCESS-CONTROL-ALLOW-METHODS", "ACCESS-CONTROL-EXPOSE-HEADERS", "ACCESS-CONTROL-MAX-AGE", "ACCESS-CONTROL-REQUEST-HEADERS", "ACCESS-CONTROL-REQUEST-METHOD", "DATE", "EXPIRES", "CACHE-CONTROL", "ALLOW", "SERVER", "CONNECTION", "TRACEPARENT", "X-DATADOG-TRACE-ID", "X-DATADOG-PARENT-ID"]
        if let extraHeaders = DDTestMonitor.config.extraHTTPHeaders {
            return headers.union(extraHeaders)
        }
        return headers
    }()

    static let requestHeadersKey = "http.request.headers"
    static let responseHeadersKey = "http.response.headers"
    static let requestPayloadKey = "http.request.payload"
    static let responsePayloadKey = "http.response.payload"
    static let unfinishedKey = "http.unfinished"

    /// The tracer that owns network spans/propagation. Injected at init so this
    /// instrumentation is self-contained and never reaches into `DDTestMonitor`
    /// at request time.
    private let tracer: DDTracer
    /// Inject Datadog / `traceparent` headers into instrumented requests.
    /// Mutable: `DDInstrumentationControl` toggles it at runtime.
    var injectHeaders: Bool
    /// Capture request/response payloads onto spans. Mutable for the same reason.
    var recordPayload: Bool
    /// Skip attaching the call stack to network spans.
    private let disableNetworkCallStack: Bool
    /// Symbolicate the captured call stack (when it is captured at all).
    private let enableNetworkCallStackSymbolicated: Bool

    var excludedURLs = Set<String>()

    func shouldRecordPayload(session: URLSession) -> Bool {
        return recordPayload
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
        return tracer.propagationContext != nil && includes(request.url)
    }

    func shouldInjectTracingHeaders(request: URLRequest) -> Bool {
        return injectHeaders && includes(request.url)
    }

    private func includes(_ url: URL?) -> Bool {
        return !excludes(url)
    }

    func injectCustomHeaders(request: inout URLRequest, span: Span?) {
        guard injectHeaders else {
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
        storeContextInSpan(span: span)
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
        if recordPayload {
            if let data = dataOrFile as? Data, !data.isEmpty {
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

    private func storeContextInSpan(span: Span) {
        guard disableNetworkCallStack == false else {
            return
        }
        let callsStack: [String]
        if enableNetworkCallStackSymbolicated {
            callsStack = DDSymbolicator.getCallStackSymbolicated()
        } else {
            callsStack = DDSymbolicator.getCallStack()
        }

        let completeStack = callsStack.joined(separator: "\n")

        if completeStack.count < 5000 {
            span.setAttribute(key: DDTags.contextCallStack, value: completeStack)
        } else {
            let splitted = completeStack.split(by: 5000)
            for i in 0 ..< splitted.count {
                let character = Character(UnicodeScalar("a".unicodeScalars.first!.value + UInt32(i))!)
                span.setAttribute(key: "\(DDTags.contextCallStack).\(character)", value: AttributeValue.string(splitted[i]))
            }
        }

        if let number = Thread.current.value(forKeyPath: "private.seqNum") as? Int {
            span.setAttribute(key: DDTags.contextThreadNumber, value: number)
        }

        if let name = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8) {
            span.setAttribute(key: DDTags.contextQueueName, value: name)
        }

        withUnsafeCurrentTask { task in
            if let hash = task?.hashValue {
                span.setAttribute(key: DDTags.contextTaskHashValue, value: hash)
            }
        }
        
    }

    func endAndCleanAliveSpans() {
        urlSessionInstrumentation.startedRequestSpans.forEach {
            $0.end()
        }
    }

    init(tracer: DDTracer,
         injectHeaders: Bool = false,
         recordPayload: Bool = false,
         disableNetworkCallStack: Bool = false,
         enableNetworkCallStackSymbolicated: Bool = false)
    {
        self.tracer = tracer
        self.injectHeaders = injectHeaders
        self.recordPayload = recordPayload
        self.disableNetworkCallStack = disableNetworkCallStack
        self.enableNetworkCallStackSymbolicated = enableNetworkCallStackSymbolicated
        excludedURLs = tracer.endpointURLs()

        // Capture `self` weakly in the configuration callbacks. The configuration
        // is retained by `urlSessionInstrumentation`, which this object owns, so
        // passing the instance methods directly (a strong `self` capture) would
        // form a retain cycle that leaks the instrumentation and its tracer.
        let configuration = URLSessionInstrumentationConfiguration(
            shouldRecordPayload: { [weak self] session in self?.shouldRecordPayload(session: session) },
            shouldInstrument: { [weak self] request in self?.shouldInstrumentRequest(request: request) },
            shouldInjectTracingHeaders: { [weak self] request in self?.shouldInjectTracingHeaders(request: request) },
            injectCustomHeaders: { [weak self] request, span in self?.injectCustomHeaders(request: &request, span: span) },
            createdRequest: { [weak self] request, span in self?.createdRequest(request: request, span: span) },
            receivedResponse: { [weak self] response, dataOrFile, span in
                self?.receivedResponse(response: response, dataOrFile: dataOrFile, span: span)
            },
            receivedError: { [weak self] error, dataOrFile, status, span in
                self?.receivedError(error: error, dataOrFile: dataOrFile, status: status, span: span)
            })

        urlSessionInstrumentation = URLSessionInstrumentation(configuration: configuration)
    }
}
