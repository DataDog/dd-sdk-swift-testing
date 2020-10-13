/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import DatadogExporter
import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

enum DDHeaders: String, CaseIterable {
    case traceIDField = "x-datadog-trace-id"
    case parentSpanIDField = "x-datadog-parent-id"
}

internal class DDTracer {
    let tracerSdk: TracerSdk
    let env = DDEnvironmentValues()
    var spanProcessor: SpanProcessor
    let datadogExporter: DatadogExporter

    init() {
        tracerSdk = OpenTelemetrySDK.instance.tracerProvider.get(instrumentationName: "hq.datadog.testing", instrumentationVersion: "0.1.0") as! TracerSdk

        let exporterConfiguration = ExporterConfiguration(
            serviceName: env.ddService ?? ProcessInfo.processInfo.processName,
            resource: "Resource",
            applicationName: "SimpleExporter",
            applicationVersion: "0.0.1",
            environment: env.ddEnvironment ?? "ci",
            clientToken: env.ddClientToken ?? "",
            endpoint: Endpoint.us,
            uploadCondition: { true },
            performancePreset: .instantDataDelivery
        )

        datadogExporter = try! DatadogExporter(config: exporterConfiguration)
        spanProcessor = SimpleSpanProcessor(spanExporter: datadogExporter)

        OpenTelemetrySDK.instance.tracerProvider.addSpanProcessor(spanProcessor)
    }

    func startSpan(name: String, attributes: [String: String]) -> RecordEventsReadableSpan {
        let spanBuilder = tracerSdk.spanBuilder(spanName: name)
        attributes.forEach {
            spanBuilder.setAttribute(key: $0.key, value: $0.value)
        }
        let span = spanBuilder.startSpan() as! RecordEventsReadableSpan
        _ = tracerSdk.withSpan(span)
        return span
    }

    func flush() {
        spanProcessor.forceFlush()
    }

    func tracePropagationHTTPHeaders() -> [String: String] {
        var headers = [String: String]()

        struct HeaderSetter: Setter {
            func set(carrier: inout [String: String], key: String, value: String) {
                carrier[key] = value
            }
        }

        guard let currentSpan = tracerSdk.currentSpan else {
            return headers
        }
        tracerSdk.textFormat.inject(spanContext: currentSpan.context, carrier: &headers, setter: HeaderSetter())

        headers[DDHeaders.traceIDField.rawValue] = String(format: "%016llx", currentSpan.context.traceId.rawLowerLong)
        headers[DDHeaders.parentSpanIDField.rawValue] = currentSpan.context.spanId.hexString

        return headers
    }

    func endpointURLs() -> Set<String> {
        return datadogExporter.endpointURLs()
    }
}
