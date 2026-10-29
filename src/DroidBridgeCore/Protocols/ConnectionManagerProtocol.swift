import Foundation

/// Coordinates active device transport connections, device switching, and session lifecycles.
public protocol ConnectionManagerProtocol: Sendable {
    /// Currently connected devices.
    func connectedDevices() async -> [DeviceDescriptor]
    
    /// Connects to a target device using its appropriate transport.
    func connect(to device: DeviceDescriptor) async throws -> any DeviceTransport
    
    /// Disconnects from an active device session.
    func disconnect(deviceID: String) async
    
    /// Disconnects all active device sessions.
    func disconnectAll() async
    
    /// Retrieves the active transport for a connected device ID.
    func transport(for deviceID: String) async -> (any DeviceTransport)?
}
