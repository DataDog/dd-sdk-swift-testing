/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

final class SkippedTest: XCTestCase {
    private var _test: XCTestCase! = nil
    
    override var name: String { _test.name }
    override var testCaseCount: Int { _test.testCaseCount }
    override var testRunClass: AnyClass? { _test.testRunClass }
    
    override func setUpWithError() throws {
        throw XCTSkip("ITR")
    }
    
    convenience init(for test: XCTestCase) {
        self.init(selector: #selector(Self._empty))
        self._test = test
    }
    
    @objc func _empty() {}
}
