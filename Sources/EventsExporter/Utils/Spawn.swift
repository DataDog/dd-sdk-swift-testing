/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import CDatadogSDKTesting

public enum Spawn {
    enum RunError: Error, CustomDebugStringConvertible {
        case code(Int32, String?)
        case signal(Int32, String?)
        
        var debugDescription: String {
            let prefix: String
            let output: String?
            switch self {
            case .code(let c, let o):
                prefix = "Code: \(c)"
                output = o
            case .signal(let s, let o):
                prefix = "Signal: \(s)"
                output = o
            }
            return "RunError::\(prefix)" + (output.map {": \($0)"} ?? "")
        }
        
        func with(output: String?) -> Self {
            switch self {
            case .code(let c, let o): return .code(c, output ?? o)
            case .signal(let s, let o): return .signal(s, output ?? o)
            }
        }
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
        } catch let e as RunError {
            throw e.with(output: (try? String(contentsOf: tempOutput)))
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
            throw status.status.si_code == CLD_EXITED
                ? RunError.code(status.status.si_status, "")
                : RunError.signal(status.status.si_status, "")
        }
    }
}


extension Spawn {
    public static func tryCommandWithResult(_ command: String, log: any Logger, debug: Bool = true) -> String? {
        do {
            return try Spawn.commandWithResult(command)
        } catch {
            if debug {
                Log.debug("Command \(command) failed with error \(error)")
            } else {
                Log.print("Command \(command) failed with error \(error)")
            }
            return nil
        }
    }
}
