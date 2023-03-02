/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation

public enum Spawn {
    public static func command(_ command: String) {
        let arguments = ["/bin/sh", "-c", command]
        let command = "/bin/sh"

        var pid: pid_t = 0

        let ret = withArrayOfCStrings(arguments) { argv in
            _stdlib_posix_spawn(&pid, command, nil, nil, argv, nil)
        }

        guard ret == 0 else {
            return
        }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }

    public static func commandWithResult(_ command: String) -> String {
        let arguments = ["/bin/sh", "-c", command]
        let command = "/bin/sh"

        let tempOutput = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: tempOutput)
        }

        var childActions: posix_spawn_file_actions_t?
        _stdlib_posix_spawn_file_actions_init(&childActions)
        _stdlib_posix_spawn_file_actions_addopen(&childActions, 1, tempOutput.path, O_WRONLY | O_CREAT | O_TRUNC, 0444)
        _stdlib_posix_spawn_file_actions_adddup2(&childActions, 1, 2)
        defer { _stdlib_posix_spawn_file_actions_destroy(&childActions) }
        var pid: pid_t = 0

        let ret = withArrayOfCStrings(arguments) { argv in
            _stdlib_posix_spawn(&pid, command, &childActions, nil, argv, nil)
        }

        guard ret == 0 else {
            return ""
        }

        var status: Int32 = 0
        waitpid(pid, &status, 0)

        return (try? String(contentsOf: tempOutput)) ?? ""
    }

    public static func commandToFile(_ command: String, outputPath: String) {
        let arguments = ["/bin/sh", "-c", command]
        let command = "/bin/sh"

        var childActions: posix_spawn_file_actions_t?
        _stdlib_posix_spawn_file_actions_init(&childActions)
        _stdlib_posix_spawn_file_actions_addopen(&childActions, 1, outputPath, O_WRONLY | O_CREAT | O_TRUNC, 0444)
        _stdlib_posix_spawn_file_actions_adddup2(&childActions, 1, 2)
        defer { _stdlib_posix_spawn_file_actions_destroy(&childActions) }
        var pid: pid_t = 0

        let ret = withArrayOfCStrings(arguments) { argv in
            _stdlib_posix_spawn(&pid, command, &childActions, nil, argv, nil)
        }

        guard ret == 0 else {
            return
        }

        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }
}

private func scan<
    S: Sequence, U
>(_ seq: S, _ initial: U, _ combine: (U, S.Element) -> U) -> [U] {
    var result: [U] = []
    result.reserveCapacity(seq.underestimatedCount)
    var runningResult = initial
    for element in seq {
        runningResult = combine(runningResult, element)
        result.append(runningResult)
    }
    return result
}

private func withArrayOfCStrings<R>(
    _ args: [String],
    _ body: ([UnsafeMutablePointer<CChar>?]) -> R) -> R
{
    let argsCounts = Array(args.map { $0.utf8.count + 1 })
    let argsOffsets = [0] + scan(argsCounts, 0, +)
    let argsBufferSize = argsOffsets.last!

    var argsBuffer: [UInt8] = []
    argsBuffer.reserveCapacity(argsBufferSize)
    for arg in args {
        argsBuffer.append(contentsOf: arg.utf8)
        argsBuffer.append(0)
    }

    return argsBuffer.withUnsafeMutableBufferPointer {
        argsBuffer in
        let ptr = UnsafeMutableRawPointer(argsBuffer.baseAddress!).bindMemory(
            to: CChar.self, capacity: argsBuffer.count)
        var cStrings: [UnsafeMutablePointer<CChar>?] = argsOffsets.map { ptr + $0 }
        cStrings[cStrings.count - 1] = nil
        return body(cStrings)
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
