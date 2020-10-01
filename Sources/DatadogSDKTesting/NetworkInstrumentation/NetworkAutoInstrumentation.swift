/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import OpenTelemetryApi

internal class NetworkAutoInstrumentation {
    static var instance: NetworkAutoInstrumentation?

    let swizzler: URLSessionSwizzler
    let urlFilter: URLFiltering
    var interceptor: RequestInterceptor {
        TracingRequestInterceptor.build(with: urlFilter)
    }

    init?(urlFilter: URLFiltering) {
        do {
            self.swizzler = try URLSessionSwizzler()
            self.urlFilter = urlFilter
            self.apply()
        } catch {
            print("🔥 Network requests won't be traced automatically: \(error)")
            return nil
        }
    }

    func apply() {
        swizzler.swizzle(using: interceptor)
    }
}

private enum TracingRequestInterceptor {
    static func build(with filter: URLFiltering) -> RequestInterceptor {
        let interceptor: RequestInterceptor = { urlRequest in
            guard let tracer = DDTestMonitor.instance?.tracer,
                filter.allows(urlRequest.url),
                tracer.canInjectHeaders(to: urlRequest) else {
                    return nil
            }
            let tracingHeaders = tracer.tracePropagationHTTPHeaders()
            var modifiedRequest = urlRequest
            tracingHeaders.forEach { modifiedRequest.setValue($1, forHTTPHeaderField: $0) }

            let observer: TaskObserver = tracingTaskObserver(tracer: tracer)
            return InterceptionResult(modifiedRequest: modifiedRequest, taskObserver: observer)
        }
        return interceptor
    }

    private static func tracingTaskObserver(
        tracer: DDTracer
    ) -> TaskObserver {
        var startedSpan: Span? = nil
        let observer: TaskObserver = { observedEvent in
            switch observedEvent {
            case .starting(var request):
                if let ongoingSpan = startedSpan {
                    print("\(String(describing: request)) is starting a new trace but it's already started a trace before: \(ongoingSpan)")
                }
                let tracingHeaders = tracer.tracePropagationHTTPHeaders()
                tracingHeaders.forEach { request?.setValue($1, forHTTPHeaderField: $0) }

                let url = request?.url?.absoluteString ?? "unknown_url"
                let method = request?.httpMethod ?? "unknown_method"

                let attributes: [String: String] = [
                    DDTags.resource: url,
                    DDTags.httpUrl: url,
                    DDTags.httpMethod: method,
                ]

                let span = tracer.startSpan( name: "urlsession.request", attributes: attributes )
                startedSpan = span
            case .completed(let response, let error):
                guard let completedSpan = startedSpan else {
                    break
                }
                if let error = error {
                    completedSpan.setError(error)
                }
                if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                    completedSpan.setAttribute(key: DDTags.httpStatusCode, value: statusCode)
                    if (400..<500).contains(statusCode) {
                        completedSpan.setAttribute(key: DDTags.error, value: true)
                    }
                    if statusCode == 404 {
                        completedSpan.setAttribute(key: DDTags.resource, value: "404")
                    }
                }
                completedSpan.end()
            }
        }
        return observer
    }
}

private extension Span {
    func setError(_ error: Error) {
        setAttribute(key: DDTags.error, value: true)

        let dderror = DDError(error: error)
        setAttribute(key: DDTags.errorType, value: dderror.title)
        setAttribute(key: DDTags.errorMessage, value: dderror.message)
        setAttribute(key: DDTags.errorStack, value: dderror.details)
    }
}
