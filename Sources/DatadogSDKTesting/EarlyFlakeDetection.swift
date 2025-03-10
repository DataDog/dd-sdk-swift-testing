/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import EventsExporter

protocol EarlyFlakeDetectionService {
    var knownTests: KnownTests? { get }
    var slowTestRetries: TracerSettings.EFD.TimeTable { get }
    var faultySessionThreshold: Double { get }
    func start()
}

final class EarlyFlakeDetection: EarlyFlakeDetectionService {
    private var knownTestsService: KnownTestsService
    
    var knownTests: KnownTests? {
        knownTestsService.knownTests
    }
    
    var slowTestRetries: TracerSettings.EFD.TimeTable
    var faultySessionThreshold: Double
    
    init(knownTests: KnownTestsService,
         slowTestRetries: TracerSettings.EFD.TimeTable,
         faultySessionThreshold: Double
    ) {
        self.knownTestsService = knownTests
        self.slowTestRetries = slowTestRetries
        self.faultySessionThreshold = faultySessionThreshold
    }
    
    func start() {
        if knownTestsService.knownTests == nil {
            Log.print("EFD can't be enabled. Known Tests is empty")
        }
    }
}
