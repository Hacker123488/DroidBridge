import Foundation

/// Defines clipboard action for Android items.
public enum ClipboardOperation: String, Codable, Sendable {
    case copy
    case cut
}

/// Representation of an Android storage item on the clipboard.
public struct ClipboardItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { remotePath }
    public let name: String
    public let remotePath: String
    public let isDirectory: Bool
    public let size: Int64
    public let deviceID: String
    
    public init(name: String, remotePath: String, isDirectory: Bool, size: Int64, deviceID: String) {
        self.name = name
        self.remotePath = remotePath
        self.isDirectory = isDirectory
        self.size = size
        self.deviceID = deviceID
    }
    
    public init(storageItem: StorageItem, deviceID: String) {
        self.name = storageItem.name
        self.remotePath = storageItem.path
        self.isDirectory = storageItem.isDirectory
        self.size = storageItem.size
        self.deviceID = deviceID
    }
}

/// JSON-serializable payload written to system pasteboard for Android remote items.
public struct AndroidClipboardPayload: Codable, Sendable, Equatable {
    public let operation: ClipboardOperation
    public let deviceID: String
    public let items: [ClipboardItem]
    
    public init(operation: ClipboardOperation, deviceID: String, items: [ClipboardItem]) {
        self.operation = operation
        self.deviceID = deviceID
        self.items = items
    }
    
    public static let pasteboardTypeString = "com.droidbridge.android-items"
    
    public func serialize() -> Data? {
        try? JSONEncoder().encode(self)
    }
    
    public static func deserialize(from data: Data) -> AndroidClipboardPayload? {
        try? JSONDecoder().decode(AndroidClipboardPayload.self, from: data)
    }
}

// MARK: - Global UI Command Notifications

extension Notification.Name {
    public static let droidBridgeCopy = Notification.Name("droidBridgeCopy")
    public static let droidBridgeCut = Notification.Name("droidBridgeCut")
    public static let droidBridgePaste = Notification.Name("droidBridgePaste")
    public static let droidBridgeSelectAll = Notification.Name("droidBridgeSelectAll")
}
