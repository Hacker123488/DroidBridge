import Foundation
import Synchronization

private struct ADBTransportState: ~Copyable {
    var isConnected: Bool = false
}

/// Production DeviceTransport implementation communicating with physical Android devices over USB ADB.
public final class ADBDeviceTransport: DeviceTransport, @unchecked Sendable {
    public let deviceID: String
    public let descriptor: DeviceDescriptor
    public let runner: any ADBCommandRunner
    
    private let state = Mutex(ADBTransportState())
    
    public let fileSystem: any DeviceFileSystem
    public let transferService: any TransferService
    
    public var isConnected: Bool {
        get async {
            state.withLock { $0.isConnected }
        }
    }
    
    public init(
        descriptor: DeviceDescriptor,
        runner: any ADBCommandRunner
    ) {
        self.deviceID = descriptor.id
        self.descriptor = descriptor
        self.runner = runner
        
        let fs = ADBFileSystem(serial: descriptor.id, runner: runner, transport: nil)
        let ts = ADBTransferService(serial: descriptor.id, runner: runner, fileSystem: fs, transport: nil)
        
        self.fileSystem = fs
        self.transferService = ts
        
        fs.transport = self
        ts.transport = self
    }
    
    public func connect() async throws {
        // Query ADB devices to check current authorization and state
        let result = try await runner.run(arguments: ["devices", "-l"], timeout: 5.0)
        guard result.isSuccess else {
            throw DeviceError.connectionFailed(reason: "adb devices command failed: \(result.stderr)")
        }
        
        let devices = ADBDeviceDiscoveryService.parseDevicesOutput(result.stdout)
        guard let current = devices.first(where: { $0.id == deviceID }) else {
            throw DeviceError.deviceDisconnected(deviceID: deviceID)
        }
        
        switch current.status {
        case .available:
            state.withLock { $0.isConnected = true }
        case .unauthorized(let msg):
            throw DeviceError.permissionDenied(path: "\(deviceID): \(msg)")
        case .error(let msg):
            throw DeviceError.connectionFailed(reason: "\(deviceID): \(msg)")
        default:
            throw DeviceError.connectionFailed(reason: "Device '\(deviceID)' is in an unready state.")
        }
    }
    
    public func disconnect() async {
        state.withLock { $0.isConnected = false }
    }
}
