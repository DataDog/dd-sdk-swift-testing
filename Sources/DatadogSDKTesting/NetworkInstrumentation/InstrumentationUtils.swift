/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 *
 * This file includes software developed by The OpenTelemetry Authors, https://opentelemetry.io and altered by Datadog.
 * Use of this source code is governed by Apache License 2.0 license: https://github.com/open-telemetry/opentelemetry-swift/blob/main/LICENSE
 */

import Foundation

enum InstrumentationUtils {
    static func objc_getClassList() -> [AnyClass] {
        let expectedClassCount = ObjectiveC.objc_getClassList(nil, 0)
        let allClasses = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(expectedClassCount))
        let autoreleasingAllClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(allClasses)
        let actualClassCount: Int32 = ObjectiveC.objc_getClassList(autoreleasingAllClasses, expectedClassCount)
        
        var classes = [AnyClass]()
        for i in 0 ..< actualClassCount {
            classes.append(allClasses[Int(i)])
        }
        allClasses.deallocate()
        return classes
    }
    
    /// Returns the registered Objective-C classes that are safe to introspect
    /// with `class_copyMethodList` / method swizzling.
    ///
    /// `objc_getClassList` can return classes whose superclass chain references a
    /// class that is registered as a stub but never realized — for example
    /// weak-linked classes from frameworks that aren't loaded, or the
    /// relative-method-list "stub" classes that newer runtimes emit. Realizing
    /// such a class, which `class_copyMethodList` does implicitly, makes the
    /// runtime log "Attempt to use unknown class %p." and abort. We avoid that by
    /// keeping only the classes whose entire superclass chain is itself present in
    /// the class list. Reading the superclass pointer with `class_getSuperclass`
    /// does not realize the class, so the check itself is safe.
    static func objc_getSafeClassList() -> [AnyClass] {
        let allClasses = objc_getClassList()
        let known = Set(allClasses.map { ObjectIdentifier($0) })

        return allClasses.filter { cls in
            var current: AnyClass? = cls
            while let c = current {
                guard known.contains(ObjectIdentifier(c)) else { return false }
                current = class_getSuperclass(c)
            }
            return true
        }
    }
    
    /// Returns whether `cls` (or any of its superclasses) conforms to `proto`,
    /// using only ObjC runtime metadata. Unlike a Swift `is`/`as?` existential
    /// cast, this never sends a message to the class, so it is safe to run across
    /// every class from `objc_getClassList()` — including pathological internal
    /// classes (`__NSGenericDeallocHandler`, `__NSAtom`, `__NSMessageBuilder`, …)
    /// that abort with an `NSForwarding` error when messaged.
    static func classConforms(_ cls: AnyClass, to proto: Protocol) -> Bool {
        var current: AnyClass? = cls
        while let c = current {
            if class_conformsToProtocol(c, proto) { return true }
            current = class_getSuperclass(c)
        }
        return false
    }

    static func instanceRespondsAndImplements(cls: AnyClass, selector: Selector) -> Bool {
        var implements = false
        if cls.instancesRespond(to: selector) {
            var methodCount: UInt32 = 0
            guard let methodList = class_copyMethodList(cls, &methodCount) else {
                return implements
            }
            defer { free(methodList) }
            if methodCount > 0 {
                enumerateCArray(array: methodList, count: methodCount) { _, m in
                    let sel = method_getName(m)
                    if sel == selector {
                        implements = true
                        return
                    }
                }
            }
        }
        return implements
    }
    
    private static func enumerateCArray<T>(array: UnsafePointer<T>, count: UInt32, f: (UInt32, T) -> Void) {
        var ptr = array
        for i in 0 ..< count {
            f(i, ptr.pointee)
            ptr = ptr.successor()
        }
    }
}
