import Foundation

/// Bidirectional data transfer interface between local macOS filesystem and Android device storage.
public protocol TransferService: Sendable {
    /// Uploads a file from local macOS storage to Android device storage.
    /// - Parameters:
    ///   - localURL: Local file URL on macOS.
    ///   - remotePath: Target directory or file path on the device.
    ///   - options: Conflict resolution and verification settings.
    ///   - progress: Callback periodically reporting progress during transfer.
    /// - Returns: Newly created or updated storage item metadata on the device.
    func upload(
        localURL: URL,
        remotePath: String,
        options: TransferOptions,
        progress: @Sendable @escaping (TransferProgress) -> Void
    ) async throws -> StorageItem
    
    /// Downloads a file from Android device storage to local macOS storage.
    /// - Parameters:
    ///   - remotePath: File path on the device.
    ///   - localURL: Target local file destination on macOS.
    ///   - options: Conflict resolution and verification settings.
    ///   - progress: Callback periodically reporting progress during transfer.
    func download(
        remotePath: String,
        localURL: URL,
        options: TransferOptions,
        progress: @Sendable @escaping (TransferProgress) -> Void
    ) async throws
    
    /// Downloads an entire directory from Android storage to macOS recursively.
    func downloadDirectory(
        remotePath: String,
        localURL: URL,
        options: TransferOptions,
        progress: @Sendable @escaping (TransferProgress) -> Void
    ) async throws
}

public extension TransferService {
    func downloadDirectory(
        remotePath: String,
        localURL: URL,
        options: TransferOptions,
        progress: @Sendable @escaping (TransferProgress) -> Void
    ) async throws {
        throw DeviceError.unsupportedOperation("downloadDirectory is not supported by this transfer service.")
    }
}
