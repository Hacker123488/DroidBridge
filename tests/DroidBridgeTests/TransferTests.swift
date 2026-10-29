import XCTest
@testable import DroidBridgeCore

final class TransferTests: XCTestCase {
    var transport: MockDeviceTransport!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        transport = MockDeviceTransport(deviceID: "TEST-DEV-XFER")
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
    
    func testUploadLocalFileToDevice() async throws {
        let localFile = tempDirectory.appendingPathComponent("test_upload.txt")
        let content = "Hello DroidBridge transfer test payload from host macOS workstation."
        try content.write(to: localFile, atomically: true, encoding: .utf8)
        
        var reportedProgress: [TransferProgress] = []
        let uploadedItem = try await transport.transferService.upload(
            localURL: localFile,
            remotePath: "/sdcard/Download",
            options: .default
        ) { progress in
            reportedProgress.append(progress)
        }
        
        XCTAssertEqual(uploadedItem.name, "test_upload.txt")
        XCTAssertEqual(uploadedItem.size, Int64(content.utf8.count))
        XCTAssertFalse(reportedProgress.isEmpty, "Progress callbacks should be emitted.")
        
        // Verify item is present in directory listing
        let items = try await transport.fileSystem.listDirectory(at: "/sdcard/Download")
        XCTAssertTrue(items.contains { $0.name == "test_upload.txt" })
    }
    
    func testDownloadFileFromDeviceToLocal() async throws {
        let destinationURL = tempDirectory.appendingPathComponent("downloaded_welcome.txt")
        
        var reportedProgress: [TransferProgress] = []
        try await transport.transferService.download(
            remotePath: "/sdcard/Download/welcome.txt",
            localURL: destinationURL,
            options: .default
        ) { progress in
            reportedProgress.append(progress)
        }
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        let downloadedContent = try String(contentsOf: destinationURL, encoding: .utf8)
        XCTAssertTrue(downloadedContent.contains("Welcome to DroidBridge"))
        XCTAssertFalse(reportedProgress.isEmpty)
    }
    
    func testZeroByteFileTransfer() async throws {
        let emptyLocal = tempDirectory.appendingPathComponent("empty.dat")
        try Data().write(to: emptyLocal)
        
        let item = try await transport.transferService.upload(
            localURL: emptyLocal,
            remotePath: "/sdcard/Download",
            options: .default
        ) { _ in }
        
        XCTAssertEqual(item.size, 0)
        
        let emptyDownload = tempDirectory.appendingPathComponent("empty_downloaded.dat")
        try await transport.transferService.download(
            remotePath: "/sdcard/Download/empty.dat",
            localURL: emptyDownload,
            options: .default
        ) { _ in }
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: emptyDownload.path))
        let data = try Data(contentsOf: emptyDownload)
        XCTAssertEqual(data.count, 0)
    }
}
