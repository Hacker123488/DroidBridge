import XCTest
@testable import DroidBridgeCore

final class ConflictHandlingTests: XCTestCase {
    var transport: MockDeviceTransport!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        transport = MockDeviceTransport(deviceID: "TEST-DEV-CONFLICT")
        try await transport.connect()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        await transport.disconnect()
        transport = nil
        if let temp = tempDirectory {
            try? FileManager.default.removeItem(at: temp)
        }
    }
    
    func testDuplicateFileFailsWhenPolicyIsFail() async throws {
        let localFile = tempDirectory.appendingPathComponent("welcome.txt")
        try "New colliding content".write(to: localFile, atomically: true, encoding: .utf8)
        
        do {
            _ = try await transport.transferService.upload(
                localURL: localFile,
                remotePath: "/sdcard/Download",
                options: TransferOptions(conflictResolution: .fail)
            ) { _ in }
            XCTFail("Upload should fail when file exists and policy is .fail")
        } catch let error as DeviceError {
            XCTAssertEqual(error, .itemAlreadyExists(path: "/sdcard/Download/welcome.txt"))
        }
    }
    
    func testDuplicateFileOverwritesWhenPolicyIsOverwrite() async throws {
        let localFile = tempDirectory.appendingPathComponent("welcome.txt")
        let replacement = "Completely updated content."
        try replacement.write(to: localFile, atomically: true, encoding: .utf8)
        
        let item = try await transport.transferService.upload(
            localURL: localFile,
            remotePath: "/sdcard/Download",
            options: TransferOptions(conflictResolution: .overwrite)
        ) { _ in }
        
        XCTAssertEqual(item.name, "welcome.txt")
        XCTAssertEqual(item.size, Int64(replacement.utf8.count))
    }
    
    func testDuplicateFileRenamesWhenPolicyIsRename() async throws {
        let localFile = tempDirectory.appendingPathComponent("welcome.txt")
        try "Renamed content".write(to: localFile, atomically: true, encoding: .utf8)
        
        let item = try await transport.transferService.upload(
            localURL: localFile,
            remotePath: "/sdcard/Download",
            options: TransferOptions(conflictResolution: .renameWithTimestamp)
        ) { _ in }
        
        XCTAssertTrue(item.name.hasPrefix("welcome_"))
        XCTAssertTrue(item.name.hasSuffix(".txt"))
        
        // Both the original and the new file should exist in the directory
        let items = try await transport.fileSystem.listDirectory(at: "/sdcard/Download")
        XCTAssertTrue(items.contains { $0.name == "welcome.txt" })
        XCTAssertTrue(items.contains { $0.name == item.name })
    }
}
