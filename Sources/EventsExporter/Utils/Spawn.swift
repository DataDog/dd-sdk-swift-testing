/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-Present Datadog, Inc.
 */

import Foundation
import CDatadogSDKTesting

public enum Spawn {
    enum RunError: Error, CustomDebugStringConvertible {
        case code(Int32, String, String)
        case signal(Int32, String, String)
        
        var debugDescription: String {
            let prefix: String
            let output: String
            let error: String
            switch self {
            case .code(let c, let o, let e):
                prefix = "Code: \(c)"
                output = o
                error = e
            case .signal(let s, let o, let e):
                prefix = "Signal: \(s)"
                output = o
                error = e
            }
            return "RunError::\(prefix)\nSTDOUT: \(output)\nSTDERR: \(error)"
        }
    }
    
    private enum RunErrorCode: Error {
        case code(Int32)
        case signal(Int32)
        
        func with(output: String, error: String) -> RunError {
            switch self {
            case .code(let c): return .code(c, output, error)
            case .signal(let s): return .signal(s, output, error)
            }
        }
    }
    
    @discardableResult
    public static func command(
        _ command: String, output: URL? = nil, error: URL? = nil
    ) throws -> (output: String?, error: String?) {
        let arguments = ["/bin/sh", "-c", command]
        let command = "/bin/sh"
        
        var childActions: posix_spawn_file_actions_t?
        dd_posix_spawn_file_actions_init(&childActions)
        
        let outFile: URL?
        let errFile: URL?
        defer {
            outFile.map { try? FileManager.default.removeItem(at: $0) }
            errFile.map { try? FileManager.default.removeItem(at: $0) }
        }
        
        if let output = output {
            outFile = nil
            dd_posix_spawn_file_actions_addopen(&childActions, 1, output.path, O_WRONLY | O_CREAT | O_TRUNC, 0444)
        } else {
            outFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".out")
            dd_posix_spawn_file_actions_addopen(&childActions, 1, outFile!.path, O_WRONLY | O_CREAT | O_TRUNC, 0444)
        }
        
        if let error = error {
            errFile = nil
            if error == output {
                dd_posix_spawn_file_actions_adddup2(&childActions, 1, 2)
            } else {
                dd_posix_spawn_file_actions_addopen(&childActions, 2, error.path, O_WRONLY | O_CREAT | O_TRUNC, 0444)
            }
        } else {
            errFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".err")
            dd_posix_spawn_file_actions_addopen(&childActions, 2, errFile!.path, O_WRONLY | O_CREAT | O_TRUNC, 0444)
        }
        
        var pid: pid_t = 0
        let ret = arguments.withCStringsNilTerminatedArray { argv in
            dd_posix_spawn(&pid, command, &childActions, nil, argv, nil)
        }
        
        dd_posix_spawn_file_actions_destroy(&childActions)
        
        do {
            try _wait(spawn: ret, pid: pid)
        } catch let e as RunErrorCode {
            throw try e.with(output: outFile.map { try String(contentsOf: $0) } ?? output!.path,
                             error: errFile.map { try String(contentsOf: $0) } ?? error!.path)
        }
        
        return try (outFile.map { try String(contentsOf: $0) },
                    errFile.map { try String(contentsOf: $0) })
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
                ? RunErrorCode.code(status.status.si_status)
                : RunErrorCode.signal(status.status.si_status)
        }
    }
}


extension Spawn {
    public static func combined(_ command: String) throws -> String {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            try combined(command, file: file)
        } catch let e as RunError {
            let data = try String(contentsOf: file)
            switch e {
            case .signal(let s, _, _): throw RunError.signal(s, data, data)
            case .code(let c, _, _): throw RunError.code(c, data, data)
            }
        }
        return try String(contentsOf: file).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @inlinable
    public static func combined(_ command: String, file: URL) throws {
        try Self.command(command, output: file, error: file)
    }
    
    public static func combined(try command: String, log: any Logger, debug: Bool = true) -> String? {
        do {
            return try combined(command)
        } catch {
            if debug {
                Log.debug("Command \(command) failed with error \(error)")
            } else {
                Log.print("Command \(command) failed with error \(error)")
            }
            return nil
        }
    }
    
    public static func output(_ command: String) throws -> String {
        try Self.command(command).output!.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public static func output(_ command: String, file: URL) throws {
        try Self.command(command, output: file)
    }
    
    public static func output(try command: String, log: any Logger, debug: Bool = true) -> String? {
        do {
            return try output(command)
        } catch {
            if debug {
                Log.debug("Command \(command) failed with error \(error)")
            } else {
                Log.print("Command \(command) failed with error \(error)")
            }
            return nil
        }
    }
    
    public static func command(
        try command: String, log: any Logger, debug: Bool = true
    ) -> (output: String, error: String)? {
        do {
            let (out, err) = try Self.command(command)
            return (out!.trimmingCharacters(in: .whitespacesAndNewlines),
                    err!.trimmingCharacters(in: .whitespacesAndNewlines))
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
