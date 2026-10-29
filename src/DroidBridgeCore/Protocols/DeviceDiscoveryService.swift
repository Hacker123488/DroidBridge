import Foundation

/// Service interface responsible for observing attached or network-accessible Android devices.
public protocol DeviceDiscoveryService: Sendable {
    /// Indicates whether discovery scanning is currently active.
    var isDiscovering: Bool { get async }
    
    /// Starts observing device arrival and departure.
    func startDiscovery() async throws
    
    /// Stops observing devices.
    func stopDiscovery() async
    
    /// Returns the currently available device list.
    func availableDevices() async -> [DeviceDescriptor]
    
    /// Asynchronous stream of discovered device updates.
    var deviceUpdates: AsyncStream<[DeviceDescriptor]> { get }
}
