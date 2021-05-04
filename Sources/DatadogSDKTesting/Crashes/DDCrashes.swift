/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import CrashReporter
import Foundation

/// This class is our interface with the crash reporter, now it is based on PLCrashReporter,
/// but we could modify this class to use another if needed
internal enum DDCrashes {
    private static var sharedPLCrashReporter: PLCrashReporter?
    private static var crashCustomData = [String: Data]()

    static func install() {
        if sharedPLCrashReporter == nil {
            installPLCrashReporterHandler()
        }
    }

    private static func installPLCrashReporterHandler() {
        let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: [])
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
              plCrashReporter.hasPendingCrashReport()
        else {
            return
        }

        let crashData = plCrashReporter.loadPendingCrashReportData()
        plCrashReporter.purgePendingCrashReport()

        if let crashReport = try? PLCrashReport(data: crashData) {
            var crashLog = PLCrashReportTextFormatter.stringValue(for: crashReport, with: PLCrashReportTextFormatiOS) ?? ""

            let symbolicated = DDSymbolicator.symbolicate(crashLog: crashLog)
            if !symbolicated.isEmpty {
                crashLog = symbolicated
            }

            if let customData = crashReport.customData {
                if let spanData = SimpleSpanSerializer.deserializeSpan(data: customData) {
                    var errorType = "Crash"
                    var errorMessage = ""
                    if let name = crashReport.signalInfo.name {
                        errorType = "Exception Type: \(name)"
                        errorMessage = SignalUtils.descriptionForSignalName(signalName: name)

                        if let code = crashReport.signalInfo.code {
                            errorType += "\nException Code: \(code)"
                        }
                    }
                    DDTestMonitor.instance?.tracer.createSpanFromCrash(spanData: spanData,
                                                                       crashDate: crashReport.systemInfo.timestamp,
                                                                       errorType: errorType,
                                                                       errorMessage: errorMessage,
                                                                       errorStack: crashLog)
                }
            }
        }
    }

    public static func setCustomData(customData: Data) {
        DDCrashes.sharedPLCrashReporter?.customData = customData
    }
}
