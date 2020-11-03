/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

class StderrCapture {
    let inputPipe = Pipe()
    let outputPipe = Pipe()
    var originalDescriptor = FileHandle.standardError.fileDescriptor
    private let syncCondition = NSCondition()
    
    static var logDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    func startCapturing(tracer: DDTracer) {
        inputPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            guard let strongSelf = self else { return }

            let data = fileHandle.availableData
            if let string = String(data: data, encoding: String.Encoding.utf8) {
                strongSelf.stderrMessage(tracer: tracer, string: string)
            }

            // Write input back to stderr
            strongSelf.outputPipe.fileHandleForWriting.write(data)
        }

        // Copy STDERR file descriptor to outputPipe for writing strings back to STDERR
        dup2(FileHandle.standardError.fileDescriptor, outputPipe.fileHandleForWriting.fileDescriptor)

        // Intercept STDERR with inputPipe
        dup2(inputPipe.fileHandleForWriting.fileDescriptor, FileHandle.standardError.fileDescriptor)
    }

    func stopCapturing() {
        freopen("/dev/stderr", "a", stderr)
    }

    func stderrMessage(tracer: DDTracer, string: String) {
        guard tracer.activeTestSpan != nil ||
                tracer.tracerSdk.currentSpan != nil ||
                tracer.launchSpanContext != nil else {
            return
        }

        string.enumerateLines { line, _ in
            if line.prefix(8) == "    t = " {
                self.logUIStep(tracer: tracer, string: line)
            } else {
                self.logTimedErrOutput(tracer: tracer, string: line)
            }
        }
    }

    func logTimedErrOutput(tracer: DDTracer, string: String) {
        let scanner = Scanner(string: string)
        let space = CharacterSet.whitespaces

        var dateNSString: NSString?
        var timeNSString: NSString?
        scanner.scanUpToCharacters(from: space, into: &dateNSString)
        scanner.scanUpToCharacters(from: space, into: &timeNSString)
        guard let dateString = dateNSString as String?,
            let timeString = timeNSString as String?,
            let date = StderrCapture.logDateFormatter.date(from: dateString + " " + timeString) else {
            return
        }

        var processId: NSString?
        scanner.scanUpToCharacters(from: space, into: &processId)
        var message: String?
        if !scanner.isAtEnd {
            let currentIndex = scanner.string.index(scanner.string.startIndex, offsetBy: scanner.scanLocation + 1)
            message = String(scanner.string.suffix(from: currentIndex))
        }

        if let message = message {
            tracer.logString(string: message, date: date)
        } else {
            syncCondition.signal()
        }
    }

    func logUIStep(tracer: DDTracer, string: String) {
        let scanner = Scanner(string: string)
        let space = CharacterSet.whitespaces

        var timeFromStart = 0.0

        scanner.scanString("t =", into: nil)
        scanner.scanDouble(&timeFromStart)
        scanner.scanUpToCharacters(from: space, into: nil)
        var message: String?
        if !scanner.isAtEnd {
            let scannerLocIndex = scanner.string.index(scanner.string.startIndex, offsetBy: scanner.scanLocation + 1)
            message = String(scanner.string[scannerLocIndex...])
        }

        if let message = message {
            tracer.logString(string: message, timeIntervalSinceSpanStart: timeFromStart)
        }
    }

    func synchronize() {
        NSLog("")
        syncCondition.wait(until: Date().addingTimeInterval(1))
    }
}
