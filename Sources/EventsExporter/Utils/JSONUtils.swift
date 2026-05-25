/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

protocol JSONable {
    var jsonData: Data? { get }
    var jsonString: String { get }
}

extension JSONable where Self: Encodable {
    var jsonData: Data? {
        return try? JSONEncoder.apiEncoder.encode(self)
    }

    var jsonString: String {
        guard let data = self.jsonData else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
