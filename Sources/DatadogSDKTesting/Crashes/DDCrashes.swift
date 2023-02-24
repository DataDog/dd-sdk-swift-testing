/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

@_implementationOnly import CrashReporter
import Foundation
@_implementationOnly import OpenTelemetryApi

let signalCallback: PLCrashReporterPostCrashSignalCallback = { _, _, _ in
    if let sanitizerInfo = SanitizerHelper.getSaniziterInfo() {
        try? sanitizerInfo.write(to: DDCrashes.sanitizerURL, atomically: true, encoding: .utf8)
    }
    DDTestMonitor.instance?.coverageHelper?.coverageWorkQueue.waitUntilAllOperationsAreFinished()
}

/// This class is our interface with the crash reporter, now it is based on PLCrashReporter,
/// but we could modify this class to use another if needed
internal enum DDCrashes {
    private static var sharedPLCrashReporter: PLCrashReporter?
    private static var crashCustomData = [String: Data]()
    fileprivate static var sanitizerURL: URL!

    static func install() {
        if sharedPLCrashReporter == nil {
            installPLCrashReporterHandler()
        }
    }

    private static func installPLCrashReporterHandler() {
        let crashDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("com.datadoghq.datadogsdktesting", isDirectory: true)
#if os(macOS)
        let config = PLCrashReporterConfig(signalHandlerType: .mach, symbolicationStrategy: [], basePath: crashDir?.path)
#else
        let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: [], basePath: crashDir?.path)
#endif
        guard let plCrashReporter = PLCrashReporter(configuration: config) else {
            return
        }

        let reportURL = URL(fileURLWithPath: plCrashReporter.crashReportPath())
        sanitizerURL = reportURL.deletingLastPathComponent().appendingPathComponent("SanitizerLog")

        var callback = PLCrashReporterCallbacks(version: 0, context: nil, handleSignal: signalCallback)
        plCrashReporter.setCrash(&callback)
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
        let purgeSuccess = plCrashReporter.purgePendingCrashReport()
        Log.debug("Crash report loaded and purged with status: \(purgeSuccess)")

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

                    DDTestMonitor.tracer.createSpanFromCrash(spanData: spanData,
                                                             crashDate: crashReport.systemInfo.timestamp,
                                                             errorType: errorType,
                                                             errorMessage: errorMessage,
                                                             errorStack: crashLog)
                    if let executionOrderString = spanData.stringAttributes[DDTestTags.testExecutionOrder],
                       let executionOrder = Int(executionOrderString),
                       let executionProcessIdString = spanData.stringAttributes[DDTestTags.testExecutionProcessId],
                       let processId = Int(executionProcessIdString),
                       let sessionID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testSessionId],
                       let moduleID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testModuleId],
                       let suiteID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testSuiteId],
                       let suiteName = spanData.stringAttributes[DDTestTags.testSuite]
                    {
                        DDTestMonitor.instance?.currentTest?.currentTestExecutionOrder = executionOrder
                        DDTestMonitor.instance?.currentTest?.initialProcessId = processId
                        DDTestMonitor.instance?.crashedModuleInfo = CrashedModuleInformation(
                            crashedSessionId: SpanId(fromHexString: sessionID),
                            crashedModuleId: SpanId(fromHexString: moduleID),
                            crashedSuiteId: SpanId(fromHexString: suiteID),
                            crashedSuiteName: suiteName,
                            moduleStartTime: spanData.moduleStartTime,
                            suiteStartTime: spanData.suiteStartTime)
                        Log.debug("Loaded Crashed Session Info: \(sessionID)")
                    }

                    // Sanitizer info
                    if FileManager.default.fileExists(atPath: sanitizerURL.path),
                       let content = try? String(contentsOf: sanitizerURL)
                    {
                        SanitizerHelper.setSaniziterInfo(info: content)
                        try? FileManager.default.removeItem(at: sanitizerURL)
                        Log.debug("Loaded Sanitizer Info from crash")
                    }
                }
            }
        }
    }

    static func setCustomData(customData: Data) {
        DDCrashes.sharedPLCrashReporter?.customData = customData
    }
}
