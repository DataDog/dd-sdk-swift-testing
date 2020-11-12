/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import DatadogExporter
#if canImport(Cocoa)
import Cocoa
let launchNotificationName = NSApplication.didFinishLaunchingNotification
#elseif canImport(UIKit)
import UIKit
let launchNotificationName = UIApplication.didFinishLaunchingNotification
#endif

internal class DDTestMonitor {
    static var instance: DDTestMonitor?

    let tracer: DDTracer
    var testObserver: DDTestObserver?
    var networkInstrumentation: NetworkAutoInstrumentation?
    var stderrCapturer: StderrCapture
    var injectHeaders: Bool = false
    var notificationObserver: NSObjectProtocol?

    init() {
        tracer = DDTracer()
        stderrCapturer = StderrCapture()
        ///If the library is being loaded in a binary launched from a UITest, dont start test observing
        if !tracer.isBinaryUnderUITesting {
            testObserver = DDTestObserver(tracer: tracer)
        }  else {
            notificationObserver = NotificationCenter.default.addObserver(
                forName: launchNotificationName,
                object: nil, queue: nil) { _ in
                /// As crash reporter is initialized in testBundleWillStart() method, we initialize it here
                /// because dont have test observer
                DDCrashes.install()
                let launchedSpan = self.tracer.createSpanFromContext(spanContext: self.tracer.launchSpanContext!)
                let simpleSpan = SimpleSpanData(spanData: launchedSpan.toSpanData())
                DDCrashes.setCustomData(customData: SimpleSpanSerializer.serializeSpan(simpleSpan: simpleSpan))
            }
        }
    }

    func startInstrumenting() {
        testObserver?.startObserving()
        if !tracer.env.disableNetworkInstrumentation {
            startNetworkAutoInstrumentation()
            if !tracer.env.disableHeadersInjection {
                injectHeaders = true
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
        let urlFilter = URLFilter(excludedURLs: tracer.endpointURLs())
        networkInstrumentation = NetworkAutoInstrumentation(urlFilter: urlFilter)
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
