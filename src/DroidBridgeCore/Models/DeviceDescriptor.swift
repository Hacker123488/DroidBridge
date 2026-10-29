import Foundation

/// High-level status of an identified Android device.
public enum DeviceStatus: Sendable, Codable, Equatable {
    case available
    case connecting
    case connected
    case busy(description: String)
    case unauthorized(message: String)
    case disconnected
    case error(message: String)
}

/// Identifies and describes a physical or simulated Android device.
public struct DeviceDescriptor: Identifiable, Sendable, Codable, Equatable {
    /// Unique identifier (e.g. USB serial number, ADB device ID, or simulated GUID).
    public let id: String
    
    /// User-friendly name (e.g. "Google Pixel 9 Pro").
    public let name: String
    
    /// Device model string (e.g. "Pixel 9 Pro").
    public let model: String
    
    /// Connection mechanism.
    public let connectionType: ConnectionType
    
    /// Explicit flag indicating whether this is a simulated device for testing or development.
    /// Never present mock data as a real device.
    public let isSimulated: Bool
    
    /// Current connection and availability status.
    public var status: DeviceStatus
    
    public init(
        id: String,
        name: String,
        model: String,
        connectionType: ConnectionType,
        isSimulated: Bool = false,
        status: DeviceStatus = .available
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.connectionType = connectionType
        self.isSimulated = isSimulated
        self.status = status
    }
}
