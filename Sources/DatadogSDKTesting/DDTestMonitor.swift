/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import DatadogExporter

internal class DDTestMonitor {
    static var instance: DDTestMonitor?
    
    let tracer: DDTracer
    var testObserver: DDTestObserver
    var networkInstrumentation: NetworkAutoInstrumentation?
    
    init() {
        tracer = DDTracer()
        testObserver = DDTestObserver(tracer: tracer)
        startNetworkAutoInstrumentation()
    }
    
    func startNetworkAutoInstrumentation() {
        let urlFilter = URLFilter(excludedURLs: tracer.endpointURLs())
        networkInstrumentation = NetworkAutoInstrumentation(urlFilter: urlFilter)
    }
}
