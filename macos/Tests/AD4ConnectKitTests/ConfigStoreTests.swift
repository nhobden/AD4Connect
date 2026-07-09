import XCTest
@testable import AD4ConnectKit

final class ConfigStoreTests: XCTestCase {
    private func tempEnv() -> (env: [String: String], path: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ad4-\(UUID().uuidString)")
        let path = dir.appendingPathComponent("config.ini")
        return (["AD4CONNECT_CONFIG": path.path], path)
    }

    func testLoadEmptyWhenMissing() {
        let (env, _) = tempEnv()
        XCTAssertTrue(ConfigStore.load(environment: env).isEmpty)
    }

    func testSaveThenLoadRoundtrip() throws {
        let (env, _) = tempEnv()
        try ConfigStore.save(["host": "192.168.1.50", "port": "8899"], environment: env)
        let loaded = ConfigStore.load(environment: env)
        XCTAssertEqual(loaded["host"], "192.168.1.50")
        XCTAssertEqual(loaded["port"], "8899")
    }

    func testSaveMergesWithoutDropping() throws {
        let (env, _) = tempEnv()
        try ConfigStore.save(["host": "10.0.0.5"], environment: env)
        try ConfigStore.save(["port": "9999"], environment: env)
        XCTAssertEqual(ConfigStore.load(environment: env), ["host": "10.0.0.5", "port": "9999"])
    }

    func testReadsFileWrittenByPythonConfigparser() throws {
        let (env, path) = tempEnv()
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "[connection]\nhost = 192.168.1.50\nport = 8899\n\n".write(
            to: path, atomically: true, encoding: .utf8)
        let loaded = ConfigStore.load(environment: env)
        XCTAssertEqual(loaded["host"], "192.168.1.50")
        XCTAssertEqual(loaded["port"], "8899")
    }

    func testConfigPathOverride() {
        let (env, path) = tempEnv()
        XCTAssertEqual(ConfigStore.configPath(environment: env), path)
    }
}
