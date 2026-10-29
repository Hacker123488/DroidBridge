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
}
