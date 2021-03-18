/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

class DDNetworkActivityLogger {
    static var spanDict = [String: Span]()
    static var spanDictQueue = DispatchQueue(label: "com.datadoghq.ddnetworkactivityLogger")
    
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
    
    private static func redactHeaders(_ headers: [String: String]) -> [String: String] {
        return Dictionary(uniqueKeysWithValues: headers.map {
            if acceptableHeaders.contains($0.uppercased()) {
                return ($0, $1)
            } else {
                return ($0, "*********")
            }
        })
    }
    
    static func log(request: URLRequest, sessionTaskId: String) {
        guard let tracer = DDTestMonitor.instance?.tracer,
              tracer.activeSpan != nil || tracer.launchSpanContext != nil,
              !(DDTestMonitor.instance?.networkInstrumentation?.excludes(request.url) ?? false)
        else {
            return
        }
        
        var headersString = ""
        if let headers = request.allHTTPHeaderFields {
            headersString = DDNetworkActivityLogger.redactHeaders(headers)
                .map { $0.0 + "=" + $0.1 }
                .joined(separator: "\n")
        }
        
        var attributes: [String: String]
        
        attributes = [
            SemanticAttributes.httpMethod.rawValue: request.httpMethod ?? "unknown_method",
            SemanticAttributes.httpURL.rawValue: request.url?.absoluteString ?? "unknown_url",
            SemanticAttributes.httpScheme.rawValue: request.url?.scheme ?? "unknown_scheme",
            requestHeadersKey: headersString
        ]
        
        if let host = request.url?.host {
            attributes[SemanticAttributes.netPeerName.rawValue] = host
        }
        
        if let port = request.url?.port {
            attributes[SemanticAttributes.netPeerPort.rawValue] = String(port)
        }
        
        if DDTestMonitor.instance?.networkInstrumentation?.recordPayload ?? false {
            if let data = request.httpBody, data.count > 0 {
                let dataSample = data.subdata(in: 0..<min(data.count, 512))
                let payload = String(data: dataSample, encoding: .ascii) ?? "<unknown>"
                attributes[requestPayloadKey] = payload
            } else {
                attributes[requestPayloadKey] = "<empty>"
            }
        } else {
            attributes[requestPayloadKey] = "<disabled>"
        }
        
        let spanName = "HTTP " + (request.httpMethod ?? "")
        let span = tracer.startSpan(name: spanName, attributes: attributes)
        spanDictQueue.sync {
            spanDict[sessionTaskId] = span
        }
    }
    
    static func log(response: URLResponse, dataOrFile: Any?, sessionTaskId: String) {
        var span: Span!
        spanDictQueue.sync {
            span = spanDict.removeValue(forKey: sessionTaskId)
        }
        guard span != nil,
              let httpResponse = response as? HTTPURLResponse
        else {
            return
        }
        
        let statusCode = httpResponse.statusCode
        span.setAttribute(key: SemanticAttributes.httpStatusCode.rawValue, value: AttributeValue.string(String(statusCode)))
        
        if let headers = httpResponse.allHeaderFields as? [String: String] {
            let headersString = DDNetworkActivityLogger.redactHeaders(headers)
                .map { $0.0 + "=" + $0.1 }
                .joined(separator: "\n")
            span.setAttribute(key: responseHeadersKey, value: AttributeValue.string(headersString))
        }
        span.status = statusForStatusCode(code: statusCode)
        
        if DDTestMonitor.instance?.networkInstrumentation?.recordPayload ?? false {
            if let data = dataOrFile as? Data, data.count > 0 {
                let dataSample = data.subdata(in: 0..<min(data.count, DDTestMonitor.instance?.maxPayloadSize ?? DDTestMonitor.defaultPayloadSize))
                let payload = String(data: dataSample, encoding: .ascii) ?? "<unknown>"
                span.setAttribute(key: responsePayloadKey, value: payload)
            } else if let fileUrl = dataOrFile as? URL {
                span.setAttribute(key: responsePayloadKey, value: fileUrl.path)
            } else {
                span.setAttribute(key: responsePayloadKey, value: "<empty>")
            }
        } else {
            span.setAttribute(key: responsePayloadKey, value: "<disabled>")
        }
        
        span.end()
    }
    
    static func log(error: Error, dataOrFile: Any?, statusCode: Int, sessionTaskId: String) {
        var span: Span!
        spanDictQueue.sync {
            span = spanDict.removeValue(forKey: sessionTaskId)
        }
        guard span != nil else {
            return
        }
        span.setAttribute(key: SemanticAttributes.httpStatusCode.rawValue, value: AttributeValue.string(String(statusCode)))
        span.status = statusForStatusCode(code: statusCode)
        
        if DDTestMonitor.instance?.networkInstrumentation?.recordPayload ?? false {
            if let data = dataOrFile as? Data, data.count > 0 {
                let dataSample = data.subdata(in: 0..<min(data.count, 512))
                let payload = String(data: dataSample, encoding: .ascii) ?? "<unknown>"
                span.setAttribute(key: responsePayloadKey, value: payload)
            } else if let fileUrl = dataOrFile as? URL {
                span.setAttribute(key: responsePayloadKey, value: fileUrl.path)
            } else {
                span.setAttribute(key: responsePayloadKey, value: "<empty>")
            }
        } else {
            span.setAttribute(key: responsePayloadKey, value: "<disabled>")
        }
        
        span.end()
    }
    
    static func statusForStatusCode(code: Int) -> Status {
        switch code {
            case 200 ... 399:
                return .ok
            default:
                return .error(description: String(code))
        }
    }
    
    static func endAndCleanAliveSpans() {
        spanDictQueue.sync {
            spanDict.forEach {
                $0.value.setAttribute(key: unfinishedKey, value: "true")
                $0.value.end()
            }
            spanDict.removeAll()
        }
    }
}
