/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

/// Interface for date provider used for files orchestration.
public protocol DateProvider {
    func currentDate() -> Date
}

public struct SystemDateProvider: DateProvider {
    public init() {}
    
    @inlinable
    public func currentDate() -> Date { return Date() }
}
