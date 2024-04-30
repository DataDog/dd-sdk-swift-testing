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
}
