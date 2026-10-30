import Foundation
import Synchronization

/// Discovery service that aggregates real physical ADB devices with optional simulated mock devices.
public final class CompositeDeviceDiscoveryService: DeviceDiscoveryService, @unchecked Sendable {
    public let adbDiscovery: ADBDeviceDiscoveryService
    public let mockDiscovery: MockDeviceDiscoveryService
    
    private let continuationLock = Mutex<AsyncStream<[DeviceDescriptor]>.Continuation?>(nil)
    
    public var isDiscovering: Bool {
        get async {
            let adbActive = await adbDiscovery.isDiscovering
            let mockActive = await mockDiscovery.isDiscovering
            return adbActive || mockActive
        }
    }
    
    public var deviceUpdates: AsyncStream<[DeviceDescriptor]> {
        AsyncStream { continuation in
            continuationLock.withLock { c in
                c = continuation
            }
            Task {
                let current = await self.availableDevices()
                continuation.yield(current)
            }
        }
    }
    
    public init(
        adbDiscovery: ADBDeviceDiscoveryService,
        mockDiscovery: MockDeviceDiscoveryService = MockDeviceDiscoveryService(enableSimulatedDevices: false)
    ) {
        self.adbDiscovery = adbDiscovery
        self.mockDiscovery = mockDiscovery
    }
    
    public func startDiscovery() async throws {
        try? await adbDiscovery.startDiscovery()
        try await mockDiscovery.startDiscovery()
        
        let devices = await availableDevices()
        _ = continuationLock.withLock { c in
            c?.yield(devices)
        }
    }
    
    public func stopDiscovery() async {
        await adbDiscovery.stopDiscovery()
        await mockDiscovery.stopDiscovery()
    }
    
    public func availableDevices() async -> [DeviceDescriptor] {
        let realDevices = await adbDiscovery.availableDevices()
        let mockDevices = await mockDiscovery.availableDevices()
        return realDevices + mockDevices
    }
}
