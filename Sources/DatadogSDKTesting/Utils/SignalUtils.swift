/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

struct SignalUtils {
    static func descriptionForSignalName(signalName: String) -> String {
        let signalNames = Mirror(reflecting: sys_signame).children.map { $0.value as! UnsafePointer<Int8> }.map { String(cString: $0).uppercased() }
        let signalDescription = Mirror(reflecting: sys_siglist).children.map { $0.value as! UnsafePointer<Int8> }.map { String(cString: $0) }
        if let index = signalNames.firstIndex(where: { signalName == ("SIG" + $0) }) {
            return signalDescription[index]
        }
        return ""
    }
}
