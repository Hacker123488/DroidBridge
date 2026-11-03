import Foundation
import Synchronization

/// Discovery service that aggregates real physical ADB devices, MTP devices, and optional simulated mock devices.
public final class CompositeDeviceDiscoveryService: DeviceDiscoveryService, @unchecked Sendable {
    public let adbDiscovery: ADBDeviceDiscoveryService
    public let mtpDiscovery: (any DeviceDiscoveryService)?
    public let mockDiscovery: MockDeviceDiscoveryService
    
    private let continuationLock = Mutex<AsyncStream<[DeviceDescriptor]>.Continuation?>(nil)
    private let observationTaskLock = Mutex<Task<Void, Never>?>(nil)
    
    public var isDiscovering: Bool {
        get async {
            let adbActive = await adbDiscovery.isDiscovering
            let mtpActive = await (mtpDiscovery?.isDiscovering ?? false)
            let mockActive = await mockDiscovery.isDiscovering
            return adbActive || mtpActive || mockActive
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
        mtpDiscovery: (any DeviceDiscoveryService)? = nil,
        mockDiscovery: MockDeviceDiscoveryService = MockDeviceDiscoveryService(enableSimulatedDevices: false)
    ) {
        self.adbDiscovery = adbDiscovery
        self.mtpDiscovery = mtpDiscovery
        self.mockDiscovery = mockDiscovery
    }
    
    public func startDiscovery() async throws {
        try? await adbDiscovery.startDiscovery()
        try? await mtpDiscovery?.startDiscovery()
        try await mockDiscovery.startDiscovery()
        
        // Start observing downstream MTP and ADB updates to publish aggregated changes
        startSubServiceObservation()
        
        let devices = await availableDevices()
        _ = continuationLock.withLock { c in
            c?.yield(devices)
        }
    }
    
    public func stopDiscovery() async {
        stopSubServiceObservation()
        await adbDiscovery.stopDiscovery()
        await mtpDiscovery?.stopDiscovery()
        await mockDiscovery.stopDiscovery()
    }
    
    public func availableDevices() async -> [DeviceDescriptor] {
        let realADB = await adbDiscovery.availableDevices()
        let realMTP = await (mtpDiscovery?.availableDevices() ?? [])
        let mockDevices = await mockDiscovery.availableDevices()
        return DeviceCorrelationManager.correlate(
            adbDevices: realADB,
            mtpDevices: realMTP,
            mockDevices: mockDevices
        )
    }
    
    private func startSubServiceObservation() {
        stopSubServiceObservation()
        guard let mtp = mtpDiscovery else { return }
        
        let task = Task { [weak self, mtp] in
            for await _ in mtp.deviceUpdates {
                guard let self = self else { break }
                let current = await self.availableDevices()
                _ = self.continuationLock.withLock { c in
                    c?.yield(current)
                }
            }
        }
        observationTaskLock.withLock { $0 = task }
    }
    
    private func stopSubServiceObservation() {
        observationTaskLock.withLock { task in
            task?.cancel()
            task = nil
        }
    }
}
