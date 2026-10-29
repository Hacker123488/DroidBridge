import Foundation
import Synchronization
import DroidBridgeCore

@MainActor
final class TestRunner {
    private var totalTests = 0
    private var passedTests = 0
    private var failedTests = 0

    func assertTrue(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        totalTests += 1
        if condition {
            passedTests += 1
            print("  ✓ PASS: \(message)")
        } else {
            failedTests += 1
            print("  ✗ FAIL: \(message) [\(file):\(line)]")
        }
    }

    func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
        totalTests += 1
        if a == b {
            passedTests += 1
            print("  ✓ PASS: \(message)")
        } else {
            failedTests += 1
            print("  ✗ FAIL: \(message) (Expected '\(b)', got '\(a)') [\(file):\(line)]")
        }
    }

    func printHeader(_ title: String) {
        print("\n==================================================")
        print(" SUITE: \(title)")
        print("==================================================")
    }

    // MARK: - Test Suites

    func runDeviceConnectionTests() async throws {
        printHeader("Device Connection & Disconnection")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-CONN")
        
        // Test 1: Initial state disconnected
        let initialConnected = await transport.isConnected
        assertTrue(!initialConnected, "Device should initially be disconnected.")
        
        // Test 2: Successful connect
        try await transport.connect()
        let afterConnect = await transport.isConnected
        assertTrue(afterConnect, "Device should report connected after connect().")
        
        // Test 3: Double connection error
        do {
            try await transport.connect()
            assertTrue(false, "Double connection should throw .alreadyConnected.")
        } catch let error as DeviceError {
            assertEqual(error, .alreadyConnected, "Throws .alreadyConnected on duplicate connect().")
        }
        
        // Test 4: Disconnect
        await transport.disconnect()
        let afterDisconnect = await transport.isConnected
        assertTrue(!afterDisconnect, "Device should report disconnected after disconnect().")
        
        // Test 5: Operations on disconnected device
        do {
            _ = try await transport.fileSystem.listDirectory(at: "/sdcard")
            assertTrue(false, "Operation on disconnected device should fail.")
        } catch let error as DeviceError {
            if case .deviceDisconnected(let id) = error {
                assertEqual(id, "TEST-DEV-CONN", "Throws .deviceDisconnected with matching device ID.")
            } else {
                assertTrue(false, "Expected .deviceDisconnected, got \(error).")
            }
        }
    }

    func runDirectoryListingTests() async throws {
        printHeader("Directory Listing & Filesystem Mutation")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-DIR")
        try await transport.connect()
        
        // Test 1: List root directory
        let rootItems = try await transport.fileSystem.listDirectory(at: "/")
        assertTrue(rootItems.contains { $0.name == "sdcard" && $0.isDirectory }, "Root directory contains /sdcard folder.")
        
        // Test 2: List /sdcard standard Android directories
        let sdcardItems = try await transport.fileSystem.listDirectory(at: "/sdcard")
        let names = Set(sdcardItems.map { $0.name })
        assertTrue(names.contains("DCIM"), "sdcard contains DCIM.")
        assertTrue(names.contains("Download"), "sdcard contains Download.")
        assertTrue(names.contains("Music"), "sdcard contains Music.")
        assertTrue(names.contains("Documents"), "sdcard contains Documents.")
        
        // Test 3: List subfolder contents
        let dcimItems = try await transport.fileSystem.listDirectory(at: "/sdcard/DCIM")
        assertTrue(dcimItems.contains { $0.name == "sample_photo.jpg" && !$0.isDirectory }, "DCIM contains sample_photo.jpg file.")
        
        // Test 4: Create new directory
        let newFolder = try await transport.fileSystem.createDirectory(at: "/sdcard", name: "CustomFolder")
        assertEqual(newFolder.name, "CustomFolder", "New directory created with correct name.")
        assertTrue(newFolder.isDirectory, "New item marked as directory.")
        
        // Test 5: Delete item
        try await transport.fileSystem.deleteItem(at: "/sdcard/CustomFolder", isRecursive: true)
        let afterDelete = try await transport.fileSystem.listDirectory(at: "/sdcard")
        assertTrue(!afterDelete.contains { $0.name == "CustomFolder" }, "Deleted folder is removed from listing.")
        
        await transport.disconnect()
    }

    func runTransferTests() async throws {
        printHeader("Bidirectional File Transfers")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-XFER")
        try await transport.connect()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Test 1: Upload Mac -> Android
        let localFile = tempDir.appendingPathComponent("upload_test.txt")
        let payload = "DroidBridge bidirectional payload testing byte parity."
        try payload.write(to: localFile, atomically: true, encoding: .utf8)
        
        let uploadProgressCount = Mutex(0)
        let uploadedItem = try await transport.transferService.upload(
            localURL: localFile,
            remotePath: "/sdcard/Download",
            options: .default
        ) { progress in
            uploadProgressCount.withLock { $0 += 1 }
        }
        assertEqual(uploadedItem.name, "upload_test.txt", "Uploaded item name matches local file.")
        assertEqual(uploadedItem.size, Int64(payload.utf8.count), "Uploaded item size matches payload bytes.")
        assertTrue(uploadProgressCount.withLock { $0 } > 0, "Upload emitted progress updates.")
        
        // Test 2: Download Android -> Mac
        let localDest = tempDir.appendingPathComponent("download_welcome.txt")
        let downloadProgressCount = Mutex(0)
        try await transport.transferService.download(
            remotePath: "/sdcard/Download/welcome.txt",
            localURL: localDest,
            options: .default
        ) { progress in
            downloadProgressCount.withLock { $0 += 1 }
        }
        assertTrue(FileManager.default.fileExists(atPath: localDest.path), "Downloaded file written to macOS destination.")
        let downloadedContent = try String(contentsOf: localDest, encoding: .utf8)
        assertTrue(downloadedContent.contains("Welcome to DroidBridge"), "Downloaded file contents match source.")
        assertTrue(downloadProgressCount.withLock { $0 } > 0, "Download emitted progress updates.")
        
        // Test 3: Zero-byte file transfer
        let emptyFile = tempDir.appendingPathComponent("zero.bin")
        try Data().write(to: emptyFile)
        let emptyUploaded = try await transport.transferService.upload(
            localURL: emptyFile,
            remotePath: "/sdcard/Download",
            options: .default
        ) { _ in }
        assertEqual(emptyUploaded.size, 0, "Zero-byte file transferred without truncation or hang.")
        
        await transport.disconnect()
    }

    func runTransferStateTests() async throws {
        printHeader("Transfer Queue & State Transitions")
        
        let queue = TransferQueueService()
        let job = TransferJob(
            name: "archive.tar",
            direction: .macToAndroid,
            localURL: URL(fileURLWithPath: "/tmp/archive.tar"),
            remotePath: "/sdcard/Download/archive.tar",
            size: 1048576
        )
        
        let jobID = await queue.enqueue(job: job)
        let enqueued = await queue.job(for: jobID)
        assertEqual(enqueued?.state, .pending, "Enqueued job initially in .pending state.")
        
        await queue.updateJobState(id: jobID, state: .inProgress(fractionCompleted: 0.4, speedBytesPerSec: 2500000))
        let inProgress = await queue.job(for: jobID)
        if case .inProgress(let fraction, _) = inProgress?.state {
            assertEqual(fraction, 0.4, "Job transitioned to .inProgress with 40% progress.")
        } else {
            assertTrue(false, "Job should be inProgress.")
        }
        
        try await queue.pause(jobID: jobID)
        let paused = await queue.job(for: jobID)
        if case .paused(let fraction) = paused?.state {
            assertEqual(fraction, 0.4, "Paused job preserves 40% progress.")
        } else {
            assertTrue(false, "Job should be paused.")
        }
        
        try await queue.resume(jobID: jobID)
        let resumed = await queue.job(for: jobID)
        if case .inProgress(let fraction, _) = resumed?.state {
            assertEqual(fraction, 0.4, "Resumed job transitions back to .inProgress.")
        } else {
            assertTrue(false, "Job should be resumed.")
        }
        
        await queue.updateJobState(id: jobID, state: .completed)
        let completed = await queue.job(for: jobID)
        assertEqual(completed?.state, .completed, "Job marked .completed successfully.")
    }

    func runCancellationTests() async throws {
        printHeader("Transfer Cancellation")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-CANCEL")
        try await transport.connect()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let largeFile = tempDir.appendingPathComponent("blob.bin")
        let data = Data(repeating: 0xFF, count: 2 * 1024 * 1024)
        try data.write(to: largeFile)
        
        let task = Task { () throws -> StorageItem in
            try await transport.transferService.upload(
                localURL: largeFile,
                remotePath: "/sdcard/Download",
                options: .default
            ) { _ in }
        }
        
        task.cancel()
        
        do {
            _ = try await task.value
            assertTrue(false, "Cancelled task should throw transferCancelled or CancellationError.")
        } catch let error as DeviceError {
            assertEqual(error, .transferCancelled, "Throws .transferCancelled on cancellation.")
        } catch is CancellationError {
            assertTrue(true, "Caught CancellationError from task runtime.")
        }
        
        // Queue cancellation
        let queue = TransferQueueService()
        let queueJob = TransferJob(
            name: "cancel_me.iso",
            direction: .macToAndroid,
            localURL: URL(fileURLWithPath: "/tmp/cancel_me.iso"),
            remotePath: "/sdcard/Download/cancel_me.iso",
            size: 5000000
        )
        let jid = await queue.enqueue(job: queueJob)
        try await queue.cancel(jobID: jid)
        let cancelled = await queue.job(for: jid)
        assertEqual(cancelled?.state, .cancelled, "Queue successfully marks job .cancelled.")
        
        await transport.disconnect()
    }

    func runPathTraversalTests() async throws {
        printHeader("Path Traversal & Security Validation")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-SEC")
        try await transport.connect()
        
        let illegalPaths = [
            "../",
            "/../../etc/passwd",
            "/sdcard/../../../System",
            "/sdcard/..",
            "../sdcard"
        ]
        
        for path in illegalPaths {
            do {
                _ = try await transport.fileSystem.listDirectory(at: path)
                assertTrue(false, "Path traversal '\(path)' was not rejected!")
            } catch let error as DeviceError {
                assertEqual(error, .pathTraversalForbidden(path: path), "Blocked traversal: \(path)")
            }
        }
        
        // Empty path
        do {
            _ = try await transport.fileSystem.listDirectory(at: "")
            assertTrue(false, "Empty path was not rejected!")
        } catch let error as DeviceError {
            assertEqual(error, .invalidPath(path: ""), "Empty path rejected with .invalidPath.")
        }
        
        await transport.disconnect()
    }

    func runConflictHandlingTests() async throws {
        printHeader("Duplicate Filename & Conflict Resolution")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-CONF")
        try await transport.connect()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let collidingFile = tempDir.appendingPathComponent("welcome.txt")
        let newContent = "Colliding content"
        try newContent.write(to: collidingFile, atomically: true, encoding: .utf8)
        
        // Policy .fail
        do {
            _ = try await transport.transferService.upload(
                localURL: collidingFile,
                remotePath: "/sdcard/Download",
                options: TransferOptions(conflictResolution: .fail)
            ) { _ in }
            assertTrue(false, "Conflict with .fail policy should throw .itemAlreadyExists.")
        } catch let error as DeviceError {
            assertEqual(error, .itemAlreadyExists(path: "/sdcard/Download/welcome.txt"), "Throws .itemAlreadyExists.")
        }
        
        // Policy .overwrite
        let overwritten = try await transport.transferService.upload(
            localURL: collidingFile,
            remotePath: "/sdcard/Download",
            options: TransferOptions(conflictResolution: .overwrite)
        ) { _ in }
        assertEqual(overwritten.name, "welcome.txt", "Overwritten file retains original name.")
        assertEqual(overwritten.size, Int64(newContent.utf8.count), "Overwritten file size updated.")
        
        // Policy .renameWithTimestamp
        let renamed = try await transport.transferService.upload(
            localURL: collidingFile,
            remotePath: "/sdcard/Download",
            options: TransferOptions(conflictResolution: .renameWithTimestamp)
        ) { _ in }
        assertTrue(renamed.name.hasPrefix("welcome_"), "Renamed file contains prefix: \(renamed.name)")
        assertTrue(renamed.name.hasSuffix(".txt"), "Renamed file preserves extension: \(renamed.name)")
        
        await transport.disconnect()
    }

    func runErrorRecoveryTests() async throws {
        printHeader("Provider Errors & Fault Recovery")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-ERR")
        try await transport.connect()
        
        // Simulated unexpected cable pull
        transport.simulateDisconnection()
        assertTrue(!(await transport.isConnected), "simulateDisconnection marks device disconnected.")
        
        do {
            _ = try await transport.fileSystem.listDirectory(at: "/sdcard")
            assertTrue(false, "Operation on disconnected device should fail.")
        } catch let error as DeviceError {
            assertEqual(error, .deviceDisconnected(deviceID: "TEST-DEV-ERR"), "Throws .deviceDisconnected.")
        }
        
        // Reconnect and verify recovery
        try await transport.connect()
        assertTrue(await transport.isConnected, "Device reconnected successfully.")
        let recoveredItems = try await transport.fileSystem.listDirectory(at: "/sdcard")
        assertTrue(!recoveredItems.isEmpty, "Device functional after recovery.")
        
        // Simulated I/O failure
        transport.simulateFailureOnNextOperation()
        do {
            _ = try await transport.fileSystem.listDirectory(at: "/sdcard")
            assertTrue(false, "Simulated I/O failure should throw.")
        } catch let error as DeviceError {
            if case .ioError(let msg) = error {
                assertTrue(msg.contains("Simulated I/O failure"), "Caught .ioError with message.")
            } else {
                assertTrue(false, "Expected .ioError, got \(error).")
            }
        }
        
        // Subsequent call succeeds
        let postErrorItems = try await transport.fileSystem.listDirectory(at: "/sdcard")
        assertTrue(!postErrorItems.isEmpty, "Device resumes normal operation after transient error.")
        
        await transport.disconnect()
    }

    func runDeviceIsolationTests() async throws {
        printHeader("Device Isolation (Multi-Device Independence)")
        
        let devA = MockDeviceTransport(deviceID: "DEV-A", deviceName: "Device Alpha", model: "Alpha")
        let devB = MockDeviceTransport(deviceID: "DEV-B", deviceName: "Device Beta", model: "Beta")
        
        try await devA.connect()
        try await devB.connect()
        
        let secretA = "SecretDirectory_DevA_\(UUID().uuidString.prefix(6))"
        _ = try await devA.fileSystem.createDirectory(at: "/sdcard", name: secretA)
        
        let itemsA = try await devA.fileSystem.listDirectory(at: "/sdcard")
        let itemsB = try await devB.fileSystem.listDirectory(at: "/sdcard")
        
        assertTrue(itemsA.contains { $0.name == secretA }, "Device A contains created directory.")
        assertTrue(!itemsB.contains { $0.name == secretA }, "Device B does NOT contain Device A's directory.")
        
        // Disconnect A; verify B is unaffected
        await devA.disconnect()
        assertTrue(!(await devA.isConnected), "Device A is disconnected.")
        assertTrue(await devB.isConnected, "Device B remains connected.")
        
        let itemsBAfter = try await devB.fileSystem.listDirectory(at: "/sdcard")
        assertTrue(!itemsBAfter.isEmpty, "Device B remains operational.")
        
        await devB.disconnect()
    }

    func executeAll() async -> Bool {
        print("==================================================")
        print(" DroidBridge Milestone 1 Test Harness")
        print(" Platform: macOS / Swift 6 Concurrency")
        print("==================================================")
        
        do {
            try await runDeviceConnectionTests()
            try await runDirectoryListingTests()
            try await runTransferTests()
            try await runTransferStateTests()
            try await runCancellationTests()
            try await runPathTraversalTests()
            try await runConflictHandlingTests()
            try await runErrorRecoveryTests()
            try await runDeviceIsolationTests()
        } catch {
            print("\n❌ FATAL TEST HARNESS ERROR: \(error)")
            return false
        }
        
        print("\n==================================================")
        print(" TEST EXECUTION SUMMARY")
        print("==================================================")
        print(" Total Assertions: \(totalTests)")
        print(" Passed:           \(passedTests)")
        print(" Failed:           \(failedTests)")
        print("==================================================")
        
        return failedTests == 0
    }
}

// MARK: - Runner Entrypoint

@main
struct TestRunnerMain {
    static func main() async {
        let runner = TestRunner()
        let success = await runner.executeAll()
        if success {
            print("🎉 ALL MILESTONE 1 TESTS PASSED SUCCESSFULLY!\n")
            exit(0)
        } else {
            print("❌ SOME TESTS FAILED.\n")
            exit(1)
        }
    }
}
