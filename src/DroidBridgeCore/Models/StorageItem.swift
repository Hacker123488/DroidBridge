import Foundation

/// Read/write permissions for a storage entry.
public struct StoragePermissions: Sendable, Codable, Equatable {
    public let canRead: Bool
    public let canWrite: Bool
    public let canDelete: Bool
    
    public init(canRead: Bool = true, canWrite: Bool = true, canDelete: Bool = true) {
        self.canRead = canRead
        self.canWrite = canWrite
        self.canDelete = canDelete
    }
    
    public static let full = StoragePermissions(canRead: true, canWrite: true, canDelete: true)
    public static let readOnly = StoragePermissions(canRead: true, canWrite: false, canDelete: false)
}

/// Represents a file or directory on the device storage.
public struct StorageItem: Identifiable, Sendable, Codable, Equatable {
    /// Unique item identifier (MTP handle or canonical path).
    public let id: String
    
    /// Entry filename or folder name.
    public let name: String
    
    /// Canonical POSIX path on the device (e.g. "/sdcard/Download/document.pdf").
    public let path: String
    
    /// File size in bytes (0 for directories).
    public let size: Int64
    
    /// Last modified date.
    public let modifiedDate: Date
    
    /// Indicates whether this item is a directory.
    public let isDirectory: Bool
    
    /// Read/write/delete permissions.
    public let permissions: StoragePermissions
    
    public init(
        id: String,
        name: String,
        path: String,
        size: Int64,
        modifiedDate: Date,
        isDirectory: Bool,
        permissions: StoragePermissions = .full
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.modifiedDate = modifiedDate
        self.isDirectory = isDirectory
        self.permissions = permissions
    }
    
    /// Type of media file (audio, video, or none).
    public var mediaType: MediaType {
        guard !isDirectory else { return .none }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "mp3", "m4a", "wav", "aac", "flac", "ogg", "aiff", "alac", "wma":
            return .audio
        case "mp4", "mov", "m4v", "mkv", "webm", "avi", "3gp", "wmv", "flv":
            return .video
        default:
            return .none
        }
    }
    
    /// Indicates whether this item is an audio or video file.
    public var isMedia: Bool {
        return mediaType != .none
    }
}

/// Category of media file for preview and playback routing.
public enum MediaType: String, Sendable, Codable {
    case audio
    case video
    case none
}
