/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

#if os(tvOS)
/// posix_spawn is not accessible in tvOS
#else

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
        let ret = posix_spawn(&pid, command, nil, nil, args, env)
        guard ret == 0 else {
            return
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return
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
        posix_spawn_file_actions_init(&childActions)
        posix_spawn_file_actions_adddup2(&childActions, outputPipe[1], 1)
        posix_spawn_file_actions_adddup2(&childActions, outputPipe[1], 2)
        posix_spawn_file_actions_addclose(&childActions, outputPipe[0])
        posix_spawn_file_actions_addclose(&childActions, outputPipe[1])

        var pid: pid_t = 0

        let ret = posix_spawn(&pid, command, &childActions, nil, args, env)
        guard ret == 0 else {
            return ""
        }

        var status: Int32 = 0
        waitpid(pid, &status, 0)

        close(outputPipe[1])
        var output = ""
        let bufferSize: size_t = 1024 * 8
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
        print(output)
        return output
    }
}
#endif
