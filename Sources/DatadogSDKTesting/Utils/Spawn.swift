/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2021 Datadog, Inc.
 */

import Foundation

enum Spawn {
    static func command(_ command: String, environment: [String: String]? = nil) {
        let arguments = ["/bin/sh", "-c", command]
        let command = "/bin/sh"
        let args = arguments.map { strdup($0) } + [nil]

        var env: [UnsafeMutablePointer<CChar>?]?
        if let environment = environment {
            env = environment.map {
                "\($0.0)=\($0.1)".withCString(strdup)
            } + [nil]
        }

        var pid: pid_t = 0
        let ret = _stdlib_posix_spawn(&pid, command, nil, nil, args, env)
        guard ret == 0 else {
            return
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }

    static func commandWithResult(_ command: String, environment: [String: String]? = nil) -> String {
        let arguments = ["/bin/sh", "-c", command]
        let command = "/bin/sh"
        let args = arguments.map { strdup($0) } + [nil]

        var env: [UnsafeMutablePointer<CChar>?]?
        if let environment = environment {
            env = environment.map {
                "\($0.0)=\($0.1)".withCString(strdup)
            } + [nil]
        }

        var outputPipe: [Int32] = [-1, -1]
        pipe(&outputPipe)
        var childActions: posix_spawn_file_actions_t?
        _stdlib_posix_spawn_file_actions_init(&childActions)
        _stdlib_posix_spawn_file_actions_adddup2(&childActions, outputPipe[1], 1)
        _stdlib_posix_spawn_file_actions_adddup2(&childActions, outputPipe[1], 2)
        _stdlib_posix_spawn_file_actions_addclose(&childActions, outputPipe[0])
        _stdlib_posix_spawn_file_actions_addclose(&childActions, outputPipe[1])

        var pid: pid_t = 0

        let ret = _stdlib_posix_spawn(&pid, command, &childActions, nil, args, env)
        guard ret == 0 else {
            return ""
        }

        var status: Int32 = 0
        waitpid(pid, &status, 0)

        close(outputPipe[1])
        var output = ""
        let bufferSize: size_t = 1024 * 64
//#if swift(>=5.6)
//        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: bufferSize) { dynamicBuffer in
//            while true {
//                memset(dynamicBuffer.baseAddress!, 0, bufferSize)
//                let amtRead = read(outputPipe[0], dynamicBuffer.baseAddress!, bufferSize - 1)
//                output += String(cString: dynamicBuffer.baseAddress!)
//                if amtRead < bufferSize - 1 {
//                    break
//                }
//            }
//        }
//#else
        let dynamicBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        while true {
            memset(dynamicBuffer, 0, bufferSize)
            let amtRead = read(outputPipe[0], dynamicBuffer, bufferSize - 1)
            output += String(cString: dynamicBuffer)
            if amtRead < bufferSize - 1 {
                break
            }
        }
        dynamicBuffer.deallocate()
//#endif
        _stdlib_posix_spawn_file_actions_destroy(&childActions)
        return output
    }

    static func commandToFile(_ command: String, outputPath: String, environment: [String: String]? = nil) {
        let arguments = ["/bin/sh", "-c", command]
        let command = "/bin/sh"
        let args = arguments.map { strdup($0) } + [nil]

        var env: [UnsafeMutablePointer<CChar>?]?
        if let environment = environment {
            env = environment.map {
                "\($0.0)=\($0.1)".withCString(strdup)
            } + [nil]
        }

        var childActions: posix_spawn_file_actions_t?
        _stdlib_posix_spawn_file_actions_init(&childActions)
        _stdlib_posix_spawn_file_actions_addopen(&childActions, 1, outputPath, O_RDWR | O_CREAT | O_TRUNC, 0644)
        _stdlib_posix_spawn_file_actions_adddup2(&childActions, 1, 2)
        var pid: pid_t = 0

        let ret = _stdlib_posix_spawn(&pid, command, &childActions, nil, args, env)
        guard ret == 0 else {
            return
        }

        var status: Int32 = 0
        waitpid(pid, &status, 0)
        _stdlib_posix_spawn_file_actions_destroy(&childActions)
    }
}

typealias _stdlib_posix_spawn_file_actions_t = posix_spawn_file_actions_t?

@_silgen_name("_stdlib_posix_spawn_file_actions_init")
@discardableResult internal func _stdlib_posix_spawn_file_actions_init(
    _ file_actions: UnsafeMutablePointer<_stdlib_posix_spawn_file_actions_t>
) -> CInt

@_silgen_name("_stdlib_posix_spawn_file_actions_destroy")
@discardableResult internal func _stdlib_posix_spawn_file_actions_destroy(
    _ file_actions: UnsafeMutablePointer<_stdlib_posix_spawn_file_actions_t>
) -> CInt

@_silgen_name("_stdlib_posix_spawn_file_actions_addclose")
@discardableResult internal func _stdlib_posix_spawn_file_actions_addclose(
    _ file_actions: UnsafeMutablePointer<_stdlib_posix_spawn_file_actions_t>,
    _ filedes: CInt) -> CInt

@_silgen_name("_stdlib_posix_spawn_file_actions_adddup2")
@discardableResult internal func _stdlib_posix_spawn_file_actions_adddup2(
    _ file_actions: UnsafeMutablePointer<_stdlib_posix_spawn_file_actions_t>,
    _ filedes: CInt,
    _ newfiledes: CInt) -> CInt

@_silgen_name("_stdlib_posix_spawn_file_actions_addopen")
@discardableResult internal func _stdlib_posix_spawn_file_actions_addopen(
    _ file_actions: UnsafeMutablePointer<_stdlib_posix_spawn_file_actions_t>,
    _ filedes: CInt,
    _ path: UnsafePointer<CChar>,
    _ oflag: Int32,
    _ mode: mode_t) -> CInt

@_silgen_name("_stdlib_posix_spawn")
internal func _stdlib_posix_spawn(
    _ pid: UnsafeMutablePointer<pid_t>?,
    _ file: UnsafePointer<Int8>,
    _ file_actions: UnsafePointer<_stdlib_posix_spawn_file_actions_t>?,
    _ attrp: UnsafePointer<posix_spawnattr_t>?,
    _ argv: UnsafePointer<UnsafeMutablePointer<Int8>?>,
    _ envp: UnsafePointer<UnsafeMutablePointer<Int8>?>?) -> CInt
