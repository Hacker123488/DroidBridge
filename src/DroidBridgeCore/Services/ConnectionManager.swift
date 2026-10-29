import Foundation

/// Manages active device connections, session lifecycles, and device switching.
public actor ConnectionManager: ConnectionManagerProtocol {
    private var activeTransports: [String: any DeviceTransport] = [:]
    private var mockTransportFactory: (@Sendable (DeviceDescriptor) -> any DeviceTransport)?
    
    public init(
        mockTransportFactory: (@Sendable (DeviceDescriptor) -> any DeviceTransport)? = nil
    ) {
        self.mockTransportFactory = mockTransportFactory
    }
    
    public func connectedDevices() async -> [DeviceDescriptor] {
        var result: [DeviceDescriptor] = []
        for (_, transport) in activeTransports {
            if await transport.isConnected {
                result.append(transport.descriptor)
            }
        }
        return result
    }
    
    public func connect(to device: DeviceDescriptor) async throws -> any DeviceTransport {
        if let existing = activeTransports[device.id] {
            if await existing.isConnected {
                return existing
            }
        }
        
        let transport: any DeviceTransport
        if device.isSimulated {
            if let customFactory = mockTransportFactory {
                transport = customFactory(device)
            } else {
                transport = MockDeviceTransport(
                    deviceID: device.id,
                    deviceName: device.name,
                    model: device.model
                )
            }
        } else {
            // Milestone 1: Physical MTP / ADB transports are not yet implemented
            throw DeviceError.unsupportedOperation(
                "Physical transport for \(device.connectionType.rawValue) is not yet implemented in Milestone 1."
            )
        }
        
        try await transport.connect()
        activeTransports[device.id] = transport
        return transport
    }
    
    public func disconnect(deviceID: String) async {
        guard let transport = activeTransports.removeValue(forKey: deviceID) else { return }
        await transport.disconnect()
    }
    
    public func disconnectAll() async {
        for (_, transport) in activeTransports {
            await transport.disconnect()
        }
        activeTransports.removeAll()
    }
    
    public func transport(for deviceID: String) async -> (any DeviceTransport)? {
        activeTransports[deviceID]
    }
}
