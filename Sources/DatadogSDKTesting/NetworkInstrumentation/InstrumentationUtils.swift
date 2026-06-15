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
        // `objc_getClassList(buf, n)` fills at most `n` slots but returns the
        // *total* number of registered classes. Other threads register classes
        // concurrently while frameworks load during app/test launch, so that total
        // can exceed the buffer we sized from an earlier call. Reading past the
        // buffer yields uninitialized garbage pointers, which crash intermittently
        // as "Attempt to use unknown class" / bad access the moment they are
        // dereferenced. Re-query and grow until the returned count fits the buffer:
        // that way we never read past it and still capture every class. The small
        // headroom lets it settle in one retry under typical concurrent loading.
        var capacity: Int32 = ObjectiveC.objc_getClassList(nil, 0) + 32
        while true {
            let buffer = UnsafeMutableBufferPointer<AnyClass>.allocate(capacity: Int(capacity))
            defer { buffer.deallocate() }
            let autoreleasing = AutoreleasingUnsafeMutablePointer<AnyClass>(buffer.baseAddress)
            let written = ObjectiveC.objc_getClassList(autoreleasing, capacity)
            if written <= capacity {
                // We got all the classes. Convert to array and return
                return Array(buffer.prefix(upTo: Int(written)))
            }
            // More classes appeared than fit; grow to the new total and retry.
            capacity = written + 32
        }
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
