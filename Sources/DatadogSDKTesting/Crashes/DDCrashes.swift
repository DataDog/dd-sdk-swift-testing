/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import CrashReporter
import Foundation

/// This class is our interface with the crash reporter, now it is based on PLCrashReporter,
/// but we could modify this class to use another if needed
internal class DDCrashes {
    private static var sharedPLCrashReporter: PLCrashReporter?
    private static var crashCustomData = [String: Data]()

    static func install() {
        if sharedPLCrashReporter == nil {
            installPLCrashReporterHandler()
        }
    }

    private static func installPLCrashReporterHandler() {
        let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all)
        guard let plCrashReporter = PLCrashReporter(configuration: config) else {
            return
        }
        sharedPLCrashReporter = plCrashReporter
        handlePLCrashReport()
        plCrashReporter.enable()
    }

    /// This method loads existing crash reports and purge the folder.
    /// If the crash  contains a serialized span it passes this data to the tracer to recreate the crashed span
    private static func handlePLCrashReport() {
        guard let plCrashReporter = sharedPLCrashReporter,
            plCrashReporter.hasPendingCrashReport() else {
            return
        }

        let crashData = plCrashReporter.loadPendingCrashReportData()
        plCrashReporter.purgePendingCrashReport()

        if let crashReport = try? PLCrashReport(data: crashData) {
            let crashLog = PLCrashReportTextFormatter.stringValue(for: crashReport, with: PLCrashReportTextFormatiOS) ?? ""
            // This code needs our PR for PLCrashReporter
            if let customData = crashReport.customData {
                if let spanData = SimpleSpanSerializer.deserializeSpan(data: customData) {
                    var crashInfo = ""
                    if let name = crashReport.signalInfo.name {
                        crashInfo += "Exception Type: \(name)"
                    }
                    if let code = crashReport.signalInfo.code {
                        crashInfo += "\nException Code: \(code)"
                    }
                    DDTestMonitor.instance?.tracer.createSpanFromCrash(spanData: spanData,
                                                                       crashDate: crashReport.systemInfo.timestamp,
                                                                       crashInfo: crashInfo,
                                                                       crashLog: crashLog)
                }
            }
        }
    }

    public static func setCustomData(customData: Data) {
        DDCrashes.sharedPLCrashReporter?.customData = customData
    }
}
