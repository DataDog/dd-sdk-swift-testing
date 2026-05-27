/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

internal import EventsExporter
import Foundation
internal import KSCrashRecording
internal import OpenTelemetryApi


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


/// File-scope `@convention(c)` callback handed to `KSCrashConfiguration.isWritingReportCallback`.
/// Runs in the crash-time exception handling context (subject to the async-safety constraints
/// described by `KSCrash_ExceptionHandlingPlan`). Mirrors the prior PLCrashReporter signal callback.
private let ddCrashIsWritingReportCallback: @convention(c) (
    UnsafePointer<ExceptionHandlingPlan>, UnsafePointer<ReportWriter>
) -> Void = { _, _ in
    if let info = SanitizerHelper.getSaniziterInfo(), let url = DDCrashes.sanitizerURL {
        try? info.write(to: url, atomically: true, encoding: .utf8)
    }
    if let url = DDCrashes.spanURL, let test = DDTest.current {
        let data = SimpleSpanSerializer.serializeSpan(simpleSpan: test.toCrashData)
        try? data.write(to: url, options: .atomic)
    }
    DDTestMonitor.instance?.tia?.stop()
    DDTestMonitor.instance?.coverage?.stop()
    Log.print("Crash detected! Exiting...")
}


/// This class is our interface with the crash reporter, now backed by KSCrash.
internal enum DDCrashes {
    private static let userInfoSpanKey = "dd.span"
    private static var installed = false
    fileprivate static var sanitizerURL: URL?
    fileprivate static var spanURL: URL?

    static func install(folder: Directory, disableMach: Bool) {
        guard !installed else { return }
        installed = true
        installKSCrashHandler(folder: folder, disableMach: disableMach)
    }

    static func setCurrent(spanData: SimpleSpanData?) {
        let bytes = spanData.map { SimpleSpanSerializer.serializeSpan(simpleSpan: $0) } ?? Data()
        KSCrash.shared.userInfo = [userInfoSpanKey: bytes.base64EncodedString()]
    }

    private static func installKSCrashHandler(folder: Directory, disableMach: Bool) {
        let baseURL = folder.url
        sanitizerURL = baseURL.appendingPathComponent("Sanitizer.log", isDirectory: false)
        spanURL = baseURL.appendingPathComponent("Span.json", isDirectory: false)

        let config = KSCrashConfiguration()
        config.installPath = baseURL.path
        var monitors: MonitorType = [.signal, .nsException, .cppException]
        if !disableMach {
            monitors.insert(.machException)
        }
        config.monitors = monitors
        config.deadlockWatchdogInterval = 0

        // `isWritingReportCallback` is a `@convention(c)` function pointer — it cannot capture
        // locals. Everything below is a static property/function access, so the closure is
        // non-capturing. The plan/writer parameters are unused.
        config.isWritingReportCallback = ddCrashIsWritingReportCallback

        do {
            try KSCrash.shared.install(with: config)
        } catch {
            Log.debug("KSCrash install failed: \(error)")
            return
        }

        handleKSCrashReport()
    }

    /// Loads any pending crash report from a previous launch, builds the CrashInformation, and purges the report.
    private static func handleKSCrashReport() {
        defer {
            sanitizerURL.flatMap { try? FileManager.default.removeItem(at: $0) }
            spanURL.flatMap { try? FileManager.default.removeItem(at: $0) }
        }

        if let url = sanitizerURL,
           FileManager.default.fileExists(atPath: url.path),
           let content = try? String(contentsOf: url)
        {
            SanitizerHelper.setSaniziterInfo(info: content)
            Log.debug("Loaded Sanitizer Info from crash")
        }

        guard let store = KSCrash.shared.reportStore,
              let firstID = store.reportIDs.first
        else {
            return
        }
        let reportID = firstID.int64Value
        defer {
            store.deleteReport(with: reportID)
            Log.debug("Crash report \(reportID) loaded and purged")
        }

        guard let report = store.report(for: reportID)?.value,
              var crashLog = CrashLog(report: report)
        else { return }

        DDSymbolicator.symbolicate(&crashLog)

        let crashTimestamp = crashLog.timestamp ?? Date()
        let (errorType, errorMessage) = crashLog.header.errorTypeAndMessage()
        let error = TestError(type: errorType, message: errorMessage, stack: crashLog.render())

        var crashedInfo: CrashInformation? = nil

        if let url = spanURL,
           FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let spanData = SimpleSpanSerializer.deserializeSpan(data: data)
        {
            DDTestMonitor.tracer.createSpanFromCrash(spanData: spanData,
                                                     crashDate: crashTimestamp,
                                                     error: error)
            crashedInfo = makeTestCrashInfo(spanData: spanData, error: error)
        } else if let userDict = report["user"] as? [String: Any],
                  let base64 = userDict[userInfoSpanKey] as? String,
                  !base64.isEmpty,
                  let data = Data(base64Encoded: base64),
                  let spanData = SimpleSpanSerializer.deserializeSpan(data: data)
        {
            crashedInfo = makeModuleOrSuiteCrashInfo(spanData: spanData, error: error)
        }

        if let info = crashedInfo {
            DDTestMonitor.instance?.crashInfo = info
            Log.debug("Loaded Crash Info: \(info)")
        }
    }

    // MARK: - Crash info reconstruction

    private static func makeTestCrashInfo(spanData: SimpleSpanData, error: TestError) -> CrashInformation? {
        guard let sessionID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testSessionId],
              let moduleID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testModuleId],
              let suiteID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testSuiteId],
              let suiteName = spanData.stringAttributes[DDTestTags.testSuite],
              let moduleName = spanData.stringAttributes[DDTestTags.testModule]
        else { return nil }
        return .test(id: SpanId(id: spanData.spanId),
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

    private static func makeModuleOrSuiteCrashInfo(spanData: SimpleSpanData, error: TestError) -> CrashInformation? {
        guard let sessionID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testSessionId] else { return nil }
        if let suiteStart = spanData.suiteStartTime,
           let moduleID = spanData.stringAttributes[DDTestSuiteVisibilityTags.testModuleId],
           let moduleName = spanData.stringAttributes[DDTestTags.testModule]
        {
            return .suite(id: SpanId(id: spanData.spanId),
                          name: spanData.name,
                          startTime: suiteStart,
                          error: error,
                          module: (id: SpanId(fromHexString: moduleID),
                                   name: moduleName,
                                   startTime: spanData.moduleStartTime),
                          session: (id: SpanId(fromHexString: sessionID),
                                    startTime: spanData.sessionStartTime))
        }
        return .module(id: SpanId(id: spanData.spanId),
                       name: spanData.name,
                       startTime: spanData.moduleStartTime,
                       error: error,
                       session: (id: SpanId(fromHexString: sessionID),
                                 startTime: spanData.sessionStartTime))
    }

}
