/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import DatadogExporter

internal class DDTestMonitor {
    static var instance: DDTestMonitor?

    let tracer: DDTracer
    var testObserver: DDTestObserver
    var networkInstrumentation: DDNetworkInstrumentation?
    var stderrCapturer: StderrCapture
    var injectHeaders: Bool = false
    var recordPayload: Bool = false

    init() {
        tracer = DDTracer()
        testObserver = DDTestObserver(tracer: tracer)
        stderrCapturer = StderrCapture()
    }

    func startInstrumenting() {
        testObserver.startObserving()
        if !tracer.env.disableNetworkInstrumentation {
            startNetworkAutoInstrumentation()
            if !tracer.env.disableHeadersInjection {
                injectHeaders = true
            }
            if tracer.env.enableRecordPayload {
                recordPayload = true
            }
        }
        if !tracer.env.disableStdoutInstrumentation {
            startStdoutCapture()
        }
        if !tracer.env.disableStderrInstrumentation {
            startStderrCapture()
        }
    }

    func startNetworkAutoInstrumentation() {
        networkInstrumentation = DDNetworkInstrumentation()
    }

    func startHeaderInjection() {
        injectHeaders = true
    }

    func stopHeaderInjection() {
        injectHeaders = false
    }

    func startStdoutCapture() {
        StdoutCapture.startCapturing(tracer: tracer)
    }
    func stopStdoutCapture() {
        StdoutCapture.stopCapturing()
    }

    func startStderrCapture() {
        stderrCapturer.startCapturing(tracer: tracer)
    }
    func stopStderrCapture() {
        stderrCapturer.stopCapturing()
    }
}
