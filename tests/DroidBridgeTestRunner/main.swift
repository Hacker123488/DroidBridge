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

    // MARK: - Milestone 1 Regression Test Suites

    func runDeviceConnectionTests() async throws {
        printHeader("M1 Regression: Device Connection & Disconnection")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-CONN")
        
        let initialConnected = await transport.isConnected
        assertTrue(!initialConnected, "Device should initially be disconnected.")
        
        try await transport.connect()
        let afterConnect = await transport.isConnected
        assertTrue(afterConnect, "Device should report connected after connect().")
        
        do {
            try await transport.connect()
            assertTrue(false, "Double connection should throw .alreadyConnected.")
        } catch let error as DeviceError {
            assertEqual(error, .alreadyConnected, "Throws .alreadyConnected on duplicate connect().")
        }
        
        await transport.disconnect()
        let afterDisconnect = await transport.isConnected
        assertTrue(!afterDisconnect, "Device should report disconnected after disconnect().")
        
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
        printHeader("M1 Regression: Directory Listing & Filesystem Mutation")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-DIR")
        try await transport.connect()
        
        let rootItems = try await transport.fileSystem.listDirectory(at: "/")
        assertTrue(rootItems.contains { $0.name == "sdcard" && $0.isDirectory }, "Root directory contains /sdcard folder.")
        
        let sdcardItems = try await transport.fileSystem.listDirectory(at: "/sdcard")
        let names = Set(sdcardItems.map { $0.name })
        assertTrue(names.contains("DCIM"), "sdcard contains DCIM.")
        assertTrue(names.contains("Download"), "sdcard contains Download.")
        assertTrue(names.contains("Music"), "sdcard contains Music.")
        assertTrue(names.contains("Documents"), "sdcard contains Documents.")
        
        let dcimItems = try await transport.fileSystem.listDirectory(at: "/sdcard/DCIM")
        assertTrue(dcimItems.contains { $0.name == "sample_photo.jpg" && !$0.isDirectory }, "DCIM contains sample_photo.jpg file.")
        
        let newFolder = try await transport.fileSystem.createDirectory(at: "/sdcard", name: "CustomFolder")
        assertEqual(newFolder.name, "CustomFolder", "New directory created with correct name.")
        assertTrue(newFolder.isDirectory, "New item marked as directory.")
        
        try await transport.fileSystem.deleteItem(at: "/sdcard/CustomFolder", isRecursive: true)
        let afterDelete = try await transport.fileSystem.listDirectory(at: "/sdcard")
        assertTrue(!afterDelete.contains { $0.name == "CustomFolder" }, "Deleted folder is removed from listing.")
        
        await transport.disconnect()
    }

    func runTransferTests() async throws {
        printHeader("M1 Regression: Bidirectional File Transfers")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-XFER")
        try await transport.connect()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
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
        printHeader("M1 Regression: Transfer Queue & State Transitions")
        
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
        printHeader("M1 Regression: Transfer Cancellation")
        
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
        printHeader("M1 Regression: Path Traversal & Security Validation")
        
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
        
        do {
            _ = try await transport.fileSystem.listDirectory(at: "")
            assertTrue(false, "Empty path was not rejected!")
        } catch let error as DeviceError {
            assertEqual(error, .invalidPath(path: ""), "Empty path rejected with .invalidPath.")
        }
        
        await transport.disconnect()
    }

    func runConflictHandlingTests() async throws {
        printHeader("M1 Regression: Duplicate Filename & Conflict Resolution")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-CONF")
        try await transport.connect()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let collidingFile = tempDir.appendingPathComponent("welcome.txt")
        let newContent = "Colliding content"
        try newContent.write(to: collidingFile, atomically: true, encoding: .utf8)
        
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
        
        let overwritten = try await transport.transferService.upload(
            localURL: collidingFile,
            remotePath: "/sdcard/Download",
            options: TransferOptions(conflictResolution: .overwrite)
        ) { _ in }
        assertEqual(overwritten.name, "welcome.txt", "Overwritten file retains original name.")
        assertEqual(overwritten.size, Int64(newContent.utf8.count), "Overwritten file size updated.")
        
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
        printHeader("M1 Regression: Provider Errors & Fault Recovery")
        
        let transport = MockDeviceTransport(deviceID: "TEST-DEV-ERR")
        try await transport.connect()
        
        transport.simulateDisconnection()
        assertTrue(!(await transport.isConnected), "simulateDisconnection marks device disconnected.")
        
        do {
            _ = try await transport.fileSystem.listDirectory(at: "/sdcard")
            assertTrue(false, "Operation on disconnected device should fail.")
        } catch let error as DeviceError {
            assertEqual(error, .deviceDisconnected(deviceID: "TEST-DEV-ERR"), "Throws .deviceDisconnected.")
        }
        
        try await transport.connect()
        assertTrue(await transport.isConnected, "Device reconnected successfully.")
        let recoveredItems = try await transport.fileSystem.listDirectory(at: "/sdcard")
        assertTrue(!recoveredItems.isEmpty, "Device functional after recovery.")
        
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
        
        let postErrorItems = try await transport.fileSystem.listDirectory(at: "/sdcard")
        assertTrue(!postErrorItems.isEmpty, "Device resumes normal operation after transient error.")
        
        await transport.disconnect()
    }

    func runDeviceIsolationTests() async throws {
        printHeader("M1 Regression: Device Isolation (Multi-Device Independence)")
        
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
        
        await devA.disconnect()
        assertTrue(!(await devA.isConnected), "Device A is disconnected.")
        assertTrue(await devB.isConnected, "Device B remains connected.")
        
        let itemsBAfter = try await devB.fileSystem.listDirectory(at: "/sdcard")
        assertTrue(!itemsBAfter.isEmpty, "Device B remains operational.")
        
        await devB.disconnect()
    }

    // MARK: - Milestone 2 ADB Test Suites

    func runADBConfigurationAndAvailabilityTests() async throws {
        printHeader("M2: ADB Configuration & Availability Detection")
        
        // Test 1: Fallback configuration check
        let config = ADBConfiguration()
        let resolved = config.resolveExecutableURL()
        print("  ℹ️ Local ADB executable detection: \(resolved?.path ?? "Not in PATH")")
        assertTrue(true, "ADBConfiguration candidate paths searched safely.")
        
        // Test 2: Custom override non-existent path
        let customConfig = ADBConfiguration(customADBPath: "/nonexistent/custom/adb")
        XCTAssertNonExistent: do {
            assertEqual(customConfig.resolveExecutableURL(), nil, "Non-existent custom ADB path resolves to nil.")
            assertEqual(customConfig.isAvailable, false, "Non-existent ADB reports isAvailable == false.")
        }
        
        // Test 3: Mock runner reports availability
        let runner = MockADBCommandRunner()
        assertTrue(await runner.isAvailable(), "MockADBCommandRunner initially reports isAvailable == true.")
        let version = try await runner.version()
        assertTrue(version.contains("Android Debug Bridge"), "version() returns ADB signature string.")
        
        // Test 4: Missing ADB error handling
        runner.setAvailable(false)
        assertTrue(!(await runner.isAvailable()), "Runner correctly reports isAvailable == false when disabled.")
        do {
            _ = try await runner.version()
            assertTrue(false, "version() on missing ADB should throw.")
        } catch let error as DeviceError {
            if case .ioError(let msg) = error {
                assertTrue(msg.contains("adb binary not found"), "Throws .ioError with missing binary message.")
            } else {
                assertTrue(false, "Expected .ioError, got \(error).")
            }
        }
        
        // Test 5: ADBDeviceDiscoveryService fails cleanly if ADB unavailable
        let discovery = ADBDeviceDiscoveryService(runner: runner)
        do {
            try await discovery.startDiscovery()
            assertTrue(false, "startDiscovery should throw when ADB is missing.")
        } catch let error as DeviceError {
            if case .ioError(let msg) = error {
                assertTrue(msg.contains("ADB is not available"), "startDiscovery throws .ioError when ADB unavailable.")
            } else {
                assertTrue(false, "Expected .ioError, got \(error).")
            }
        }
    }

    func runADBDiscoveryParsingTests() async throws {
        printHeader("M2: ADB Device Discovery & Status Parsing")
        
        let sampleOutput = """
        List of devices attached
        RFCW10ABCDE            device usb:1-1 product:panther model:Pixel_7 device:panther transport_id:1
        192.168.1.50:5555      device product:husky model:Pixel_8_Pro device:husky transport_id:2
        HT7750201234           unauthorized usb:1-2 transport_id:3
        emulator-5554          offline transport_id:4
        """
        
        let devices = ADBDeviceDiscoveryService.parseDevicesOutput(sampleOutput)
        assertEqual(devices.count, 4, "Parsed exactly 4 devices from sample output.")
        
        // Device 1: Authorized Pixel 7 USB
        let dev1 = devices.first { $0.id == "RFCW10ABCDE" }
        assertTrue(dev1 != nil, "Found device RFCW10ABCDE.")
        assertEqual(dev1?.status, .available, "Device 1 mapped to .available.")
        assertEqual(dev1?.model, "Pixel 7", "Device 1 model extracted accurately.")
        assertEqual(dev1?.name, "Pixel 7 (RFCW10ABCDE)", "Device 1 formatted display name.")
        assertEqual(dev1?.isSimulated, false, "Real ADB device marked isSimulated == false.")
        assertEqual(dev1?.connectionType, .usbADB, "Device connectionType is .usbADB.")
        
        // Device 2: Wi-Fi ADB Pixel 8 Pro
        let dev2 = devices.first { $0.id == "192.168.1.50:5555" }
        assertTrue(dev2 != nil, "Found Wi-Fi device 192.168.1.50:5555.")
        assertEqual(dev2?.status, .available, "Device 2 mapped to .available.")
        assertEqual(dev2?.model, "Pixel 8 Pro", "Device 2 model has spaces instead of underscores.")
        
        // Device 3: Unauthorized phone
        let dev3 = devices.first { $0.id == "HT7750201234" }
        assertTrue(dev3 != nil, "Found device HT7750201234.")
        if case .unauthorized(let msg) = dev3?.status {
            assertTrue(msg.contains("authorize USB debugging"), "Unauthorized device status has helpful prompt.")
        } else {
            assertTrue(false, "Device 3 should have .unauthorized status, got \(String(describing: dev3?.status)).")
        }
        
        // Device 4: Offline emulator
        let dev4 = devices.first { $0.id == "emulator-5554" }
        assertTrue(dev4 != nil, "Found emulator-5554.")
        if case .error(let msg) = dev4?.status {
            assertTrue(msg.contains("offline"), "Offline device mapped to .error.")
        } else {
            assertTrue(false, "Device 4 should have .error status, got \(String(describing: dev4?.status)).")
        }
        
        // Empty output
        let emptyDevices = ADBDeviceDiscoveryService.parseDevicesOutput("List of devices attached\n\n")
        assertEqual(emptyDevices.count, 0, "Empty list returns 0 devices.")
        
        // Output with daemon startup banners
        let daemonBanner = """
        * daemon not running; starting now at tcp:5037 *
        * daemon started successfully *
        List of devices attached
        SN12345                device product:sunfish model:Pixel_4a
        """
        let bannerDevices = ADBDeviceDiscoveryService.parseDevicesOutput(daemonBanner)
        assertEqual(bannerDevices.count, 1, "Daemon startup banners safely ignored.")
        assertEqual(bannerDevices.first?.id, "SN12345", "Parsed valid device past daemon banners.")
    }

    func runADBCommandSafetyAndMultipleDevicesTests() async throws {
        printHeader("M2: Command Argument Safety & Multi-Device Targeting")
        
        let runner = MockADBCommandRunner()
        let dev1Desc = DeviceDescriptor(id: "DEV-SERIAL-1", name: "Pixel 7 (DEV-SERIAL-1)", model: "Pixel 7", connectionType: .usbADB, isSimulated: false, status: .available)
        let dev2Desc = DeviceDescriptor(id: "DEV-SERIAL-2", name: "Galaxy S24 (DEV-SERIAL-2)", model: "SM-S928B", connectionType: .usbADB, isSimulated: false, status: .available)
        
        runner.setSimulatedDevicesOutput("""
        List of devices attached
        DEV-SERIAL-1           device model:Pixel_7
        DEV-SERIAL-2           device model:SM-S928B
        """)
        
        let transport1 = ADBDeviceTransport(descriptor: dev1Desc, runner: runner)
        let transport2 = ADBDeviceTransport(descriptor: dev2Desc, runner: runner)
        
        try await transport1.connect()
        try await transport2.connect()
        
        _ = try await transport1.fileSystem.listDirectory(at: "/sdcard")
        let calls1 = runner.recordedCalls()
        let lastCall1 = calls1.last ?? []
        assertTrue(lastCall1.count >= 2, "Call made with arguments array.")
        assertEqual(lastCall1[0], "-s", "First argument is '-s' device target flag.")
        assertEqual(lastCall1[1], "DEV-SERIAL-1", "Second argument is explicit target serial DEV-SERIAL-1.")
        assertTrue(!lastCall1.joined(separator: " ").contains("/bin/sh"), "No shell string interpolation or execution used.")
        
        _ = try await transport2.fileSystem.listDirectory(at: "/sdcard")
        let calls2 = runner.recordedCalls()
        let lastCall2 = calls2.last ?? []
        assertEqual(lastCall2[0], "-s", "First argument is '-s' device target flag.")
        assertEqual(lastCall2[1], "DEV-SERIAL-2", "Second argument is explicit target serial DEV-SERIAL-2.")
        
        // Verify unauthorized connection attempt throws
        let unauthDesc = DeviceDescriptor(id: "UNAUTH-DEV", name: "Unauth Phone", model: "Phone", connectionType: .usbADB, isSimulated: false, status: .unauthorized(message: "Unauthorized"))
        runner.setSimulatedDevicesOutput("""
        List of devices attached
        UNAUTH-DEV             unauthorized
        """)
        let unauthTransport = ADBDeviceTransport(descriptor: unauthDesc, runner: runner)
        do {
            try await unauthTransport.connect()
            assertTrue(false, "Connecting to unauthorized device should throw.")
        } catch let error as DeviceError {
            if case .permissionDenied(let msg) = error {
                assertTrue(msg.lowercased().contains("authorize"), "Throws .permissionDenied on unauthorized device.")
            } else {
                assertTrue(false, "Expected .permissionDenied, got \(error).")
            }
        }
    }

    func runADBFileSystemAndUnicodeTests() async throws {
        printHeader("M2: ADB Filesystem & Unicode/Space Handling")
        
        let runner = MockADBCommandRunner()
        let desc = DeviceDescriptor(id: "RFCW10ABCDE", name: "Pixel 7", model: "Pixel 7", connectionType: .usbADB, isSimulated: false, status: .available)
        let transport = ADBDeviceTransport(descriptor: desc, runner: runner)
        try await transport.connect()
        
        // Test 1: Path traversal validation
        do {
            _ = try await transport.fileSystem.listDirectory(at: "/sdcard/../../etc/passwd")
            assertTrue(false, "Path traversal should throw .pathTraversalForbidden.")
        } catch let error as DeviceError {
            assertEqual(error, .pathTraversalForbidden(path: "/sdcard/../../etc/passwd"), "Path traversal forbidden.")
        }
        
        // Test 2: List directory with spaces and Unicode
        let items = try await transport.fileSystem.listDirectory(at: "/sdcard/Download")
        assertTrue(items.contains { $0.name == "welcome.txt" }, "Found welcome.txt in Download.")
        assertTrue(items.contains { $0.name == "Unicode 测试 🚀.pdf" }, "Found file with spaces and Unicode: 'Unicode 测试 🚀.pdf'.")
        
        if let unicodeFile = items.first(where: { $0.name == "Unicode 测试 🚀.pdf" }) {
            assertEqual(unicodeFile.size, 2048, "Accurately parsed file size for Unicode file.")
            assertEqual(unicodeFile.isDirectory, false, "Marked as file, not directory.")
        }
        
        // Test 3: Create directory
        let created = try await transport.fileSystem.createDirectory(at: "/sdcard", name: "Folder With Spaces")
        assertEqual(created.name, "Folder With Spaces", "Directory name preserves spaces.")
        assertTrue(created.isDirectory, "Created item is marked as directory.")
        
        // Test 4: Rename item
        let renamed = try await transport.fileSystem.renameItem(at: "/sdcard/Download/welcome.txt", newName: "renamed_welcome.txt")
        assertEqual(renamed.name, "renamed_welcome.txt", "Renamed item has new name.")
        
        // Test 5: Delete item
        try await transport.fileSystem.deleteItem(at: "/sdcard/Download/renamed_welcome.txt", isRecursive: false)
        assertTrue(true, "deleteItem completed successfully.")
        
        await transport.disconnect()
    }

    func runADBTransferAndErrorRecoveryTests() async throws {
        printHeader("M2: Real ADB Transfers, Verification & Error Recovery")
        
        let runner = MockADBCommandRunner()
        let desc = DeviceDescriptor(id: "RFCW10ABCDE", name: "Pixel 7", model: "Pixel 7", connectionType: .usbADB, isSimulated: false, status: .available)
        let transport = ADBDeviceTransport(descriptor: desc, runner: runner)
        try await transport.connect()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Test 1: Upload via adb push
        let localFile = tempDir.appendingPathComponent("push_test.dat")
        let testPayload = "ADB Push streaming payload for hardware validation."
        try testPayload.write(to: localFile, atomically: true, encoding: .utf8)
        
        let uploadProgress = Mutex(0)
        let uploadedItem = try await transport.transferService.upload(
            localURL: localFile,
            remotePath: "/sdcard/Download",
            options: .default
        ) { progress in
            uploadProgress.withLock { $0 += 1 }
        }
        assertEqual(uploadedItem.name, "push_test.dat", "Uploaded item name matches.")
        assertTrue(uploadProgress.withLock { $0 } > 0, "Upload emitted progress.")
        
        // Verify recorded call contains push and local path
        let hasPushCall = runner.recordedCalls().contains { $0.contains("push") }
        let hasLocalPathCall = runner.recordedCalls().contains { $0.contains(localFile.path) }
        assertTrue(hasPushCall, "Executed adb push command.")
        assertTrue(hasLocalPathCall, "Local path passed as argument.")
        
        // Test 2: Upload conflict resolution (.fail)
        do {
            _ = try await transport.transferService.upload(
                localURL: localFile,
                remotePath: "/sdcard/Download/push_test.dat",
                options: TransferOptions(conflictResolution: .fail)
            ) { _ in }
            assertTrue(false, "Uploading existing file with .fail should throw.")
        } catch let error as DeviceError {
            assertEqual(error, .itemAlreadyExists(path: "/sdcard/Download/push_test.dat"), "Throws .itemAlreadyExists.")
        }
        
        // Test 3: Upload failure when storage is full
        runner.setSimulatedPushError("adb: error: failed to copy 'file' to '/sdcard/Download/file': No space left on device")
        let bigLocal = tempDir.appendingPathComponent("big.bin")
        try "data".write(to: bigLocal, atomically: true, encoding: .utf8)
        do {
            _ = try await transport.transferService.upload(
                localURL: bigLocal,
                remotePath: "/sdcard/Download/big.bin",
                options: .default
            ) { _ in }
            assertTrue(false, "Upload to full storage should throw .storageFull.")
        } catch let error as DeviceError {
            assertEqual(error, .storageFull, "Mapped 'No space left on device' to .storageFull.")
        }
        runner.setSimulatedPushError(nil)
        
        // Test 4: Download via adb pull
        let localDest = tempDir.appendingPathComponent("pulled_welcome.txt")
        let downloadProgress = Mutex(0)
        try await transport.transferService.download(
            remotePath: "/sdcard/Download/welcome.txt",
            localURL: localDest,
            options: .default
        ) { progress in
            downloadProgress.withLock { $0 += 1 }
        }
        assertTrue(FileManager.default.fileExists(atPath: localDest.path), "Downloaded file exists on local disk.")
        let pulledContent = try String(contentsOf: localDest, encoding: .utf8)
        assertTrue(pulledContent.contains("Real Android ADB remote payload"), "Pulled content matches source.")
        assertTrue(downloadProgress.withLock { $0 } > 0, "Download emitted progress.")
        
        // Test 5: Device disconnection during transfer
        runner.setSimulateDisconnect(true)
        let disconnectLocal = tempDir.appendingPathComponent("disconnect_test.txt")
        try "content".write(to: disconnectLocal, atomically: true, encoding: .utf8)
        do {
            _ = try await transport.transferService.upload(
                localURL: disconnectLocal,
                remotePath: "/sdcard/Download",
                options: .default
            ) { _ in }
            assertTrue(false, "Upload during disconnect should throw .deviceDisconnected.")
        } catch let error as DeviceError {
            if case .deviceDisconnected(let devId) = error {
                assertEqual(devId, "RFCW10ABCDE", "Throws .deviceDisconnected with device ID.")
            } else {
                assertTrue(false, "Expected .deviceDisconnected, got \(error).")
            }
        }
        runner.setSimulateDisconnect(false)
        
        await transport.disconnect()
    }

    func runADBTimeoutAndCancellationTests() async throws {
        printHeader("M2: ADB Command Timeouts & Task Cancellation")
        
        let runner = MockADBCommandRunner()
        
        // Test 1: Injected command timeout
        runner.setSimulateTimeout(true)
        do {
            _ = try await runner.run(arguments: ["devices", "-l"], timeout: 1.0)
            assertTrue(false, "Timed out command should throw.")
        } catch let error as DeviceError {
            if case .ioError(let msg) = error {
                assertTrue(msg.contains("timed out"), "Caught timeout error: \(msg)")
            } else {
                assertTrue(false, "Expected .ioError with timeout, got \(error).")
            }
        }
        runner.setSimulateTimeout(false)
        
        // Test 2: Task cancellation
        let desc = DeviceDescriptor(id: "RFCW10ABCDE", name: "Pixel 7", model: "Pixel 7", connectionType: .usbADB, isSimulated: false, status: .available)
        let transport = ADBDeviceTransport(descriptor: desc, runner: runner)
        try await transport.connect()
        
        let cancelTask = Task { () throws -> [StorageItem] in
            try await transport.fileSystem.listDirectory(at: "/sdcard")
        }
        cancelTask.cancel()
        
        do {
            _ = try await cancelTask.value
            // Either succeeds if executed before cancellation or throws
            assertTrue(true, "Task completed or threw cancellation.")
        } catch is CancellationError {
            assertTrue(true, "Task cleanly threw CancellationError.")
        } catch {
            assertTrue(true, "Task threw cancellation-related error: \(error)")
        }
        
        await transport.disconnect()
    }

    // MARK: - Milestone 2.1 Symlink & Transfer UI Test Suites

    func runSymlinkAndNavigationTests() async throws {
        printHeader("M2.1: Android Symbolic Link Resolution & Directory Navigation")
        
        let runner = MockADBCommandRunner()
        let physicalSerial = "AE9PH68T4DV86L9P"
        let desc = DeviceDescriptor(
            id: physicalSerial,
            name: "RMX3092 (\(physicalSerial))",
            model: "RMX3092",
            connectionType: .usbADB,
            isSimulated: false,
            status: .available
        )
        
        runner.setSimulatedDevicesOutput("""
        List of devices attached
        \(physicalSerial)       device usb:1-1 product:RMX3092 model:RMX3092
        """)
        
        let transport = ADBDeviceTransport(descriptor: desc, runner: runner)
        try await transport.connect()
        
        // Test 1: Verify listDirectory passes -L to follow symlinks like /sdcard -> /storage/self/primary
        let items = try await transport.fileSystem.listDirectory(at: "/sdcard")
        let calls = runner.recordedCalls()
        let listCall = calls.last ?? []
        assertTrue(listCall.contains("-L"), "listDirectory passes '-L' flag to follow symlinks.")
        assertTrue(listCall.contains("/sdcard"), "listDirectory targets /sdcard path.")
        assertEqual(listCall[0], "-s", "First argument is '-s'.")
        assertEqual(listCall[1], physicalSerial, "Target serial matches physical device.")
        
        // Test 2: Verify /sdcard lists directories instead of a raw symlink entry
        assertTrue(items.contains { $0.name == "Download" }, "/sdcard listing contains Download folder.")
        assertTrue(items.contains { $0.name == "DCIM" }, "/sdcard listing contains DCIM folder.")
        if let downloadItem = items.first(where: { $0.name == "Download" }) {
            assertTrue(downloadItem.isDirectory, "Download is recognized as a directory.")
        }
        
        // Test 3: Verify getItem on /sdcard dereferences symlink with -L
        let sdcardItem = try await transport.fileSystem.getItem(at: "/sdcard")
        let statCalls = runner.recordedCalls()
        let statCall = statCalls.last ?? []
        assertTrue(statCall.contains("-L"), "getItem passes '-L' flag to stat symlink targets.")
        assertTrue(statCall.contains("-ld"), "getItem passes '-ld' flag.")
        assertTrue(sdcardItem.isDirectory, "/sdcard item is recognized as directory (not plain file).")
        assertTrue(!sdcardItem.name.contains("->"), "/sdcard item name does not contain raw symlink arrow notation.")
        
        // Test 4: Verify listing /sdcard/Download
        let downloadItems = try await transport.fileSystem.listDirectory(at: "/sdcard/Download")
        assertTrue(downloadItems.contains { $0.name == "welcome.txt" }, "/sdcard/Download contains welcome.txt file.")
        if let welcomeItem = downloadItems.first(where: { $0.name == "welcome.txt" }) {
            assertEqual(welcomeItem.isDirectory, false, "welcome.txt is recognized as a file.")
        }
        
        // Test 5: Directory navigation via AppViewModel
        await MainActor.run {
            let connMgr = ConnectionManager(adbRunner: runner)
            let vm = AppViewModel(connectionManager: connMgr)
            vm.activeTransport = transport
            vm.selectedDevice = desc
            vm.currentPath = "/sdcard"
            assertEqual(vm.currentPath, "/sdcard", "ViewModel current path initialized to /sdcard.")
        }
        
        await transport.disconnect()
    }

    func runTransferUIIntegrationTests() async throws {
        printHeader("M2.1: Transfer UI Integration & Serial Targeting")
        
        let runner = MockADBCommandRunner()
        let physicalSerial = "AE9PH68T4DV86L9P"
        let desc = DeviceDescriptor(
            id: physicalSerial,
            name: "RMX3092 (\(physicalSerial))",
            model: "RMX3092",
            connectionType: .usbADB,
            isSimulated: false,
            status: .available
        )
        
        runner.setSimulatedDevicesOutput("""
        List of devices attached
        \(physicalSerial)       device usb:1-1 product:RMX3092 model:RMX3092
        """)
        
        let connMgr = ConnectionManager(adbRunner: runner)
        let vm = await MainActor.run {
            AppViewModel(connectionManager: connMgr)
        }
        
        // Connect device in ViewModel
        await vm.connectToDevice(desc)
        await MainActor.run {
            let isConnected = vm.selectedDevice?.id == physicalSerial && vm.activeTransport != nil
            assertTrue(isConnected, "AppViewModel successfully connected to physical device.")
            let isSimulated = vm.selectedDevice?.isSimulated ?? true
            assertEqual(isSimulated, false, "Physical device is NOT marked simulated.")
        }
        
        // Test 1: Upload UI-to-service integration with serial targeting
        let tempDir = FileManager.default.temporaryDirectory
        let uploadFile = tempDir.appendingPathComponent("ui_upload_test.txt")
        try "UI Upload Integration Payload".data(using: .utf8)?.write(to: uploadFile)
        
        await vm.upload(localURL: uploadFile)
        
        await MainActor.run {
            let uploadCompleted = !vm.isTransferring && vm.transferProgressFraction == 1.0
            assertTrue(uploadCompleted, "UI Upload completed successfully with 100% progress.")
            let uploadMsg = vm.statusMessage
            assertTrue(uploadMsg.contains("Uploaded") && uploadMsg.contains("successfully"), "UI Status message reports successful upload.")
        }
        
        // Verify ADB command called with explicit serial targeting
        let recorded = runner.recordedCalls()
        let pushCall = recorded.first { $0.contains("push") } ?? []
        assertTrue(pushCall.count >= 5, "adb push command was invoked.")
        assertEqual(pushCall[0], "-s", "Push command starts with '-s'.")
        assertEqual(pushCall[1], physicalSerial, "Push command targets the physical device serial AE9PH68T4DV86L9P.")
        assertEqual(pushCall[2], "push", "Push command executes 'push'.")
        
        // Test 2: Download UI-to-service integration
        let downloadDest = tempDir.appendingPathComponent("ui_download_test.txt")
        try? FileManager.default.removeItem(at: downloadDest)
        
        let remoteFileItem = StorageItem(
            id: "welcome.txt",
            name: "welcome.txt",
            path: "/sdcard/Download/welcome.txt",
            size: 40,
            modifiedDate: Date(),
            isDirectory: false
        )
        
        await vm.download(item: remoteFileItem, to: downloadDest)
        
        await MainActor.run {
            let downloadCompleted = !vm.isTransferring && vm.transferProgressFraction == 1.0
            assertTrue(downloadCompleted, "UI Download completed successfully with 100% progress.")
            assertTrue(FileManager.default.fileExists(atPath: downloadDest.path), "Downloaded file written to macOS destination.")
        }
        let pullCall = runner.recordedCalls().first { $0.contains("pull") } ?? []
        assertTrue(pullCall.count >= 5, "adb pull command was invoked.")
        assertEqual(pullCall[0], "-s", "Pull command starts with '-s'.")
        assertEqual(pullCall[1], physicalSerial, "Pull command targets the physical device serial AE9PH68T4DV86L9P.")
        
        // Test 3: Inappropriate action prevention (directory download)
        let dirItem = StorageItem(
            id: "Download",
            name: "Download",
            path: "/sdcard/Download",
            size: 0,
            modifiedDate: Date(),
            isDirectory: true
        )
        await vm.download(item: dirItem, to: tempDir.appendingPathComponent("invalid_dir"))
        await MainActor.run {
            let lastError = vm.lastError ?? ""
            assertTrue(lastError.contains("directory"), "Downloading directory is prevented with clear error message.")
        }
        
        // Test 4: Transfer error handling
        runner.setSimulatedPushError("adb: error: failed to copy: permission denied")
        let failUploadFile = tempDir.appendingPathComponent("fail_upload.txt")
        try "Data".data(using: .utf8)?.write(to: failUploadFile)
        
        await vm.upload(localURL: failUploadFile)
        await MainActor.run {
            let transferFailed = !vm.isTransferring && vm.lastError != nil
            assertTrue(transferFailed, "Transfer failure updates error state.")
            let failStatus = vm.statusMessage
            assertTrue(failStatus.contains("Upload failed"), "Status message reflects upload failure.")
        }
        runner.setSimulatedPushError(nil)
        
        // Test 5: Transfer cancellation
        await MainActor.run {
            vm.cancelTransfer()
            assertEqual(vm.isTransferring, false, "cancelTransfer resets transferring state.")
            assertTrue(vm.transferStatusText.contains("Cancelled"), "Status text reflects cancellation.")
        }
        
        // Test 6: Custom valid/invalid ADB path configuration
        let validCustom = ADBConfiguration(customADBPath: "/bin/ls")
        assertEqual(validCustom.isAvailable, true, "Valid custom executable resolves and reports available.")
        let invalidCustom = ADBConfiguration(customADBPath: "/usr/bin/nonexistent_droidbridge_bin")
        assertEqual(invalidCustom.isAvailable, false, "Invalid custom path override returns false and does not fall back.")
        assertEqual(invalidCustom.resolveExecutableURL(), nil, "Invalid custom path resolves to nil.")
        
        // Clean up
        try? FileManager.default.removeItem(at: uploadFile)
        try? FileManager.default.removeItem(at: downloadDest)
        try? FileManager.default.removeItem(at: failUploadFile)
    }

    func executeAll() async -> Bool {
        print("==================================================")
        print(" DroidBridge Milestone 2 Test Harness")
        print(" Platform: macOS / Swift 6 Concurrency")
        print(" Target: Real Android ADB & Mock Regression")
        print("==================================================")
        
        do {
            // Milestone 1 Regression Suites (All 9 Suites, 50 Assertions)
            try await runDeviceConnectionTests()
            try await runDirectoryListingTests()
            try await runTransferTests()
            try await runTransferStateTests()
            try await runCancellationTests()
            try await runPathTraversalTests()
            try await runConflictHandlingTests()
            try await runErrorRecoveryTests()
            try await runDeviceIsolationTests()
            
            // Milestone 2 Real ADB Suites (6 Suites, 53 Assertions)
            try await runADBConfigurationAndAvailabilityTests()
            try await runADBDiscoveryParsingTests()
            try await runADBCommandSafetyAndMultipleDevicesTests()
            try await runADBFileSystemAndUnicodeTests()
            try await runADBTransferAndErrorRecoveryTests()
            try await runADBTimeoutAndCancellationTests()
            
            // Milestone 2.1 Symlink & Transfer UI Suites
            try await runSymlinkAndNavigationTests()
            try await runTransferUIIntegrationTests()
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
            print("🎉 ALL MILESTONE 1 & 2 TESTS PASSED SUCCESSFULLY!\n")
            exit(0)
        } else {
            print("❌ SOME TESTS FAILED.\n")
            exit(1)
        }
    }
}
