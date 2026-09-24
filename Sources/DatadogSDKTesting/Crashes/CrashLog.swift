/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import KSCrashRecordingCore
internal import KSCrashReportModel

/// Structured representation of a KSCrash crash report. Symbolication operates on these
/// frames in place, and `render()` produces the human-readable text only when needed.
internal struct CrashLog {
    var header: Header
    var threads: [Thread]
    var binaryImages: [BinaryImage]
    var timestamp: Date?

    struct Header {
        var exceptionType: String?
        var signalName: String?
        var signalNumber: Int?
        var signalCodeName: String?
        var machExceptionName: String?
        var machCodeName: String?
        var nsExceptionName: String?
        var cppExceptionName: String?
        var reason: String?
    }

    struct Thread {
        var index: Int
        var crashed: Bool
        var frames: [Frame]
    }

    struct Frame {
        var index: Int
        var library: String
        var instructionAddress: UInt64
        var objectAddress: UInt64
        var symbolicated: String?
    }

    struct BinaryImage {
        var address: UInt64
        var size: UInt64
        var name: String
        var arch: String
        var uuid: String
    }
}

extension CrashLog {
    /// Build a `CrashLog` from a typed KSCrash report (`KSCrashReportModel.CrashReport`).
    init<UserData>(report: CrashReport<UserData>) {
        let crash = report.crash
        let error = crash.error

        self.header = Header(
            exceptionType: error.type.rawValue,
            signalName: error.signal?.name,
            signalNumber: error.signal.map { Int($0.signal) },
            signalCodeName: error.signal?.codeName,
            machExceptionName: error.mach?.exceptionName,
            machCodeName: error.mach?.codeName,
            nsExceptionName: error.nsexception?.name,
            cppExceptionName: error.cppException?.name,
            reason: error.reason ?? error.nsexception?.reason
        )

        self.threads = (crash.threads ?? [])
            .sorted { ($0.crashed ? 0 : 1) < ($1.crashed ? 0 : 1) }
            .map { thread in
                let frames = (thread.backtrace?.contents ?? [])
                    .enumerated()
                    .map { (i, frame) in
                        Frame(
                            index: i,
                            library: frame.objectName ?? "???",
                            instructionAddress: frame.instructionAddr,
                            objectAddress: frame.objectAddr ?? 0,
                            symbolicated: nil
                        )
                    }
                return Thread(index: thread.index, crashed: thread.crashed, frames: frames)
            }

        self.binaryImages = (report.binaryImages ?? []).map { img in
            BinaryImage(
                address: img.imageAddr,
                size: img.imageSize,
                name: img.name,
                arch: Self.archName(cpuType: img.cpuType, cpuSubtype: img.cpuSubtype),
                uuid: img.uuid ?? ""
            )
        }

        self.timestamp = report.report.timestamp
    }

    /// KSCrash only records the raw Mach-O `cputype`/`cpusubtype` per image.
    private static func archName(cpuType: Int, cpuSubtype: Int) -> String {
        guard let name = kscpu_archForCPU(cpu_type_t(truncatingIfNeeded: cpuType),
                                          cpu_subtype_t(truncatingIfNeeded: cpuSubtype))
        else { return "" }
        return String(cString: name)
    }
}

extension CrashLog.Header {
    /// Maps the captured fields to the (errorType, errorMessage) pair surfaced as span tags.
    func errorTypeAndMessage() -> (type: String, message: String) {
        if let name = signalName {
            var type = "Exception Type: \(name)"
            if let codeName = signalCodeName {
                type += "\nException Code: \(codeName)"
            }
            return (type, SignalUtils.descriptionForSignalName(signalName: name))
        }
        if let name = machExceptionName {
            return ("Exception Type: \(name)", machCodeName ?? "")
        }
        if let name = nsExceptionName {
            return ("NSException: \(name)", reason ?? "")
        }
        if let name = cppExceptionName {
            return ("C++ Exception: \(name)", reason ?? "")
        }
        return ("Crash", reason ?? "")
    }
}

extension CrashLog {
    /// Renders the human-readable crash log emitted as the `error.stack` and
    /// `error.crash_log.NN` span tags. Frame layout matches what `DDSymbolicator` produced
    /// in the prior text-based path (single-space separated, frame index padded to 3, library
    /// padded to 30) so any downstream consumers see the same shape.
    func render() -> String {
        var lines: [String] = []

        if let type = header.exceptionType { lines.append("Exception Type: \(type)") }
        if let name = header.signalName, let num = header.signalNumber {
            lines.append("Signal: \(name) (\(num))")
        }
        if let code = header.signalCodeName { lines.append("Signal Code: \(code)") }
        if let name = header.machExceptionName { lines.append("Mach Exception: \(name)") }
        if let code = header.machCodeName { lines.append("Mach Code: \(code)") }
        if let name = header.nsExceptionName { lines.append("NSException: \(name)") }
        if let reason = header.reason { lines.append("Reason: \(reason)") }
        lines.append("")

        for thread in threads {
            lines.append(thread.crashed ? "Thread \(thread.index) Crashed:" : "Thread \(thread.index):")
            for frame in thread.frames {
                lines.append(frame.render())
            }
            lines.append("")
        }

        lines.append("Binary Images:")
        for img in binaryImages {
            let endAddr = img.size > 0 ? img.address &+ img.size &- 1 : img.address
            lines.append("\(Self.hex(img.address)) - \(Self.hex(endAddr)) \(img.name) \(img.arch) <\(img.uuid)>")
        }
        return lines.joined(separator: "\n")
    }

    fileprivate static func hex(_ value: UInt64) -> String {
        String(format: "0x%016llx", value)
    }
}

extension CrashLog.Frame {
    func render() -> String {
        let indexField = Self.padRight(String(index), to: 3)
        let libField = Self.padRight(library, to: 30)
        let pc = CrashLog.hex(instructionAddress)
        if let symbol = symbolicated {
            return "\(indexField) \(libField) \(pc) \(symbol)"
        }
        let base = CrashLog.hex(objectAddress)
        let offset: UInt64 = objectAddress > 0 ? instructionAddress &- objectAddress : 0
        return "\(indexField) \(libField) \(pc) \(base) + \(offset)"
    }

    private static func padRight(_ s: String, to width: Int) -> String {
        guard s.count < width else { return s }
        return s + String(repeating: " ", count: width - s.count)
    }
}
