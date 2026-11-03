import Foundation
import Synchronization

/// Discovery service that observes physical Android devices connected via USB using MTP.
/// Implements passive, zero-open discovery: Never opens or claims USB interfaces.
public final class MTPDeviceDiscoveryService: DeviceDiscoveryService, @unchecked Sendable {
    public let observer: any MTPUSBObserverProtocol
    
    private struct ServiceState: ~Copyable {
        var isDiscovering: Bool = false
        var interfacesByEntryID: [UInt64: MTPUSBInterfaceInfo] = [:]
    }
    
    private let state = Mutex(ServiceState())
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
            Task {
                let current = await self.availableDevices()
                continuation.yield(current)
            }
        }
    }
    
    public init(observer: any MTPUSBObserverProtocol = IOKitMTPUSBObserver()) {
        self.observer = observer
    }
    
    public func startDiscovery() async throws {
        state.withLock { s in
            s.isDiscovering = true
            s.interfacesByEntryID.removeAll()
        }
        
        try observer.startObserving(
            onMatched: { [weak self] info in
                self?.handleInterfaceMatched(info)
            },
            onTerminated: { [weak self] entryID in
                self?.handleInterfaceTerminated(entryID)
            }
        )
        
        let devices = await availableDevices()
        _ = continuationLock.withLock { c in
            c?.yield(devices)
        }
    }
    
    public func stopDiscovery() async {
        state.withLock { s in
            s.isDiscovering = false
            s.interfacesByEntryID.removeAll()
        }
        observer.stopObserving()
        
        _ = continuationLock.withLock { c in
            c?.yield([])
        }
    }
    
    public func availableDevices() async -> [DeviceDescriptor] {
        let interfaces = state.withLock { Array($0.interfacesByEntryID.values) }
        return Self.deduplicateAndConvert(interfaces)
    }
    
    // MARK: - Internal Event Handlers
    
    private func handleInterfaceMatched(_ info: MTPUSBInterfaceInfo) {
        state.withLock { s in
            s.interfacesByEntryID[info.entryID] = info
        }
        publishCurrentDevices()
    }
    
    private func handleInterfaceTerminated(_ entryID: UInt64) {
        state.withLock { s in
            _ = s.interfacesByEntryID.removeValue(forKey: entryID)
        }
        publishCurrentDevices()
    }
    
    private func publishCurrentDevices() {
        let interfaces = state.withLock { Array($0.interfacesByEntryID.values) }
        let devices = Self.deduplicateAndConvert(interfaces)
        _ = continuationLock.withLock { c in
            c?.yield(devices)
        }
    }
    
    /// Converts raw USB interface records into distinct physical `DeviceDescriptor`s,
    /// deduplicating multiple interfaces belonging to the same physical serial number.
    public static func deduplicateAndConvert(_ interfaces: [MTPUSBInterfaceInfo]) -> [DeviceDescriptor] {
        var seenSerials = Set<String>()
        var seenEntryIDs = Set<UInt64>()
        var descriptors: [DeviceDescriptor] = []
        
        for intf in interfaces {
            let serial = intf.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            if !serial.isEmpty {
                if seenSerials.contains(serial) {
                    continue
                }
                seenSerials.insert(serial)
            } else {
                if seenEntryIDs.contains(intf.entryID) {
                    continue
                }
                seenEntryIDs.insert(intf.entryID)
            }
            
            descriptors.append(MTPDeviceIdentity.makeDescriptor(from: intf))
        }
        
        return descriptors
    }
}
