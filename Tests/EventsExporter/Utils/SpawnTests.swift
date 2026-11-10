@testable import EventsExporter
import XCTest

class SpawnTests: XCTestCase {
    func testSpawnCommandRuns() throws {
        try Spawn.command("echo Hello World")
    }

    func testSpawnCommandWithResult() throws {
        let output = try Spawn.output("echo Hello World")
        XCTAssertEqual(output, "Hello World")
    }

    func testSpawnCommandToFile() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try Spawn.command("echo Hello World", output: tempURL)
        let writtenData = try String(contentsOf: tempURL, encoding: .ascii)
        XCTAssertEqual(writtenData, "Hello World\n")
    }

    func testSpawnDoesNotInheritParentEnvironmentByDefault() throws {
        let name = "DD_SPAWN_TEST_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        setenv(name, "inherited", 1)
        defer { unsetenv(name) }
        XCTAssertEqual(try Spawn.output("printf '%s' \"${\(name)-unset}\""), "unset")
    }

    func testSpawnPassesExplicitEnvironment() throws {
        let env = ["DD_SPAWN_A": "first value", "DD_SPAWN_B": "it's \"quoted\" $HOME"]
        XCTAssertEqual(try Spawn.output("printf '%s|%s' \"$DD_SPAWN_A\" \"$DD_SPAWN_B\"", environment: env),
                       "first value|it's \"quoted\" $HOME")
        XCTAssertEqual(try Spawn.output("printf '%s' \"${HOME-unset}\"", environment: env), "unset")
    }

    func testSpawnPassesEnvironmentToAllVariants() throws {
        let env = ["DD_SPAWN_VALUE": "42"]
        XCTAssertEqual(try Spawn.combined("printf '%s' \"$DD_SPAWN_VALUE\"", environment: env), "42")
        XCTAssertEqual(Spawn.output(try: "printf '%s' \"$DD_SPAWN_VALUE\"", log: Log(), environment: env), "42")
        XCTAssertEqual(Spawn.command(try: "printf '%s' \"$DD_SPAWN_VALUE\" >&2", log: Log(), environment: env)?.error, "42")
    }

    func testSpawnInheritsEnvironmentWhenRequested() throws {
        let name = "DD_SPAWN_TEST_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        setenv(name, "inherited", 1)
        defer { unsetenv(name) }
        XCTAssertEqual(try Spawn.output("printf '%s' \"$\(name)\"", environment: ProcessInfo.processInfo.environment),
                       "inherited")
    }
}
