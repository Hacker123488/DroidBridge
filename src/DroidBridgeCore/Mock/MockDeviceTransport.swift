import Foundation
import Synchronization

/// Internal mutable state protected by Mutex.
private struct MockTransportState: ~Copyable {
    var isConnected: Bool = false
    var simulateFailureOnNextOperation: Bool = false
}

/// A simulated DeviceTransport backed by a local temporary directory.
/// Strictly labeled as a simulated device and isolated per instance.
public final class MockDeviceTransport: DeviceTransport, @unchecked Sendable {
    public let deviceID: String
    public let descriptor: DeviceDescriptor
    
    private let state = Mutex(MockTransportState())
    
    public let backingDirectory: URL
    public let fileSystem: any DeviceFileSystem
    public let transferService: any TransferService
    
    public var isConnected: Bool {
        get async {
            state.withLock { $0.isConnected }
        }
    }
    
    public init(
        deviceID: String = "SIM-DEV-\(UUID().uuidString.prefix(8))",
        deviceName: String = "[SIMULATED] Android Pixel 9 Pro (Mock)",
        model: String = "Pixel 9 Pro (Simulated)",
        customBackingURL: URL? = nil
    ) {
        self.deviceID = deviceID
        self.descriptor = DeviceDescriptor(
            id: deviceID,
            name: deviceName,
            model: model,
            connectionType: .simulatedMock,
            isSimulated: true,
            status: .available
        )
        
        let rootURL = customBackingURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("DroidBridge_Mock_\(deviceID)_\(UUID().uuidString)")
        self.backingDirectory = rootURL
        
        let fs = MockFileSystem(rootDirectory: rootURL, transportRef: nil)
        let ts = MockTransferService(fileSystem: fs, transportRef: nil)
        
        self.fileSystem = fs
        self.transferService = ts
        
        fs.transport = self
        ts.transport = self
        
        // Seed default directory hierarchy
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        seedInitialFilesystem(at: rootURL)
    }
    
    deinit {
        try? FileManager.default.removeItem(at: backingDirectory)
    }
    
    public func connect() async throws {
        try state.withLock { s in
            if s.simulateFailureOnNextOperation {
                s.simulateFailureOnNextOperation = false
                throw DeviceError.connectionFailed(reason: "Simulated connection error")
            }
            if s.isConnected {
                throw DeviceError.alreadyConnected
            }
            s.isConnected = true
        }
    }
    
    public func disconnect() async {
        state.withLock { s in
            s.isConnected = false
        }
    }
    
    /// Trigger for testing error recovery and sudden disconnects.
    public func simulateDisconnection() {
        state.withLock { s in
            s.isConnected = false
        }
    }
    
    public func simulateFailureOnNextOperation() {
        state.withLock { s in
            s.simulateFailureOnNextOperation = true
        }
    }
    
    internal func checkConnection() throws {
        try state.withLock { s in
            if !s.isConnected {
                throw DeviceError.deviceDisconnected(deviceID: deviceID)
            }
            if s.simulateFailureOnNextOperation {
                s.simulateFailureOnNextOperation = false
                throw DeviceError.ioError(message: "Simulated I/O failure on transport \(deviceID)")
            }
        }
    }
    
    private func seedInitialFilesystem(at root: URL) {
        let defaultFolders = ["sdcard", "sdcard/DCIM", "sdcard/Download", "sdcard/Music", "sdcard/Documents"]
        for folder in defaultFolders {
            let folderURL = root.appendingPathComponent(folder)
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        
        let samplePhoto = root.appendingPathComponent("sdcard/DCIM/sample_photo.jpg")
        let photoData = "Simulated JPEG binary header and pixel data".data(using: .utf8) ?? Data()
        try? photoData.write(to: samplePhoto)
        
        let sampleReadme = root.appendingPathComponent("sdcard/Download/welcome.txt")
        let readmeData = "Welcome to DroidBridge simulated Android filesystem.\n".data(using: .utf8) ?? Data()
        try? readmeData.write(to: sampleReadme)
    }
}

// MARK: - Mock FileSystem

private final class MockFileSystem: DeviceFileSystem, @unchecked Sendable {
    let rootDirectory: URL
    weak var transport: MockDeviceTransport?
    
    init(rootDirectory: URL, transportRef: MockDeviceTransport?) {
        self.rootDirectory = rootDirectory
        self.transport = transportRef
    }
    
    private func resolveLocalURL(for devicePath: String) throws -> URL {
        try transport?.checkConnection()
        
        let trimmed = devicePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw DeviceError.invalidPath(path: devicePath)
        }
        
        // Prevent path traversal
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        for component in components {
            if component == ".." || component == "." {
                throw DeviceError.pathTraversalForbidden(path: devicePath)
            }
        }
        
        var currentURL = rootDirectory
        for component in components {
            currentURL = currentURL.appendingPathComponent(String(component))
        }
        
        let canonicalRoot = rootDirectory.standardizedFileURL.path
        let canonicalTarget = currentURL.standardizedFileURL.path
        
        guard canonicalTarget.hasPrefix(canonicalRoot) else {
            throw DeviceError.pathTraversalForbidden(path: devicePath)
        }
        
        return currentURL
    }
    
    func listDirectory(at path: String) async throws -> [StorageItem] {
        let localURL = try resolveLocalURL(for: path)
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw DeviceError.itemNotFound(path: path)
        }
        
        let contents = try FileManager.default.contentsOfDirectory(at: localURL, includingPropertiesForKeys: [
            .fileSizeKey, .contentModificationDateKey, .isDirectoryKey
        ], options: [.skipsHiddenFiles])
        
        return try contents.map { itemURL in
            let resourceValues = try itemURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            let isItemDir = resourceValues.isDirectory ?? false
            let size = isItemDir ? 0 : Int64(resourceValues.fileSize ?? 0)
            let modDate = resourceValues.contentModificationDate ?? Date()
            let relPath = itemURL.path.replacingOccurrences(of: rootDirectory.path, with: "")
            let normalizedPath = relPath.hasPrefix("/") ? relPath : "/" + relPath
            
            return StorageItem(
                id: itemURL.lastPathComponent,
                name: itemURL.lastPathComponent,
                path: normalizedPath,
                size: size,
                modifiedDate: modDate,
                isDirectory: isItemDir
            )
        }
    }
    
    func getItem(at path: String) async throws -> StorageItem {
        let localURL = try resolveLocalURL(for: path)
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir) else {
            throw DeviceError.itemNotFound(path: path)
        }
        
        let resourceValues = try localURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
        let size = isDir.boolValue ? 0 : Int64(resourceValues.fileSize ?? 0)
        let modDate = resourceValues.contentModificationDate ?? Date()
        
        return StorageItem(
            id: localURL.lastPathComponent,
            name: localURL.lastPathComponent,
            path: path,
            size: size,
            modifiedDate: modDate,
            isDirectory: isDir.boolValue
        )
    }
    
    func createDirectory(at path: String, name: String) async throws -> StorageItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName.contains("/") || trimmedName == ".." {
            throw DeviceError.invalidPath(path: name)
        }
        
        let parentURL = try resolveLocalURL(for: path)
        let targetURL = parentURL.appendingPathComponent(trimmedName)
        
        if FileManager.default.fileExists(atPath: targetURL.path) {
            throw DeviceError.itemAlreadyExists(path: "\(path)/\(trimmedName)")
        }
        
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
        
        let relPath = targetURL.path.replacingOccurrences(of: rootDirectory.path, with: "")
        let normalizedPath = relPath.hasPrefix("/") ? relPath : "/" + relPath
        
        return StorageItem(
            id: trimmedName,
            name: trimmedName,
            path: normalizedPath,
            size: 0,
            modifiedDate: Date(),
            isDirectory: true
        )
    }
    
    func deleteItem(at path: String, isRecursive: Bool) async throws {
        let localURL = try resolveLocalURL(for: path)
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir) else {
            throw DeviceError.itemNotFound(path: path)
        }
        
        if isDir.boolValue && !isRecursive {
            let contents = try FileManager.default.contentsOfDirectory(atPath: localURL.path)
            if !contents.isEmpty {
                throw DeviceError.ioError(message: "Directory is not empty and recursive delete was false.")
            }
        }
        
        try FileManager.default.removeItem(at: localURL)
    }
    
    func renameItem(at path: String, newName: String) async throws -> StorageItem {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName.contains("/") || trimmedName == ".." {
            throw DeviceError.invalidPath(path: newName)
        }
        
        let currentURL = try resolveLocalURL(for: path)
        guard FileManager.default.fileExists(atPath: currentURL.path) else {
            throw DeviceError.itemNotFound(path: path)
        }
        
        let targetURL = currentURL.deletingLastPathComponent().appendingPathComponent(trimmedName)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            throw DeviceError.itemAlreadyExists(path: targetURL.path)
        }
        
        try FileManager.default.moveItem(at: currentURL, to: targetURL)
        
        let relPath = targetURL.path.replacingOccurrences(of: rootDirectory.path, with: "")
        let normalizedPath = relPath.hasPrefix("/") ? relPath : "/" + relPath
        
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir)
        let resourceValues = try targetURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        
        return StorageItem(
            id: trimmedName,
            name: trimmedName,
            path: normalizedPath,
            size: isDir.boolValue ? 0 : Int64(resourceValues.fileSize ?? 0),
            modifiedDate: resourceValues.contentModificationDate ?? Date(),
            isDirectory: isDir.boolValue
        )
    }
    
    func moveItem(from sourcePath: String, to destinationPath: String) async throws -> StorageItem {
        let srcURL = try resolveLocalURL(for: sourcePath)
        guard FileManager.default.fileExists(atPath: srcURL.path) else {
            throw DeviceError.itemNotFound(path: sourcePath)
        }
        
        let dstURL = try resolveLocalURL(for: destinationPath)
        if FileManager.default.fileExists(atPath: dstURL.path) {
            throw DeviceError.itemAlreadyExists(path: destinationPath)
        }
        
        try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: srcURL, to: dstURL)
        return try await getItem(at: destinationPath)
    }
    
    func copyItem(from sourcePath: String, to destinationPath: String) async throws -> StorageItem {
        let srcURL = try resolveLocalURL(for: sourcePath)
        guard FileManager.default.fileExists(atPath: srcURL.path) else {
            throw DeviceError.itemNotFound(path: sourcePath)
        }
        
        let dstURL = try resolveLocalURL(for: destinationPath)
        if FileManager.default.fileExists(atPath: dstURL.path) {
            throw DeviceError.itemAlreadyExists(path: destinationPath)
        }
        
        try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: srcURL, to: dstURL)
        return try await getItem(at: destinationPath)
    }
}

// MARK: - Mock TransferService

private final class MockTransferService: TransferService, @unchecked Sendable {
    private let fileSystem: MockFileSystem
    weak var transport: MockDeviceTransport?
    
    init(fileSystem: MockFileSystem, transportRef: MockDeviceTransport?) {
        self.fileSystem = fileSystem
        self.transport = transportRef
    }
    
    func upload(
        localURL: URL,
        remotePath: String,
        options: TransferOptions,
        progress: @Sendable @escaping (TransferProgress) -> Void
    ) async throws -> StorageItem {
        try transport?.checkConnection()
        
        var isLocalDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isLocalDir) else {
            throw DeviceError.itemNotFound(path: localURL.path)
        }
        
        let fileSize: Int64
        if isLocalDir.boolValue {
            fileSize = 0
        } else {
            let localValues = try localURL.resourceValues(forKeys: [.fileSizeKey])
            fileSize = Int64(localValues.fileSize ?? 0)
        }
        
        var targetFilename = localURL.lastPathComponent
        var targetDirectoryPath = remotePath
        
        var isDir = false
        do {
            let item = try await fileSystem.getItem(at: remotePath)
            if item.isDirectory {
                isDir = true
            }
        } catch {}
        
        let finalRemotePath: String
        if isDir {
            finalRemotePath = remotePath.hasSuffix("/") ? "\(remotePath)\(targetFilename)" : "\(remotePath)/\(targetFilename)"
        } else {
            finalRemotePath = remotePath
            targetFilename = (remotePath as NSString).lastPathComponent
            targetDirectoryPath = (remotePath as NSString).deletingLastPathComponent
        }
        
        var resolvedPath = finalRemotePath
        var exists = false
        do {
            _ = try await fileSystem.getItem(at: finalRemotePath)
            exists = true
        } catch {}
        
        if exists {
            switch options.conflictResolution {
            case .fail:
                throw DeviceError.itemAlreadyExists(path: finalRemotePath)
            case .overwrite:
                try await fileSystem.deleteItem(at: finalRemotePath, isRecursive: true)
            case .renameWithTimestamp:
                let ext = (targetFilename as NSString).pathExtension
                let base = (targetFilename as NSString).deletingPathExtension
                let timestamp = Int(Date().timeIntervalSince1970)
                let newFilename = ext.isEmpty ? "\(base)_\(timestamp)" : "\(base)_\(timestamp).\(ext)"
                resolvedPath = targetDirectoryPath.hasSuffix("/") ? "\(targetDirectoryPath)\(newFilename)" : "\(targetDirectoryPath)/\(newFilename)"
            }
        }
        
        if isLocalDir.boolValue {
            try Task.checkCancellation()
            try transport?.checkConnection()
            let destURL = fileSystem.rootDirectory.appendingPathComponent(resolvedPath.replacingOccurrences(of: "^/", with: "", options: .regularExpression))
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: localURL, to: destURL)
            progress(TransferProgress(bytesTransferred: 1024, totalBytes: 1024, speedBytesPerSec: 10 * 1024 * 1024))
            return try await fileSystem.getItem(at: resolvedPath)
        }
        
        let data = try Data(contentsOf: localURL)
        let chunkSize = 64 * 1024
        var bytesWritten: Int64 = 0
        
        if fileSize == 0 {
            try Task.checkCancellation()
            try transport?.checkConnection()
            progress(TransferProgress(bytesTransferred: 0, totalBytes: 0, speedBytesPerSec: 0))
        } else {
            while bytesWritten < fileSize {
                try Task.checkCancellation()
                try transport?.checkConnection()
                
                let remaining = fileSize - bytesWritten
                let thisChunk = min(Int64(chunkSize), remaining)
                bytesWritten += thisChunk
                
                if Task.isCancelled {
                    throw DeviceError.transferCancelled
                }
                
                progress(TransferProgress(bytesTransferred: bytesWritten, totalBytes: fileSize, speedBytesPerSec: 10 * 1024 * 1024))
                await Task.yield()
            }
        }
        
        let destURL = fileSystem.rootDirectory.appendingPathComponent(resolvedPath.replacingOccurrences(of: "^/", with: "", options: .regularExpression))
        try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destURL)
        
        return try await fileSystem.getItem(at: resolvedPath)
    }
    
    func download(
        remotePath: String,
        localURL: URL,
        options: TransferOptions,
        progress: @Sendable @escaping (TransferProgress) -> Void
    ) async throws {
        try transport?.checkConnection()
        
        let item = try await fileSystem.getItem(at: remotePath)
        guard !item.isDirectory else {
            throw DeviceError.invalidPath(path: "Cannot download directory directly with single-file download.")
        }
        
        if FileManager.default.fileExists(atPath: localURL.path) {
            switch options.conflictResolution {
            case .fail:
                throw DeviceError.itemAlreadyExists(path: localURL.path)
            case .overwrite:
                try? FileManager.default.removeItem(at: localURL)
            case .renameWithTimestamp:
                break
            }
        }
        
        let sourceURL = fileSystem.rootDirectory.appendingPathComponent(remotePath.replacingOccurrences(of: "^/", with: "", options: .regularExpression))
        let data = try Data(contentsOf: sourceURL)
        let fileSize = item.size
        let chunkSize = 64 * 1024
        var bytesRead: Int64 = 0
        
        if fileSize == 0 {
            try Task.checkCancellation()
            try transport?.checkConnection()
            progress(TransferProgress(bytesTransferred: 0, totalBytes: 0, speedBytesPerSec: 0))
        } else {
            while bytesRead < fileSize {
                try Task.checkCancellation()
                try transport?.checkConnection()
                
                let remaining = fileSize - bytesRead
                let thisChunk = min(Int64(chunkSize), remaining)
                bytesRead += thisChunk
                
                if Task.isCancelled {
                    throw DeviceError.transferCancelled
                }
                
                progress(TransferProgress(bytesTransferred: bytesRead, totalBytes: fileSize, speedBytesPerSec: 10 * 1024 * 1024))
                await Task.yield()
            }
        }
        
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: localURL)
    }
    
    func downloadDirectory(
        remotePath: String,
        localURL: URL,
        options: TransferOptions,
        progress: @Sendable @escaping (TransferProgress) -> Void
    ) async throws {
        try transport?.checkConnection()
        let item = try await fileSystem.getItem(at: remotePath)
        guard item.isDirectory else {
            throw DeviceError.invalidPath(path: "downloadDirectory called on non-directory.")
        }
        
        if FileManager.default.fileExists(atPath: localURL.path) {
            switch options.conflictResolution {
            case .fail:
                throw DeviceError.itemAlreadyExists(path: localURL.path)
            case .overwrite:
                try? FileManager.default.removeItem(at: localURL)
            case .renameWithTimestamp:
                break
            }
        }
        
        let sourceURL = fileSystem.rootDirectory.appendingPathComponent(remotePath.replacingOccurrences(of: "^/", with: "", options: .regularExpression))
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceURL, to: localURL)
        progress(TransferProgress(bytesTransferred: 1024, totalBytes: 1024, speedBytesPerSec: 10 * 1024 * 1024))
    }
}
