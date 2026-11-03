import Foundation

/// High-level filesystem abstraction for navigating and mutating items on an Android device.
public protocol DeviceFileSystem: Sendable {
    /// Lists all items contained within the specified directory path.
    /// - Parameter path: Canonical POSIX path on the device (e.g. "/" or "/sdcard").
    func listDirectory(at path: String) async throws -> [StorageItem]
    
    /// Retrieves metadata for a specific file or folder.
    func getItem(at path: String) async throws -> StorageItem
    
    /// Creates a new directory at the specified target path.
    func createDirectory(at path: String, name: String) async throws -> StorageItem
    
    /// Deletes a file or directory at the given path.
    func deleteItem(at path: String, isRecursive: Bool) async throws
    
    /// Renames an existing item.
    func renameItem(at path: String, newName: String) async throws -> StorageItem
    
    /// Moves an existing item from source path to destination path.
    func moveItem(from sourcePath: String, to destinationPath: String) async throws -> StorageItem
    
    /// Copies an existing item from source path to destination path.
    func copyItem(from sourcePath: String, to destinationPath: String) async throws -> StorageItem
}

public extension DeviceFileSystem {
    func moveItem(from sourcePath: String, to destinationPath: String) async throws -> StorageItem {
        let newName = (destinationPath as NSString).lastPathComponent
        return try await renameItem(at: sourcePath, newName: newName)
    }
    
    func copyItem(from sourcePath: String, to destinationPath: String) async throws -> StorageItem {
        throw DeviceError.unsupportedOperation("copyItem is not implemented for this transport.")
    }
}
