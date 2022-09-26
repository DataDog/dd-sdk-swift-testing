/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

public class SanitizerHelper: NSObject {
    static let santizerQueue = DispatchQueue(label: "civisibility.sanitizerQueue")
    override init() {}

    private static var sanitizerInfo = ""

    @objc
    public static func logSanitizerMessage(_ message: NSString) {
        santizerQueue.async {
            sanitizerInfo += String(message)
        }
    }

    public static func getSaniziterInfo() -> String? {
        var sanitizerInfoCopy = ""
        santizerQueue.sync {
            sanitizerInfoCopy = sanitizerInfo
        }
        return sanitizerInfoCopy.isEmpty ? nil : sanitizerInfoCopy
    }

    public static func setSaniziterInfo(info: String?) {
        guard let info = info else { return }
        santizerQueue.sync {
            sanitizerInfo = info
        }
    }
}
