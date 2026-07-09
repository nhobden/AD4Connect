import XCTest
@testable import AD4ConnectKit

final class DiscoveryTests: XCTestCase {
    func testParseNameNullTerminated() {
        var bytes = [UInt8]("Adventurer4".utf8)
        bytes.append(0)
        bytes.append(contentsOf: [0x41, 0x42]) // trailing junk after the null
        let name = PrinterDiscovery.parseName(from: Data(bytes))
        XCTAssertEqual(name, "Adventurer4")
    }

    func testParseNameEmptyIsNil() {
        XCTAssertNil(PrinterDiscovery.parseName(from: Data([0, 0, 0])))
        XCTAssertNil(PrinterDiscovery.parseName(from: Data()))
    }

    func testParsePortBigEndian() {
        var bytes = [UInt8](repeating: 0, count: 0x84)
        bytes.append(contentsOf: [0x22, 0xC3]) // 0x22C3 = 8899
        XCTAssertEqual(PrinterDiscovery.parsePort(from: Data(bytes)), 8899)
    }

    func testParsePortMissingIsNil() {
        XCTAssertNil(PrinterDiscovery.parsePort(from: Data([1, 2, 3])))
    }

    func testCameraStreamURL() {
        XCTAssertEqual(
            CameraStream.streamURL(host: "192.168.1.50")?.absoluteString,
            "http://192.168.1.50:8080/?action=stream")
        XCTAssertEqual(
            CameraStream.streamURL(host: " 10.0.0.9 ", port: 8081, path: "cam")?.absoluteString,
            "http://10.0.0.9:8081/cam")
        XCTAssertNil(CameraStream.streamURL(host: "   "))
    }
}
