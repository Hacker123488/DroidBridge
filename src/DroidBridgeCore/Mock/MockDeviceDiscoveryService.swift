import Foundation
import Synchronization

private struct DiscoveryState: ~Copyable {
    var isDiscovering: Bool = false
    var simulatedDevices: [DeviceDescriptor] = []
}

/// Device discovery service providing simulated devices for development and unit testing.
/// Mock devices are never exposed in production unless explicitly enabled.
public final class MockDeviceDiscoveryService: DeviceDiscoveryService, @unchecked Sendable {
    private let state: Mutex<DiscoveryState>
    
    /// Global or instance guard: must be explicitly set to true to expose simulated devices.
    public let enableSimulatedDevices: Bool
    
    private let continuationLock = Mutex<AsyncStream<[DeviceDescriptor]>.Continuation?>(nil)
    
    public var isDiscovering: Bool {
        get async {
            state.withLock { $0.isDiscovering }
        }
    }
    
    public var deviceUpdates: AsyncStream<[DeviceDescriptor]> {
        AsyncStream { continuation in
            continuationLock.withLock { c in
                c = continuation
            }
            let current = self.availableDevicesSync()
            continuation.yield(current)
        }
    }
    
    public init(enableSimulatedDevices: Bool = false) {
        self.enableSimulatedDevices = enableSimulatedDevices
        var initialDevices: [DeviceDescriptor] = []
        if enableSimulatedDevices {
            initialDevices = [
                DeviceDescriptor(
                    id: "SIM-DEV-PIXEL9",
                    name: "[SIMULATED] Google Pixel 9 Pro (Mock)",
                    model: "Pixel 9 Pro",
                    connectionType: .simulatedMock,
                    isSimulated: true,
                    status: .available
                ),
                DeviceDescriptor(
                    id: "SIM-DEV-GALAXY24",
                    name: "[SIMULATED] Samsung Galaxy S24 Ultra (Mock)",
                    model: "SM-S928B",
                    connectionType: .simulatedMock,
                    isSimulated: true,
                    status: .available
                )
            ]
        }
        self.state = Mutex(DiscoveryState(isDiscovering: false, simulatedDevices: initialDevices))
    }
    
    public func startDiscovery() async throws {
        let list = state.withLock { s -> [DeviceDescriptor] in
            s.isDiscovering = true
            return enableSimulatedDevices ? s.simulatedDevices : []
        }
        _ = continuationLock.withLock { c in
            c?.yield(list)
        }
    }
    
    public func stopDiscovery() async {
        state.withLock { s in
            s.isDiscovering = false
        }
    }
    
    public func availableDevices() async -> [DeviceDescriptor] {
        availableDevicesSync()
    }
    
    private func availableDevicesSync() -> [DeviceDescriptor] {
        guard enableSimulatedDevices else {
            return [] // Mock functionality strictly disabled when enableSimulatedDevices is false
        }
        return state.withLock { $0.simulatedDevices }
    }
    
    /// Test helper to simulate dynamically plugging in a new mock device.
    public func simulateDevicePlugged(device: DeviceDescriptor) {
        guard enableSimulatedDevices, device.isSimulated else { return }
        let list = state.withLock { s -> [DeviceDescriptor] in
            s.simulatedDevices.removeAll { $0.id == device.id }
            s.simulatedDevices.append(device)
            return s.simulatedDevices
        }
        _ = continuationLock.withLock { c in
            c?.yield(list)
        }
    }
    
    /// Test helper to simulate dynamically unplugging a mock device.
    public func simulateDeviceUnplugged(deviceID: String) {
        guard enableSimulatedDevices else { return }
        let list = state.withLock { s -> [DeviceDescriptor] in
            s.simulatedDevices.removeAll { $0.id == deviceID }
            return s.simulatedDevices
        }
        _ = continuationLock.withLock { c in
            c?.yield(list)
        }
    }
}
