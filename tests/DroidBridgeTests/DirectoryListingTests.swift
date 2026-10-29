import XCTest
@testable import DroidBridgeCore

final class DirectoryListingTests: XCTestCase {
    var transport: MockDeviceTransport!
    
    override func setUp() async throws {
        transport = MockDeviceTransport(deviceID: "TEST-DEV-DIR")
        try await transport.connect()
    }
    
    override func tearDown() async throws {
        await transport.disconnect()
        transport = nil
    }
    
    func testListRootDirectoryContainsSdcard() async throws {
        let items = try await transport.fileSystem.listDirectory(at: "/")
        XCTAssertTrue(items.contains { $0.name == "sdcard" && $0.isDirectory }, "Root should contain /sdcard folder.")
    }
    
    func testListSdcardContainsDefaultFolders() async throws {
        let items = try await transport.fileSystem.listDirectory(at: "/sdcard")
        let names = Set(items.map { $0.name })
        
        XCTAssertTrue(names.contains("DCIM"))
        XCTAssertTrue(names.contains("Download"))
        XCTAssertTrue(names.contains("Music"))
        XCTAssertTrue(names.contains("Documents"))
    }
    
    func testListSubdirectoryAndMetadata() async throws {
        let items = try await transport.fileSystem.listDirectory(at: "/sdcard/DCIM")
        XCTAssertTrue(items.contains { $0.name == "sample_photo.jpg" && !$0.isDirectory })
        
        if let photo = items.first(where: { $0.name == "sample_photo.jpg" }) {
            XCTAssertGreaterThan(photo.size, 0)
        }
    }
    
    func testCreateAndListNewDirectory() async throws {
        let created = try await transport.fileSystem.createDirectory(at: "/sdcard", name: "NewTestFolder")
        XCTAssertEqual(created.name, "NewTestFolder")
        XCTAssertTrue(created.isDirectory)
        
        let items = try await transport.fileSystem.listDirectory(at: "/sdcard")
        XCTAssertTrue(items.contains { $0.name == "NewTestFolder" })
    }
    
    func testDeleteItem() async throws {
        _ = try await transport.fileSystem.createDirectory(at: "/sdcard", name: "FolderToDelete")
        try await transport.fileSystem.deleteItem(at: "/sdcard/FolderToDelete", isRecursive: true)
        
        let items = try await transport.fileSystem.listDirectory(at: "/sdcard")
        XCTAssertFalse(items.contains { $0.name == "FolderToDelete" })
    }
}
