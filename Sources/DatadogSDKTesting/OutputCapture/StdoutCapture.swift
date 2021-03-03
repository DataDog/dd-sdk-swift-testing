/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

class StdoutCapture {
    static var originalStdoutWriter: ((UnsafeMutableRawPointer?, UnsafePointer<Int8>?, Int32) -> Int32)?
    static var stdoutBuffer = ""
    weak static var tracer: DDTracer?

    static func startCapturing(tracer: DDTracer) {
        StdoutCapture.tracer = tracer
        if StdoutCapture.originalStdoutWriter == nil {
            StdoutCapture.originalStdoutWriter = stdout.pointee._write
        }
        stdout.pointee._write = capturedStdoutWriter
    }

    static func stopCapturing() {
        stdout.pointee._write = standardStdoutWriter
    }

    /// This is the logging code, we are buffering the output because sometimes single characters can appear
    static func logStdOutMessage(_ string: String) {
        stdoutBuffer += string
        let newlineChar = CharacterSet.newlines
        if let lastCharacter = self.stdoutBuffer.unicodeScalars.last,
           newlineChar.contains(lastCharacter)
        {
            if self.stdoutBuffer.trimmingCharacters(in: newlineChar).count > 0 {
                tracer?.logString(string: self.stdoutBuffer)
            }
            self.stdoutBuffer = ""
        }
    }
}

/// This is the code that runs original stodut code, and captures the buffer for the logging
func capturedStdoutWriter(fd: UnsafeMutableRawPointer?, buffer: UnsafePointer<Int8>?, size: Int32) -> Int32 {
    _ = StdoutCapture.originalStdoutWriter?(fd, buffer, size)
    if let buffer = buffer {
        let string = String(cString: buffer)
        if string.count > 0 {
            StdoutCapture.logStdOutMessage(string)
        }
    }
    return size
}

/// We need to redirect to the original writer through this function because swift doesn't allow to reassign directly
func standardStdoutWriter(fd: UnsafeMutableRawPointer?, buffer: UnsafePointer<Int8>?, size: Int32) -> Int32 {
    return StdoutCapture.originalStdoutWriter?(fd, buffer, size) ?? size
}
