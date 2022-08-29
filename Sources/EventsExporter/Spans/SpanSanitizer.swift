/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

/// Sanitizes `SpanEvent` representation received from the user, so it can match Datadog APM constraints.
internal struct SpanSanitizer {
    private let attributesSanitizer = AttributesSanitizer(featureName: "Span")

    func sanitize(span: DDSpan) -> DDSpan {
        // Sanitize attribute names
        var sanitizedTags = attributesSanitizer.sanitizeKeys(for: span.tags)

        var sanitizedSpan = span
        sanitizedSpan.tags = sanitizedTags
        return sanitizedSpan
    }
}
