import Foundation

/// Standardized error types thrown by device transports, filesystems, and transfer operations.
public enum DeviceError: Error, LocalizedError, Sendable, Equatable {
    case deviceDisconnected(deviceID: String)
    case notConnected
    case alreadyConnected
    case connectionFailed(reason: String)
    case transferCancelled
    case itemNotFound(path: String)
    case itemAlreadyExists(path: String)
    case invalidPath(path: String)
    case pathTraversalForbidden(path: String)
    case permissionDenied(path: String)
    case ioError(message: String)
    case unsupportedOperation(String)
    case storageFull
    
    public var errorDescription: String? {
        switch self {
        case .deviceDisconnected(let deviceID):
            return "Device '\(deviceID)' disconnected unexpectedly."
        case .notConnected:
            return "Device is not connected."
        case .alreadyConnected:
            return "Device is already connected."
        case .connectionFailed(let reason):
            return "Failed to establish device connection: \(reason)"
        case .transferCancelled:
            return "Transfer operation was cancelled."
        case .itemNotFound(let path):
            return "Item not found at path: \(path)"
        case .itemAlreadyExists(let path):
            return "An item already exists at path: \(path)"
        case .invalidPath(let path):
            return "Invalid path provided: \(path)"
        case .pathTraversalForbidden(let path):
            return "Security violation: Path traversal outside root storage is forbidden: \(path)"
        case .permissionDenied(let path):
            return "Permission denied for operation at path: \(path)"
        case .ioError(let message):
            return "I/O Error: \(message)"
        case .unsupportedOperation(let message):
            return "Unsupported operation: \(message)"
        case .storageFull:
            return "Insufficient free storage space on target device."
        }
    }
}
