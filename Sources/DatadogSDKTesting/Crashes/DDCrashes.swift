/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

internal import CrashReporter
internal import EventsExporter
import Foundation
internal import OpenTelemetryApi

let signalCallback: PLCrashReporterPostCrashSignalCallback = { _, _, _ in
    if let sanitizerInfo = SanitizerHelper.getSaniziterInfo(),
       let url = DDCrashes.sanitizerURL
    {
        try? sanitizerInfo.write(to: url, atomically: true, encoding: .utf8)
    }
    
    if let url = DDCrashes.spanURL, let test = Test.current {
        let data = SimpleSpanSerializer.serializeSpan(simpleSpan: test.toCrashData)
        try? data.write(to: url, options: .atomic)
    }
    
    DDTestMonitor.instance?.tia?.stop()
    Log.print("Crash detected! Exiting...")
}


enum CrashInformation {
    case module(id: SpanId, name: String, startTime: Date, error: TestError,
                session: (id: SpanId, startTime: Date))
    case suite(id: SpanId, name: String, startTime: Date, error: TestError,
               module: (id: SpanId, name: String, startTime: Date),
               session: (id: SpanId, startTime: Date))
    case test(id: SpanId, name: String, startTime: Date, error: TestError,
              suite: (id: SpanId, name: String, startTime: Date),
              module: (id: SpanId, name: String, startTime: Date),
              session: (id: SpanId, startTime: Date))
    
    var session: (id: SpanId, startTime: Date) {
        switch self {
        case .module(id: _, name: _, startTime: _,
                     error: _, session: let s): return s
        case .suite(id: _, name: _, startTime: _,
                    error: _, module: _, session: let s): return s
        case .test(id: _, name: _, startTime: _, error: _,
                   suite: _, module: _, session: let s): return s
        }
    }
    
    var module: (id: SpanId, name: String, startTime: Date, error: TestError?) {
        switch self {
        case .module(id: let i, name: let n, startTime: let s,
                     error: let e, session: _): return (i, n, s, e)
        case .suite(id: _, name: _, startTime: _, error: _,
                    module: let m, session: _): return (m.id, m.name, m.startTime, nil)
        case .test(id: _, name: _, startTime: _, error: _,
                   suite: _, module: let m, session: _): return (m.id, m.name, m.startTime, nil)
        }
    }
    
    var suite: (id: SpanId, name: String, startTime: Date, error: TestError?)? {
        switch self {
        case .suite(id: let i, name: let n, startTime: let s,
                    error: let e, module: _, session: _): return (i, n, s, e)
        case .test(id: _, name: _, startTime: _, error: _,
                   suite: let s, module: _, session: _): return (s.id, s.name, s.startTime, nil)
        default: return nil
        }
    }
    
    var test: (id: SpanId, name: String, startTime: Date, error: TestError)? {
        switch self {
        case .test(id: let i, name: let n, startTime: let s, error: let e,
                   suite: _, module: _, session: _): return (i, n, s, e)
        default: return nil
        }
    }
    
    var error: TestError {
        switch self {
        case .module(id: _, name: _, startTime: _, error: let e, session: _): return e
        case .suite(id: _, name: _, startTime: _, error: let e, module: _, session: _): return e
        case .test(id: _, name: _, startTime: _, error: let e, suite: _, module: _, session: _): return e
        }
    }
}


/// This class is our interface with the crash reporter, now it is based on PLCrashReporter,
/// but we could modify this class to use another if needed
internal enum DDCrashes {
    private static var sharedPLCrashReporter: PLCrashReporter?
    fileprivate static var sanitizerURL: URL?
    fileprivate static var spanURL: URL?

    static func install(folder: Directory, disableMach: Bool) {
        if sharedPLCrashReporter == nil {
            installPLCrashReporterHandler(folder: folder, disableMach: disableMach)
        }
    }

    private static func installPLCrashReporterHandler(folder: Directory, disableMach: Bool) {
        let signalHandler: PLCrashReporterSignalHandlerType
        #if os(macOS) || os(iOS)
            signalHandler = disableMach ? .BSD : .mach
        #else
            signalHandler = .BSD
        #endif
        let config = PLCrashReporterConfig(signalHandlerType: signalHandler,
                                           symbolicationStrategy: [],
                                           basePath: folder.url.path)
        guard let plCrashReporter = PLCrashReporter(configuration: config) else {
            return
        }

        let reportURL = URL(fileURLWithPath: plCrashReporter.crashReportPath(), isDirectory: true)
        sanitizerURL = reportURL
            .deletingLastPathComponent()
            .appendingPathComponent("Sanitizer.log", isDirectory: false)
        spanURL = reportURL
            .deletingLastPathComponent()
            .appendingPathComponent("Span.json", isDirectory: false)

        var callback = PLCrashReporterCallbacks(version: 0, context: nil, handleSignal: signalCallback)
        plCrashReporter.setCrash(&callback)
        sharedPLCrashReporter = plCrashReporter
        handlePLCrashReport()
        plCrashReporter.enable()
    }

    /// This method loads existing crash reports and purge the folder.
    /// If the crash  contains a serialized span it passes this data to the tracer to recreate the crashed span
    private static func handlePLCrashReport() {
        defer {
            sanitizerURL.flatMap { try? FileManager.default.removeItem(at: $0) }
            spanURL.flatMap { try? FileManager.default.removeItem(at: $0) }
        }
        
        // Sanitizer info
        if FileManager.default.fileExists(atPath: sanitizerURL!.path),
           let content = try? String(contentsOf: sanitizerURL!)
        {
            SanitizerHelper.setSaniziterInfo(info: content)
            Log.debug("Loaded Sanitizer Info from crash")
        }
        
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
            
            var errorType = "Crash"
            var errorMessage = ""
            if let name = crashReport.signalInfo.name {
                errorType = "Exception Type: \(name)"
                errorMessage = SignalUtils.descriptionForSignalName(signalName: name)

                if let code = crashReport.signalInfo.code {
                    errorType += "\nException Code: \(code)"
                }
            }
            
            let error = TestError(type: errorType, message: errorMessage, stack: crashLog)
            
            var crashedInfo: CrashInformation? = nil
            
            if FileManager.default.fileExists(atPath: spanURL!.path),
               let data = try? Data(contentsOf: spanURL!),
               let spanData = SimpleSpanSerializer.deserializeSpan(data: data)
            {
                DDTestMonitor.tracer.createSpanFromCrash(spanData: spanData,
                                                         crashDate: crashReport.systemInfo.timestamp,
                                                         error: error)
                
                if let sessionID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testSessionId],
                   let moduleID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testModuleId],
                   let suiteID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testSuiteId],
                   let suiteName = spanData.stringAttributes[DDTestTags.testSuite],
                   let moduleName = spanData.stringAttributes[DDTestTags.testModule]
                {
                    crashedInfo = .test(id: SpanId(id: spanData.spanId),
                                        name: spanData.name,
                                        startTime: spanData.startTime,
                                        error: error,
                                        suite: (id: SpanId(fromHexString: suiteID),
                                                name: suiteName,
                                                startTime: spanData.suiteStartTime!),
                                        module: (id: SpanId(fromHexString: moduleID),
                                                 name: moduleName,
                                                 startTime: spanData.moduleStartTime),
                                        session: (id: SpanId(fromHexString: sessionID),
                                                  startTime: spanData.sessionStartTime))
                }
            } else if let customData = crashReport.customData,
                      let spanData = SimpleSpanSerializer.deserializeSpan(data: customData)
            {
                // This is a module or suite
                if let sessionID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testSessionId] {
                    if let suiteStart = spanData.suiteStartTime,
                       let moduleID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testModuleId],
                       let moduleName = spanData.stringAttributes[DDTestTags.testModule]
                    {
                        crashedInfo = .suite(id: SpanId(id: spanData.spanId),
                                             name: spanData.name,
                                             startTime: suiteStart,
                                             error: error,
                                             module: (id: SpanId(fromHexString: moduleID),
                                                      name: moduleName,
                                                      startTime: spanData.moduleStartTime),
                                             session: (id: SpanId(fromHexString: sessionID),
                                                       startTime: spanData.sessionStartTime))
                    } else {
                        crashedInfo = .module(id: SpanId(id: spanData.spanId),
                                              name: spanData.name,
                                              startTime: spanData.moduleStartTime,
                                              error: error,
                                              session: (id: SpanId(fromHexString: sessionID),
                                                        startTime: spanData.sessionStartTime))
                    }
                }
            }
            if let info = crashedInfo {
                DDTestMonitor.instance?.crashInfo = info
                Log.debug("Loaded Crash Info: \(info)")
            }
        }
    }
    
    static func setCurrent(spanData: SimpleSpanData?) {
        let data = spanData.map { SimpleSpanSerializer.serializeSpan(simpleSpan: $0) } ?? .init()
        DDCrashes.sharedPLCrashReporter?.customData = data
    }
}
