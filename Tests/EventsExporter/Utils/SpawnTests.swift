@testable import EventsExporter
import XCTest

class SpawnTests: XCTestCase {
    func testSpawnCommandRuns() {
        Spawn.command("echo Hello World")
    }

    func testSpawnCommandWithResult() {
        let output = Spawn.commandWithResult("echo Hello World")
        XCTAssertEqual(output, "Hello World\n")
    }

    func testSpawnCommandToFile() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
        Spawn.commandToFile("echo Hello World", outputPath: tempURL.path)
        let writtenData = try String(contentsOf: tempURL, encoding: .ascii)
        XCTAssertEqual(writtenData, "Hello World\n")
    }
}
