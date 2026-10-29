import XCTest
@testable import DroidBridgeCore

final class CancellationTests: XCTestCase {
    var transport: MockDeviceTransport!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        transport = MockDeviceTransport(deviceID: "TEST-DEV-CANCEL")
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
    
    func testTaskCancellationThrowsError() async throws {
        let largeFile = tempDirectory.appendingPathComponent("large_blob.bin")
        // Create 2 MB data
        let dummyData = Data(repeating: 0xAB, count: 2 * 1024 * 1024)
        try dummyData.write(to: largeFile)
        
        let uploadTask = Task { () throws -> StorageItem in
            try await transport.transferService.upload(
                localURL: largeFile,
                remotePath: "/sdcard/Download",
                options: .default
            ) { _ in }
        }
        
        // Cancel task almost immediately
        uploadTask.cancel()
        
        do {
            _ = try await uploadTask.value
            XCTFail("Cancelled task should throw transferCancelled or CancellationError.")
        } catch let error as DeviceError {
            XCTAssertEqual(error, .transferCancelled)
        } catch is CancellationError {
            // Expected alternative from Swift Concurrency runtime
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error caught: \(error)")
        }
    }
    
    func testQueueCancellation() async throws {
        let queue = TransferQueueService()
        let job = TransferJob(
            name: "test.zip",
            direction: .macToAndroid,
            localURL: URL(fileURLWithPath: "/tmp/test.zip"),
            remotePath: "/sdcard/Download/test.zip",
            size: 1000
        )
        
        let jobID = await queue.enqueue(job: job)
        try await queue.cancel(jobID: jobID)
        
        let cancelledJob = await queue.job(for: jobID)
        XCTAssertEqual(cancelledJob?.state, .cancelled)
    }
}
