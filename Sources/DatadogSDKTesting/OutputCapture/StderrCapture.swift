/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

enum StderrCapture {
    static var isCapturing = false
    static private let inputPipe = Pipe()
    static private let outputPipe = Pipe()
    static private var originalDescriptor = FileHandle.standardError.fileDescriptor

    static var logDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    static func startCapturing() {
        guard !isCapturing else {
            return
        }
        inputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if let string = String(data: data, encoding: String.Encoding.utf8) {
                StderrCapture.stderrMessage(string: string)
            }

            // Write input back to stderr
            outputPipe.fileHandleForWriting.write(data)
        }
        setvbuf(stderr, nil, _IONBF, 0)

        // Copy STDERR file descriptor to outputPipe for writing strings back to STDERR
        dup2(FileHandle.standardError.fileDescriptor, outputPipe.fileHandleForWriting.fileDescriptor)

        // Intercept STDERR with inputPipe
        dup2(inputPipe.fileHandleForWriting.fileDescriptor, FileHandle.standardError.fileDescriptor)

        isCapturing = true
    }

    static func syncData() {
        guard isCapturing, inputPipe.fileHandleForReading.isReadable else {
            return
        }

        var synchronizeData: DispatchWorkItem!
        synchronizeData = DispatchWorkItem(block: {
            let auxData = self.inputPipe.fileHandleForReading.availableData
            if !auxData.isEmpty,
               let string = String(data: auxData, encoding: String.Encoding.utf8)
            {
                StderrCapture.stderrMessage(string: string)
            }
        })
        DispatchQueue.global().async {
            synchronizeData.perform()
        }
        _ = synchronizeData.wait(timeout: .now() + .milliseconds(10))
    }

    static func stopCapturing() {
        guard isCapturing else {
            return
        }
        isCapturing = false
        freopen("/dev/stderr", "a", stderr)
    }

    static func stderrMessage(string: String) {
        guard DDTracer.activeSpan != nil ||
            DDTestMonitor.tracer.isBinaryUnderUITesting
        else {
            return
        }

        string.enumerateLines { line, _ in
            if line.prefix(8) == "    t = " {
                self.logUIStep(string: line)
            } else {
                self.logTimedErrOutput(string: line)
            }
        }
    }

    static func logTimedErrOutput(string: String) {
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
                DDTestMonitor.tracer.logString(string: message, date: date)
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
                DDTestMonitor.tracer.logString(string: message, date: date)
            }
        }
    }

    static func logUIStep(string: String) {
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
            DDTestMonitor.tracer.logString(string: message, timeIntervalSinceSpanStart: timeFromStart)
        }
    }
}
