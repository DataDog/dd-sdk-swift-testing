/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

class StderrCapture {
    var isCapturing = false
    var tracer: DDTracer?
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private var originalDescriptor = FileHandle.standardError.fileDescriptor

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
        setvbuf(stderr, nil, _IONBF, 0)

        // Copy STDERR file descriptor to outputPipe for writing strings back to STDERR
        dup2(FileHandle.standardError.fileDescriptor, outputPipe.fileHandleForWriting.fileDescriptor)

        // Intercept STDERR with inputPipe
        dup2(inputPipe.fileHandleForWriting.fileDescriptor, FileHandle.standardError.fileDescriptor)

        self.tracer = tracer
        isCapturing = true
    }

    func syncData() {
        guard inputPipe.fileHandleForReading.isReadable else {
            return
        }

        var synchronizeData: DispatchWorkItem!
        synchronizeData = DispatchWorkItem(block: {
            let auxData = self.inputPipe.fileHandleForReading.availableData
            if synchronizeData.isCancelled {
                return
            }
            if !auxData.isEmpty,
               let tracer = self.tracer,
               let string = String(data: auxData, encoding: String.Encoding.utf8)
            {
                self.stderrMessage(tracer: tracer, string: string)
            }
        })
        DispatchQueue.global().async {
            synchronizeData.perform()
        }
        _ = synchronizeData.wait(timeout: .now() + .milliseconds(10))
        synchronizeData.cancel()
    }

    func stopCapturing() {
        isCapturing = false
        freopen("/dev/stderr", "a", stderr)
    }

    func stderrMessage(tracer: DDTracer, string: String) {
        guard DDTracer.activeSpan != nil ||
            tracer.isBinaryUnderUITesting
        else {
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
        var message: String?

        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, *) {
            guard let dateString = scanner.scanUpToCharacters(from: space),
                  let timeString = scanner.scanUpToCharacters(from: space),
                  let date = StderrCapture.logDateFormatter.date(from: dateString + " " + timeString)
            else {
                return
            }
            _ = scanner.scanUpToCharacters(from: space)
            if !scanner.isAtEnd {
                message = String(scanner.string.suffix(from: scanner.string.index(after: scanner.currentIndex)))
            }

            if let message = message {
                tracer.logString(string: message, date: date)
            }

        } else {
            var dateNSString: NSString?
            var timeNSString: NSString?
            scanner.scanUpToCharacters(from: space, into: &dateNSString)
            scanner.scanUpToCharacters(from: space, into: &timeNSString)
            guard let dateString = dateNSString as String?,
                  let timeString = timeNSString as String?,
                  let date = StderrCapture.logDateFormatter.date(from: dateString + " " + timeString)
            else {
                return
            }
            var processId: NSString?
            scanner.scanUpToCharacters(from: space, into: &processId)

            if !scanner.isAtEnd {
                let currentIndex = scanner.string.index(scanner.string.startIndex, offsetBy: scanner.scanLocation + 1)
                message = String(scanner.string.suffix(from: currentIndex))
            }

            if let message = message {
                tracer.logString(string: message, date: date)
            }
        }
    }

    func logUIStep(tracer: DDTracer, string: String) {
        let scanner = Scanner(string: string)
        let space = CharacterSet.whitespaces
        var message: String?

        var timeFromStart = 0.0

        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, *) {
            _ = scanner.scanString("t =")
            timeFromStart = scanner.scanDouble() ?? 0.0
            _ = scanner.scanUpToCharacters(from: space)
            if !scanner.isAtEnd {
                let scannerLocIndex = scanner.string.index(after: scanner.currentIndex)
                message = String(scanner.string[scannerLocIndex...])
            }
        } else {
            scanner.scanString("t =", into: nil)
            scanner.scanDouble(&timeFromStart)
            scanner.scanUpToCharacters(from: space, into: nil)
            if !scanner.isAtEnd {
                let scannerLocIndex = scanner.string.index(scanner.string.startIndex, offsetBy: scanner.scanLocation + 1)
                message = String(scanner.string[scannerLocIndex...])
            }
        }

        if let message = message {
            tracer.logString(string: message, timeIntervalSinceSpanStart: timeFromStart)
        }
    }
}
