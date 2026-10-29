import XCTest
@testable import DroidBridgeCore

final class ErrorRecoveryTests: XCTestCase {
    func testSimulatedDisconnectionAndRecovery() async throws {
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-RECOVER")
        try await transport.connect()
        XCTAssertTrue(await transport.isConnected)
        
        // Ensure healthy operation
        let items = try await transport.fileSystem.listDirectory(at: "/sdcard")
        XCTAssertFalse(items.isEmpty)
        
        // Trigger simulated cable pull / disconnect
        transport.simulateDisconnection()
        XCTAssertFalse(await transport.isConnected)
        
        do {
            _ = try await transport.fileSystem.listDirectory(at: "/sdcard")
            XCTFail("Should throw deviceDisconnected")
        } catch let error as DeviceError {
            XCTAssertEqual(error, .deviceDisconnected(deviceID: "TEST-DEV-RECOVER"))
        }
        
        // Recover by reconnecting
        try await transport.connect()
        XCTAssertTrue(await transport.isConnected)
        
        let recoveredItems = try await transport.fileSystem.listDirectory(at: "/sdcard")
        XCTAssertFalse(recoveredItems.isEmpty)
    }
    
    func testSimulatedIOFailure() async throws {
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-IOFAIL")
        try await transport.connect()
        
        transport.simulateFailureOnNextOperation()
        
        do {
            _ = try await transport.fileSystem.listDirectory(at: "/sdcard")
            XCTFail("Operation should fail after simulated I/O failure injection")
        } catch let error as DeviceError {
            if case .ioError(let msg) = error {
                XCTAssertTrue(msg.contains("Simulated I/O failure"))
            } else {
                XCTFail("Expected .ioError, got \(error)")
            }
        }
        
        // Next operation should succeed normally
        let items = try await transport.fileSystem.listDirectory(at: "/sdcard")
        XCTAssertFalse(items.isEmpty)
    }
}
