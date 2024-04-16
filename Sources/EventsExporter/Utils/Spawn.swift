/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import CDatadogSDKTesting

public enum Spawn {
    struct ExitCode: Swift.Error {
        let code: Int32
        let output: String?
    }
    
    public static func command(_ command: String) throws {
        let arguments = ["/bin/sh", "-c", command]
        let command = "/bin/sh"

        var pid: pid_t = 0
        let ret = arguments.withCStringsNilTerminatedArray { argv in
            dd_posix_spawn(&pid, command, nil, nil, argv, nil)
        }
        try _wait(spawn: ret, pid: pid)
    }

    public static func commandWithResult(_ command: String) throws -> String {
        let tempOutput = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempOutput) }
        
        do {
            try commandToFile(command, outputPath: tempOutput.path)
            return (try? String(contentsOf: tempOutput)) ?? ""
        } catch let e as ExitCode {
            throw ExitCode(code: e.code, output: (try? String(contentsOf: tempOutput)) ?? e.output)
        }
    }

    public static func commandToFile(_ command: String, outputPath: String) throws {
        let arguments = ["/bin/sh", "-c", command]
        let command = "/bin/sh"

        var childActions: posix_spawn_file_actions_t?
        dd_posix_spawn_file_actions_init(&childActions)
        dd_posix_spawn_file_actions_addopen(&childActions, 1, outputPath, O_WRONLY | O_CREAT | O_TRUNC, 0444)
        dd_posix_spawn_file_actions_adddup2(&childActions, 1, 2)
        defer { dd_posix_spawn_file_actions_destroy(&childActions) }
        
        var pid: pid_t = 0
        let ret = arguments.withCStringsNilTerminatedArray { argv in
            dd_posix_spawn(&pid, command, &childActions, nil, argv, nil)
        }
        try _wait(spawn: ret, pid: pid)
    }
    
    private static func _wait(spawn: Int32, pid: pid_t) throws {
        guard spawn == 0 else {
            throw POSIXError(POSIXError.Code(rawValue: spawn) ?? .ELAST)
        }
        let status = dd_wait_for_process(pid)
        guard !status.is_error else {
            throw POSIXError(POSIXError.Code(rawValue: status.error) ?? .ELAST)
        }
        guard status.status.si_code == CLD_EXITED && status.status.si_status == 0 else {
            throw ExitCode(code: status.status.si_status, output: nil)
        }
    }
}
