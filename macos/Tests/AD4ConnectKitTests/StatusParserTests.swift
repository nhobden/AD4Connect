import XCTest
@testable import AD4ConnectKit

final class StatusParserTests: XCTestCase {
    func testParseStatus() {
        let status = StatusParser.parseStatus(
            "MachineStatus: READY\nMoveMode: READY\nCurrentFile: test.gcode\nok",
            "T0:14/0 B:-3/0\nok",
            "SD printing byte 9/100\nLayer: 0/0\nok"
        )
        XCTAssertEqual(status.machineStatus, "READY")
        XCTAssertEqual(status.currentFile, "test.gcode")
        XCTAssertEqual(status.nozzleCurrent, 14)
        XCTAssertEqual(status.bedCurrent, -3)
        XCTAssertEqual(status.progressPercent, 9.0)
    }

    // Real hardware sends CRLF line endings and extra header lines. Swift treats
    // "\r\n" as one Character, which broke an earlier split-based parser.
    func testParseStatusCRLFWithHeaderLines() {
        let m119 = "CMD M119 Received.\r\nEndstop: X-max:0 Y-max:0 Z-max:0\r\n"
            + "MachineStatus: BUILDING_FROM_SD\r\nMoveMode: MOVING\r\n"
            + "Status: S:1 L:0 J:0 F:0\r\nLED: 1\r\nCurrentFile: test.gcode\r\nok\r\n"
        let m105 = "CMD M105 Received.\r\nT0:220/220 B:60/60\r\nok\r\n"
        let m27 = "CMD M27 Received.\r\nSD printing byte 71/100\r\nLayer: 0/0\r\nok\r\n"
        let status = StatusParser.parseStatus(m119, m105, m27)
        XCTAssertEqual(status.machineStatus, "BUILDING_FROM_SD")
        XCTAssertEqual(status.moveMode, "MOVING")
        XCTAssertEqual(status.currentFile, "test.gcode")
        XCTAssertEqual(status.nozzleCurrent, 220)
        XCTAssertEqual(status.bedCurrent, 60)
        XCTAssertEqual(status.progressPercent, 71.0)
        XCTAssertTrue(status.isPrinting)
    }

    func testParseFileList() {
        let raw = "D\u{fffd}\u{fffd}/data/test.gcode::\u{fffd}\u{fffd}/data/Owlbear.gx::\u{fffd}\u{fffd}"
        XCTAssertEqual(StatusParser.parseFileList(raw), ["/data/test.gcode", "/data/Owlbear.gx"])
    }

    func testIsPrinting() {
        XCTAssertTrue(StatusParser.parseStatus("MachineStatus: BUILDING_FROM_SD\nok").isPrinting)
        XCTAssertFalse(StatusParser.parseStatus("MachineStatus: READY\nok").isPrinting)
    }

    func testProgressNilWhenNoBytes() {
        XCTAssertNil(StatusParser.parseStatus("MachineStatus: READY\nok").progressPercent)
    }
}
