import Foundation

/// Low-level transport connection interface to an Android device.
public protocol DeviceTransport: AnyObject, Sendable {
    /// Unique identifier for this transport instance/device.
    var deviceID: String { get }
    
    /// Metadata descriptor for the device.
    var descriptor: DeviceDescriptor { get }
    
    /// Current connection status.
    var isConnected: Bool { get async }
    
    /// Establishes the physical or simulated transport link.
    func connect() async throws
    
    /// Cleanly closes the transport link.
    func disconnect() async
    
    /// Access to the filesystem provider driven by this transport.
    var fileSystem: any DeviceFileSystem { get }
    
    /// Access to the bidirectional data transfer service.
    var transferService: any TransferService { get }
}
