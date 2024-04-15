/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

class SanitizerHelper: NSObject {
    static let santizerQueue = DispatchQueue(label: "civisibility.sanitizerQueue", attributes: .concurrent)
    override init() {}

    private static var sanitizerInfo = ""

    static func logSanitizerMessage(_ message: String) {
        santizerQueue.sync(flags: .barrier) {
            sanitizerInfo += message
        }
    }

    static func getSaniziterInfo() -> String? {
        var sanitizerInfoCopy = ""
        santizerQueue.sync {
            sanitizerInfoCopy = sanitizerInfo
        }
        return sanitizerInfoCopy.isEmpty ? nil : sanitizerInfoCopy
    }

    static func setSaniziterInfo(info: String?) {
        guard let info = info else { return }
        santizerQueue.sync(flags: .barrier) {
            sanitizerInfo = info
        }
    }
}

/// This is the method that sanitizers call to print messages, we capture it and store with our Test module. This is called asynchornously.
@_cdecl("__sanitizer_on_print")
func __sanitizer_on_print(message: UnsafePointer<CChar>!) {
    SanitizerHelper.logSanitizerMessage(String(cString: message))
}
