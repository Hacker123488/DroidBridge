import XCTest
@testable import DroidBridgeCore

final class DeviceConnectionTests: XCTestCase {
    func testDeviceInitialStateDisconnected() async {
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-001")
        let isConnected = await transport.isConnected
        XCTAssertFalse(isConnected, "Device should initially be disconnected.")
    }
    
    func testDeviceSuccessfulConnection() async throws {
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-002")
        try await transport.connect()
        let isConnected = await transport.isConnected
        XCTAssertTrue(isConnected, "Device should report connected after connect().")
    }
    
    func testDoubleConnectionThrowsError() async throws {
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-003")
        try await transport.connect()
        
        do {
            try await transport.connect()
            XCTFail("Connecting an already connected transport should throw.")
        } catch let error as DeviceError {
            XCTAssertEqual(error, .alreadyConnected)
        }
    }
    
    func testDeviceDisconnection() async throws {
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-004")
        try await transport.connect()
        XCTAssertTrue(await transport.isConnected)
        
        await transport.disconnect()
        XCTAssertFalse(await transport.isConnected)
    }
    
    func testOperationsWhenDisconnectedFail() async {
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-005")
        
        do {
            _ = try await transport.fileSystem.listDirectory(at: "/sdcard")
            XCTFail("Operations on disconnected device must throw error.")
        } catch let error as DeviceError {
            if case .deviceDisconnected(let devId) = error {
                XCTAssertEqual(devId, "TEST-DEV-005")
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
