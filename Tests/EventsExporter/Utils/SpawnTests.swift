@testable import EventsExporter
import XCTest

class SpawnTests: XCTestCase {
    func testSpawnCommandRuns() {
        Spawn.command("echo $VALUE", environment: ["VALUE": "Hello World"])
    }

    func testSpawnCommandWithResult() {
        let output = Spawn.commandWithResult("echo $VALUE", environment: ["VALUE": "Hello World"])
        XCTAssertEqual(output, "Hello World\n")
    }

    func testSpawnCommandToFile() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
        Spawn.commandToFile("echo $VALUE", outputPath: tempURL.path, environment: ["VALUE": "Hello World"])
        let writtenData = try String(contentsOf: tempURL, encoding: .ascii)
        XCTAssertEqual(writtenData, "Hello World\n")
    }
}
