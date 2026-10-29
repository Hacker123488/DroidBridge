import Foundation

/// Direction of data movement.
public enum TransferDirection: String, Sendable, Codable {
    case macToAndroid = "Host to Android"
    case androidToMac = "Android to Host"
}

/// Policy when an item with the same name already exists at the destination.
public enum ConflictResolutionPolicy: String, Sendable, Codable {
    case fail = "Fail"
    case overwrite = "Overwrite"
    case renameWithTimestamp = "Rename"
}

/// Options configured for a transfer job.
public struct TransferOptions: Sendable, Codable, Equatable {
    public let conflictResolution: ConflictResolutionPolicy
    public let verifyChecksum: Bool
    
    public init(
        conflictResolution: ConflictResolutionPolicy = .fail,
        verifyChecksum: Bool = false
    ) {
        self.conflictResolution = conflictResolution
        self.verifyChecksum = verifyChecksum
    }
    
    public static let `default` = TransferOptions()
}

/// Real-time progress report emitted during active file transfer.
public struct TransferProgress: Sendable, Equatable {
    public let bytesTransferred: Int64
    public let totalBytes: Int64
    public let fractionCompleted: Double
    public let speedBytesPerSec: Double
    
    public init(
        bytesTransferred: Int64,
        totalBytes: Int64,
        speedBytesPerSec: Double = 0
    ) {
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.fractionCompleted = totalBytes > 0 ? Double(bytesTransferred) / Double(totalBytes) : 0
        self.speedBytesPerSec = speedBytesPerSec
    }
}

/// Lifecycle state of an individual transfer job.
public enum TransferJobState: Sendable, Equatable {
    case pending
    case inProgress(fractionCompleted: Double, speedBytesPerSec: Double)
    case paused(fractionCompleted: Double)
    case completed
    case cancelled
    case failed(message: String)
}

/// Model representing a queued or active transfer job.
public struct TransferJob: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let direction: TransferDirection
    public let localURL: URL
    public let remotePath: String
    public let size: Int64
    public var state: TransferJobState
    public let options: TransferOptions
    public let createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        direction: TransferDirection,
        localURL: URL,
        remotePath: String,
        size: Int64,
        state: TransferJobState = .pending,
        options: TransferOptions = .default,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.direction = direction
        self.localURL = localURL
        self.remotePath = remotePath
        self.size = size
        self.state = state
        self.options = options
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
