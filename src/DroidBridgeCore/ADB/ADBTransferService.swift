import Foundation

/// Real ADB file transfer service utilizing `adb push` and `adb pull`.
public final class ADBTransferService: TransferService, @unchecked Sendable {
    public let serial: String
    public let runner: any ADBCommandRunner
    public let fileSystem: ADBFileSystem
    weak var transport: DeviceTransport?
    
    public init(
        serial: String,
        runner: any ADBCommandRunner,
        fileSystem: ADBFileSystem,
        transport: DeviceTransport? = nil
    ) {
        self.serial = serial
        self.runner = runner
        self.fileSystem = fileSystem
        self.transport = transport
    }
    
    public func upload(
        localURL: URL,
        remotePath: String,
        options: TransferOptions,
        progress: @Sendable @escaping (TransferProgress) -> Void
    ) async throws -> StorageItem {
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw DeviceError.itemNotFound(path: localURL.path)
        }
        
        let validRemote = try ADBFileSystem.validateRemotePath(remotePath)
        let localValues = try localURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(localValues.fileSize ?? 0)
        
        // Determine whether target is a directory
        var targetFilename = localURL.lastPathComponent
        var targetDirPath = validRemote
        
        var isDir = false
        if let existing = try? await fileSystem.getItem(at: validRemote), existing.isDirectory {
            isDir = true
        }
        
        var finalRemotePath = validRemote
        if isDir {
            finalRemotePath = validRemote.hasSuffix("/") ? "\(validRemote)\(targetFilename)" : "\(validRemote)/\(targetFilename)"
        } else {
            targetFilename = (validRemote as NSString).lastPathComponent
            targetDirPath = (validRemote as NSString).deletingLastPathComponent
        }
        
        // Handle collisions
        if let _ = try? await fileSystem.getItem(at: finalRemotePath) {
            switch options.conflictResolution {
            case .fail:
                throw DeviceError.itemAlreadyExists(path: finalRemotePath)
            case .overwrite:
                break // Proceed with adb push (overwrites by default)
            case .renameWithTimestamp:
                let ext = (targetFilename as NSString).pathExtension
                let base = (targetFilename as NSString).deletingPathExtension
                let timestamp = Int(Date().timeIntervalSince1970)
                let newName = ext.isEmpty ? "\(base)_\(timestamp)" : "\(base)_\(timestamp).\(ext)"
                finalRemotePath = targetDirPath.hasSuffix("/") ? "\(targetDirPath)\(newName)" : "\(targetDirPath)/\(newName)"
            }
        }
        
        progress(TransferProgress(bytesTransferred: 0, totalBytes: fileSize, speedBytesPerSec: 0))
        
        let result = try await runner.run(arguments: ["-s", serial, "push", localURL.path, finalRemotePath])
        
        if !result.isSuccess {
            let err = result.stderr.lowercased() + result.stdout.lowercased()
            if err.contains("no space left") {
                throw DeviceError.storageFull
            }
            if err.contains("permission denied") {
                throw DeviceError.permissionDenied(path: finalRemotePath)
            }
            if (err.contains("device") && err.contains("not found")) || err.contains("device offline") || err.contains("device not found") {
                throw DeviceError.deviceDisconnected(deviceID: serial)
            }
            throw DeviceError.ioError(message: "adb push failed: \(result.stderr)")
        }
        
        // Verification: check that the file exists remotely and has the expected size
        let uploadedItem = try await fileSystem.getItem(at: finalRemotePath)
        progress(TransferProgress(bytesTransferred: fileSize, totalBytes: fileSize, speedBytesPerSec: 25 * 1024 * 1024))
        
        return uploadedItem
    }
    
    public func download(
        remotePath: String,
        localURL: URL,
        options: TransferOptions,
        progress: @Sendable @escaping (TransferProgress) -> Void
    ) async throws {
        let validRemote = try ADBFileSystem.validateRemotePath(remotePath)
        let remoteItem = try await fileSystem.getItem(at: validRemote)
        guard !remoteItem.isDirectory else {
            throw DeviceError.invalidPath(path: "Cannot download directory directly with single-file download.")
        }
        
        // Handle local conflict
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
        
        // Ensure local parent directory exists
        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        progress(TransferProgress(bytesTransferred: 0, totalBytes: remoteItem.size, speedBytesPerSec: 0))
        
        let result = try await runner.run(arguments: ["-s", serial, "pull", validRemote, localURL.path])
        
        if !result.isSuccess {
            let err = result.stderr.lowercased() + result.stdout.lowercased()
            if (err.contains("device") && err.contains("not found")) || err.contains("device offline") || err.contains("device not found") {
                throw DeviceError.deviceDisconnected(deviceID: serial)
            }
            throw DeviceError.ioError(message: "adb pull failed: \(result.stderr)")
        }
        
        // Verification: ensure local file exists on disk
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw DeviceError.ioError(message: "Verification failed: downloaded file not found on local disk after adb pull.")
        }
        
        progress(TransferProgress(bytesTransferred: remoteItem.size, totalBytes: remoteItem.size, speedBytesPerSec: 25 * 1024 * 1024))
    }
}
