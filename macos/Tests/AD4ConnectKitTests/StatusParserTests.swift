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
