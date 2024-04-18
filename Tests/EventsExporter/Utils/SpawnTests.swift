@testable import EventsExporter
import XCTest

class SpawnTests: XCTestCase {
    func testSpawnCommandRuns() throws {
        try Spawn.command("echo Hello World")
    }

    func testSpawnCommandWithResult() throws {
        let output = try Spawn.commandWithResult("echo Hello World")
        XCTAssertEqual(output, "Hello World\n")
    }

    func testSpawnCommandToFile() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
        try Spawn.commandToFile("echo Hello World", outputPath: tempURL.path)
        let writtenData = try String(contentsOf: tempURL, encoding: .ascii)
        XCTAssertEqual(writtenData, "Hello World\n")
    }
}
