/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
@_implementationOnly import XCTest

extension XCTestCase {
    var ddRealTest: XCTestCase { self }
    
    var testId: (suite: String, test: String) {
        let parts = name.trimmingCharacters(in: Self._trimmedCharacters).split(separator: " ")
        assert(parts.count == 2, "unknown test name format \(name)")
        return (String(parts[0]), String(parts[1]))
    }
    
    private static let _trimmedCharacters: CharacterSet = CharacterSet(charactersIn: "-[]")
}

#if canImport(ObjectiveC)
extension XCTestCase {
    func toSkipped() -> XCTestCase {
        type(of: self)._swizzleIfNeeded()
        self._skipped = true
        self.continueAfterFailure = false
        return self
    }
    
    @objc func swizzled_setUp(completion: @escaping (Error?) -> Void) {
        _skipped ? completion(XCTSkip("ITR")) : swizzled_setUp(completion: completion)
    }
    
    @objc func swizzled_setUpWithError() throws {
        guard !_skipped else { throw XCTSkip("ITR") }
        try swizzled_setUpWithError()
    }
    
    @objc func swizzled_setUp_() {
        if !_skipped { swizzled_setUp_() }
    }
        
    @objc func swizzled_tearDown_() {
        if !_skipped { swizzled_tearDown_() }
    }
    
    @objc func swizzled_tearDownWithError() throws {
        if !_skipped { try swizzled_tearDownWithError() }
    }
    
    @objc func swizzled_tearDown(completion: @escaping (Error?) -> Void) {
        _skipped ? completion(nil) : swizzled_tearDown(completion: completion)
    }
    
    private static func _swizzleIfNeeded() {
        guard self != XCTestCase.self else { return } // Run only for child classes
        
        // Synchronize
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        
        // Check that we are not swizzled yet
        guard !_swizzled else { return }
        
        // Swizzle all selectors
        for (original, swizzled) in _swizzledSelectors {
            // Get method implementation from XCTestCase
            guard let swizzledMethod = class_getInstanceMethod(XCTestCase.self, swizzled) else { return }
            // Try to add it to the class as original method
            if _addMethod(swizzledMethod, selector: original) {
                // we haven't had implementation in our class. Get orignal implementation from the superclass
                guard let parentMethod = class_getInstanceMethod(class_getSuperclass(self), original) else { return }
                // save it as swizzled method for proper chaining
                guard _addMethod(parentMethod, selector: swizzled) else { return }
            } else {
                // we have this method in our class.
                guard let originalMethod = class_getInstanceMethod(self, original) else { return }
                // Add swizzle method to our class, so we will not override parent one
                guard _addMethod(swizzledMethod) else { return }
                // get added implementation
                guard let addedMethod = class_getInstanceMethod(self, swizzled) else { return }
                // exhange implementations
                method_exchangeImplementations(originalMethod, addedMethod)
            }
        }
        
        // Done
        _swizzled = true
    }
    
    private static func _addMethod(_ method: Method, selector: Selector? = nil) -> Bool {
        class_addMethod(self, selector ?? method_getName(method), method_getImplementation(method), method_getTypeEncoding(method))
    }
    
    private var _skipped: Bool {
        get {
            objc_getAssociatedObject(self, &XCTestCase._swizzled_key)
                .map { ($0 as! NSNumber).boolValue } ?? false
        }
        set {
            objc_setAssociatedObject(self, &XCTestCase._swizzled_key,
                                     NSNumber(value: newValue),
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private static var _swizzled: Bool {
        get {
            objc_getAssociatedObject(self, &_swizzled_key)
                .map { ($0 as! NSNumber).boolValue } ?? false
        }
        set {
            objc_setAssociatedObject(self, &_swizzled_key,
                                     NSNumber(value: newValue),
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private static let _swizzledSelectors: [Selector: Selector] = [
        #selector(setUp(completion:)): #selector(swizzled_setUp(completion:)),
        #selector(setUpWithError): #selector(swizzled_setUpWithError),
        #selector(setUp): #selector(swizzled_setUp_),
        #selector(tearDown(completion:)): #selector(swizzled_tearDown(completion:)),
        #selector(tearDownWithError): #selector(swizzled_tearDownWithError),
        #selector(tearDown): #selector(swizzled_tearDown_)
    ]
    
    private static var _swizzled_key: Int = 0
}
#else
final class SkippedTest: XCTestCase {
   private var _test: XCTestCase! = nil

   override var name: String { _test.name }
   override var testCaseCount: Int { _test.testCaseCount }
   override var testRunClass: AnyClass? { _test.testRunClass }

   override func setUpWithError() throws {
       throw XCTSkip("ITR")
   }

   convenience init(for test: XCTestCase) {
       self.init(name: "") {_ in}
       self.continueAfterFailure = false
       self._test = test
   }

   override var ddRealTest: XCTestCase { _test }
}

extension XCTestCase {
    func toSkipped() -> XCTestCase { SkippedTest(for: self) }
}
#endif
