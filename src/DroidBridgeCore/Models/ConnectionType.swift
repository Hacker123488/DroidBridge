import Foundation

/// Represents the physical or simulated communication mechanism used to connect to a device.
public enum ConnectionType: String, Sendable, Codable, CaseIterable {
    /// USB connection using the standard Media Transfer Protocol.
    case usbMTP = "USB (MTP)"
    
    /// USB connection using the Android Debug Bridge socket daemon.
    case usbADB = "USB (ADB)"
    
    /// Local network connection using authorized wireless ADB (Wi-Fi).
    case wirelessADB = "Wireless ADB (Wi-Fi)"
    
    /// In-memory or temporary-folder simulated transport for unit tests and UI previews.
    case simulatedMock = "Simulated Mock Device"
    
    /// True if this connection type is a simulated mock provider rather than physical hardware.
    public var isSimulated: Bool {
        self == .simulatedMock
    }
}
