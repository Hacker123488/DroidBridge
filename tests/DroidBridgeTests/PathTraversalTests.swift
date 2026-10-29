import XCTest
@testable import DroidBridgeCore

final class PathTraversalTests: XCTestCase {
    var transport: MockDeviceTransport!
    
    override func setUp() async throws {
        transport = MockDeviceTransport(deviceID: "TEST-DEV-SEC")
        try await transport.connect()
    }
    
    override func tearDown() async throws {
        await transport.disconnect()
        transport = nil
    }
    
    func testParentTraversalThrowsSecurityError() async {
        let maliciousPaths = [
            "../",
            "/../../etc/passwd",
            "/sdcard/../../../System",
            "/sdcard/..",
            "../sdcard"
        ]
        
        for path in maliciousPaths {
            do {
                _ = try await transport.fileSystem.listDirectory(at: path)
                XCTFail("Path traversal '\(path)' must be rejected with an error.")
            } catch let error as DeviceError {
                XCTAssertEqual(error, .pathTraversalForbidden(path: path))
            } catch {
                XCTFail("Unexpected error for path \(path): \(error)")
            }
        }
    }
    
    func testEmptyPathThrowsInvalidPathError() async {
        do {
            _ = try await transport.fileSystem.listDirectory(at: "")
            XCTFail("Empty path should throw invalidPath.")
        } catch let error as DeviceError {
            XCTAssertEqual(error, .invalidPath(path: ""))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCreateDirectoryTraversalPrevention() async {
        do {
            _ = try await transport.fileSystem.createDirectory(at: "/sdcard", name: "../escape")
            XCTFail("Creating directory with '..' must fail.")
        } catch let error as DeviceError {
            XCTAssertEqual(error, .invalidPath(path: "../escape"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
