/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
internal import OpenTelemetrySdk

final class NoopSpanExporter: SpanExporter {
    init() {}

    func export(spans: [SpanData], explicitTimeout: TimeInterval? = nil) -> SpanExporterResultCode {
        .success
    }

    func flush(explicitTimeout: TimeInterval? = nil) -> SpanExporterResultCode {
        .success
    }

    func shutdown(explicitTimeout: TimeInterval? = nil) {}
}
