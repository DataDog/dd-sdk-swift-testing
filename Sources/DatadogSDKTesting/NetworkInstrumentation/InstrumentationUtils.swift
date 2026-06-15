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
        let capacity = Int(ObjectiveC.objc_getClassList(nil, 0))
        let allClasses = UnsafeMutablePointer<AnyClass>.allocate(capacity: capacity)
        defer { allClasses.deallocate() }
        let autoreleasingAllClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(allClasses)
        // `objc_getClassList` writes at most `capacity` entries but returns the
        // *total* number of registered classes, which can exceed `capacity` when
        // another thread registers classes between the two calls (frameworks load
        // concurrently during app/test launch). Iterating past `capacity` would
        // read uninitialized memory and hand back garbage pointers, which then
        // crash intermittently as "Attempt to use unknown class" / bad access the
        // moment they are dereferenced. Clamp to what we actually allocated.
        let written = Int(ObjectiveC.objc_getClassList(autoreleasingAllClasses, Int32(capacity)))
        let count = min(written, capacity)

        var classes = [AnyClass]()
        classes.reserveCapacity(count)
        for i in 0 ..< count {
            classes.append(allClasses[i])
        }
        return classes
    }

    /// Returns whether `cls` (or any of its superclasses) conforms to `proto`,
    /// using only ObjC runtime metadata. Unlike a Swift `is`/`as?` existential
    /// cast, this never sends a message to the class. It lets the delegate scan
    /// skip the expensive `class_copyMethodList` for the thousands of classes
    /// that don't adopt `URLSessionDelegate`.
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
