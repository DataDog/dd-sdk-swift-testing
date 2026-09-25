/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

internal import EventsExporter
import Foundation
internal import KSCrashRecording
internal import KSCrashReportModel
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
) -> Void = { plan, _ in
    // A crash inside this callback (or elsewhere in the handler) re-enters with
    // `crashedDuringExceptionHandling` set; KSCrash asks callbacks to do nothing then.
    // Non-fatal reports (e.g. a recovered hang) are not crashes of the current test.
    // We deliberately ignore `requiresAsyncSafety`: signal/Mach crashes always set it,
    // and the span snapshot below is the whole point of the callback.
    guard !plan.pointee.crashedDuringExceptionHandling, plan.pointee.isFatal else { return }
    if let info = SanitizerHelper.getSaniziterInfo(), let url = DDCrashes.sanitizerURL {
        try? info.write(to: url, atomically: true, encoding: .utf8)
    }
    if let url = DDCrashes.spanURL, let test = DDTest.current {
        let data = SimpleSpanSerializer.serializeSpan(simpleSpan: test.toCrashData)
        try? data.write(to: url, options: .atomic)
    }
    // Nothing here may drain a queue, wait on an OperationQueue, take a lock or
    // touch the network. KSCrash suspends the other threads before writing the
    // report (`ksmc_suspendEnvironment`), so anything that waits on them waits
    // forever — and the work it is waiting for can never run, which makes the
    // attempt pointless as well as deadlock-prone. That rules out flushing the
    // exporters' writer queues and draining the coverage processor here; both
    // have to happen before the crash, or on the next run.
    Log.print("Crash detected! Exiting...")
}


/// The module/suite context we keep in the crash report's `user` section. Each field is a
/// separate key in KSCrash's per-key user info store (mmap'd, so nothing is serialized at
/// crash time). Values are stored flat because the store truncates strings to 1024 bytes,
/// which a serialized span with all its attributes would easily exceed. Longer values are
/// split into `<key>`, `<key>.1`, ... with the chunk count in `<key>.count` (absent = 1).
private struct CrashUserInfo: Codable, Sendable {
    static let maxStringBytes = 1024

    var spanId: String?
    var name: String?
    var sessionId: String?
    var moduleId: String?
    var moduleName: String?
    var sessionStartTime: Double?
    var moduleStartTime: Double?
    var suiteStartTime: Double?

    enum Key: String, CaseIterable {
        case spanId = "dd.span.id"
        case name = "dd.span.name"
        case sessionId = "dd.span.session_id"
        case moduleId = "dd.span.module_id"
        case moduleName = "dd.span.module_name"
        case sessionStartTime = "dd.span.session_start"
        case moduleStartTime = "dd.span.module_start"
        case suiteStartTime = "dd.span.suite_start"

        var count: String { "\(rawValue).count" }

        func chunk(_ index: Int) -> String {
            index == 0 ? rawValue : "\(rawValue).\(index)"
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    static func chunks(of value: String) -> [String] {
        var chunks: [String] = []
        var current = String.UnicodeScalarView()
        var bytes = 0
        for scalar in value.unicodeScalars {
            let size = UTF8.width(scalar)
            if bytes + size > maxStringBytes {
                chunks.append(String(current))
                current = .init()
                bytes = 0
            }
            current.append(scalar)
            bytes += size
        }
        chunks.append(String(current))
        return chunks
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func string(_ key: Key) -> String? {
            let count = (try? c.decodeIfPresent(Int.self, forKey: AnyKey(key.count))) ?? 1
            var parts: [String] = []
            for index in 0..<max(count, 1) {
                guard let part = try? c.decodeIfPresent(String.self, forKey: AnyKey(key.chunk(index)))
                else { return nil }
                parts.append(part)
            }
            return parts.joined()
        }
        func double(_ key: Key) -> Double? {
            try? c.decodeIfPresent(Double.self, forKey: AnyKey(key.rawValue))
        }
        spanId = string(.spanId)
        name = string(.name)
        sessionId = string(.sessionId)
        moduleId = string(.moduleId)
        moduleName = string(.moduleName)
        sessionStartTime = double(.sessionStartTime)
        moduleStartTime = double(.moduleStartTime)
        suiteStartTime = double(.suiteStartTime)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        func put(_ value: String?, _ key: Key) throws {
            guard let chunks = value.map(Self.chunks) else { return }
            for (index, part) in chunks.enumerated() {
                try c.encode(part, forKey: AnyKey(key.chunk(index)))
            }
            if chunks.count > 1 { try c.encode(chunks.count, forKey: AnyKey(key.count)) }
        }
        try put(spanId, .spanId)
        try put(name, .name)
        try put(sessionId, .sessionId)
        try put(moduleId, .moduleId)
        try put(moduleName, .moduleName)
        try c.encodeIfPresent(sessionStartTime, forKey: AnyKey(Key.sessionStartTime.rawValue))
        try c.encodeIfPresent(moduleStartTime, forKey: AnyKey(Key.moduleStartTime.rawValue))
        try c.encodeIfPresent(suiteStartTime, forKey: AnyKey(Key.suiteStartTime.rawValue))
    }
}


/// `KSCrashRecording` also exports a `CrashReport` (the ObjC `KSCrashReport` protocol).
private typealias TypedCrashReport = KSCrashReportModel.CrashReport<CrashUserInfo>


/// This class is our interface with the crash reporter, now backed by KSCrash.
internal enum DDCrashes {
    private static var installed = false
    fileprivate static var sanitizerURL: URL?
    fileprivate static var spanURL: URL?

    /// Installs the crash handler and loads any crash report from a previous
    /// launch. Returns the reconstructed `CrashInformation` (if the prior run
    /// crashed inside a test) so the caller — the monitor — can store it, instead
    /// of `DDCrashes` reaching back into `DDTestMonitor.instance`.
    @discardableResult
    static func install(folder: Directory, disableMach: Bool, tracer: DDTracer) -> CrashInformation? {
        guard !installed else { return nil }
        installed = true
        return installKSCrashHandler(folder: folder, disableMach: disableMach, tracer: tracer)
    }

    private static let userInfoLock = UnfairLock()

    /// The fields are separate writes, so a crash can observe a half-updated context.
    /// `spanId` is removed first and written last: the reader requires it, so a torn
    /// context is dropped instead of being attributed to the wrong module or suite.
    static func setCurrent(spanData: SimpleSpanData?) {
        typealias Key = CrashUserInfo.Key
        let crash = KSCrash.shared
        // Stale chunks of a longer previous value are left in place: `<key>.count` bounds the read.
        func set(_ value: String?, _ key: Key) {
            guard let chunks = value.map(CrashUserInfo.chunks) else {
                crash.removeUserInfoValue(forKey: key.rawValue)
                return
            }
            for (index, chunk) in chunks.enumerated() {
                crash.setUserInfo(chunk, forKey: key.chunk(index))
            }
            if chunks.count > 1 { crash.setUserInfo(chunks.count, forKey: key.count) }
            else { crash.removeUserInfoValue(forKey: key.count) }
        }
        func set(_ value: Date?, _ key: Key) {
            if let value { crash.setUserInfo(value.timeIntervalSince1970, forKey: key.rawValue) }
            else { crash.removeUserInfoValue(forKey: key.rawValue) }
        }
        userInfoLock.whileLocked {
            crash.removeUserInfoValue(forKey: Key.spanId.rawValue)
            guard let spanData else {
                Key.allCases.forEach { crash.removeUserInfoValue(forKey: $0.rawValue) }
                return
            }
            set(spanData.name, .name)
            set(spanData.stringAttributes[DDTestSuiteVisibilityTags.testSessionId], .sessionId)
            set(spanData.stringAttributes[DDTestSuiteVisibilityTags.testModuleId], .moduleId)
            set(spanData.stringAttributes[DDTestTags.testModule], .moduleName)
            set(spanData.sessionStartTime, .sessionStartTime)
            set(spanData.moduleStartTime, .moduleStartTime)
            set(spanData.suiteStartTime, .suiteStartTime)
            set(SpanId(id: spanData.spanId).hexString, .spanId)
        }
    }

    @discardableResult
    private static func installKSCrashHandler(folder: Directory, disableMach: Bool, tracer: DDTracer) -> CrashInformation? {
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
        // Stitch Swift async continuation frames into current-thread captures
        // (C++/NSException throw sites), which covers `async` Swift Testing tests.
        config.enableSwiftAsyncStackTraces = true
        // Only keep binary images referenced by a backtrace. The full image list
        // is several hundred entries in a test host and only bloats `error.stack`.
        config.enableCompactBinaryImages = true

        // `isWritingReportCallback` is a `@convention(c)` function pointer — it cannot capture
        // locals. Everything below is a static property/function access, so the closure is
        // non-capturing. The plan/writer parameters are unused.
        config.isWritingReportCallback = ddCrashIsWritingReportCallback

        do {
            try KSCrash.shared.install(with: config)
        } catch {
            Log.debug("KSCrash install failed: \(error)")
            return nil
        }

        return handleKSCrashReport(tracer: tracer)
    }

    /// Loads any pending crash report from a previous launch, builds the
    /// CrashInformation, purges the report, and returns the info (if any).
    private static func handleKSCrashReport(tracer: DDTracer) -> CrashInformation? {
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
              let report = loadFatalReport(from: store)
        else {
            return nil
        }

        var crashLog = CrashLog(report: report)

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
            tracer.createSpanFromCrash(spanData: spanData,
                                       crashDate: crashTimestamp,
                                       error: error)
            crashedInfo = makeTestCrashInfo(spanData: spanData, error: error)
        } else if let userInfo = report.user {
            crashedInfo = makeModuleOrSuiteCrashInfo(userInfo: userInfo, error: error)
        }

        if let info = crashedInfo {
            Log.debug("Loaded Crash Info: \(info)")
        }
        return crashedInfo
    }

    /// Returns the oldest fatal report in the store and purges every report up to and
    /// including it. Non-fatal reports (resolved hangs, CPU warnings) are discarded: they
    /// are never enabled here, but `KSCrashMonitorTypeRequired` monitors can emit them.
    private static func loadFatalReport(from store: CrashReportStore) -> TypedCrashReport? {
        defer { store.cleanupOrphanedRunSidecars() }
        // Oldest first. Iterating a snapshot rather than polling `nextReportID`
        // means a report that fails to delete can't loop forever.
        for reportID in store.reportIDs.map(\.int64Value).sorted() {
            defer {
                store.deleteReport(with: reportID)
                Log.debug("Crash report \(reportID) loaded and purged")
            }
            guard let data = store.reportData(for: reportID)?.value else { continue }
            let report: TypedCrashReport
            do {
                report = try JSONDecoder().decode(TypedCrashReport.self, from: data)
            } catch {
                Log.debug("Failed decoding crash report \(reportID): \(error)")
                continue
            }
            guard report.crash.error.isFatal != false else { continue }
            return report
        }
        return nil
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

    private static func makeModuleOrSuiteCrashInfo(userInfo: CrashUserInfo, error: TestError) -> CrashInformation? {
        guard let spanID = userInfo.spanId,
              let name = userInfo.name,
              let sessionID = userInfo.sessionId,
              let sessionStart = userInfo.sessionStartTime,
              let moduleStart = userInfo.moduleStartTime
        else { return nil }
        let session = (id: SpanId(fromHexString: sessionID),
                       startTime: Date(timeIntervalSince1970: sessionStart))
        if let suiteStart = userInfo.suiteStartTime,
           let moduleID = userInfo.moduleId,
           let moduleName = userInfo.moduleName
        {
            return .suite(id: SpanId(fromHexString: spanID),
                          name: name,
                          startTime: Date(timeIntervalSince1970: suiteStart),
                          error: error,
                          module: (id: SpanId(fromHexString: moduleID),
                                   name: moduleName,
                                   startTime: Date(timeIntervalSince1970: moduleStart)),
                          session: session)
        }
        return .module(id: SpanId(fromHexString: spanID),
                       name: name,
                       startTime: Date(timeIntervalSince1970: moduleStart),
                       error: error,
                       session: session)
    }

}
