/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation
import OpenTelemetrySdk

@objc public class DDInstrumentationControl: NSObject {
    @objc public static func startInjectingHeaders() {
        DDTestMonitor.instance?.injectHeaders = true
    }

    @objc public static func stopInjectingHeaders() {
        DDTestMonitor.instance?.injectHeaders = false
    }

    @objc public static func startPayloadCapture() {
        DDTestMonitor.instance?.recordPayload = true
    }

    @objc public static func stopPayloadCapture() {
        DDTestMonitor.instance?.recordPayload = false
    }

    @objc public static func startStdoutCapture() {
        DDTestMonitor.instance?.startStdoutCapture()
    }

    @objc public static func stopStdoutCapture() {
        DDTestMonitor.instance?.stopStdoutCapture()
    }

    @objc public static func startStderrCapture() {
        DDTestMonitor.instance?.startStderrCapture()
    }

    @objc public static func stopStderrCapture() {
        DDTestMonitor.instance?.stopStderrCapture()
    }

    public static var openTelemetryTracer: TracerSdk? {
        return DDTestMonitor.instance?.tracer.tracerSdk
    }
}
