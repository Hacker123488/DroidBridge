import XCTest
@testable import DroidBridgeCore

final class DeviceIsolationTests: XCTestCase {
    func testDeviceFilesystemAndStateIsolation() async throws {
        let deviceA = MockDeviceTransport(
            deviceID: "SIM-DEV-A",
            deviceName: "[SIMULATED] Pixel A",
            model: "Pixel A"
        )
        let deviceB = MockDeviceTransport(
            deviceID: "SIM-DEV-B",
            deviceName: "[SIMULATED] Pixel B",
            model: "Pixel B"
        )
        
        try await deviceA.connect()
        try await deviceB.connect()
        
        XCTAssertTrue(await deviceA.isConnected)
        XCTAssertTrue(await deviceB.isConnected)
        
        // Mutate Device A by creating a unique directory
        let uniqueName = "DeviceA_Exclusive_\(UUID().uuidString.prefix(6))"
        _ = try await deviceA.fileSystem.createDirectory(at: "/sdcard", name: uniqueName)
        
        // Verify Device A has the directory
        let itemsA = try await deviceA.fileSystem.listDirectory(at: "/sdcard")
        XCTAssertTrue(itemsA.contains { $0.name == uniqueName })
        
        // Verify Device B does NOT have the directory
        let itemsB = try await deviceB.fileSystem.listDirectory(at: "/sdcard")
        XCTAssertFalse(itemsB.contains { $0.name == uniqueName }, "Device B must not share filesystem state with Device A.")
        
        // Disconnecting Device A must not affect Device B
        await deviceA.disconnect()
        XCTAssertFalse(await deviceA.isConnected)
        XCTAssertTrue(await deviceB.isConnected, "Device B must remain connected when Device A disconnects.")
        
        // Device B can still perform operations
        let checkItemsB = try await deviceB.fileSystem.listDirectory(at: "/sdcard")
        XCTAssertFalse(checkItemsB.isEmpty)
        
        await deviceB.disconnect()
    }
}
