import Foundation
import Synchronization

private struct ADBDiscoveryState: ~Copyable {
    var isDiscovering: Bool = false
    var cachedDevices: [DeviceDescriptor] = []
}

/// Service that discovers physical Android devices connected via USB using ADB.
public final class ADBDeviceDiscoveryService: DeviceDiscoveryService, @unchecked Sendable {
    public let runner: any ADBCommandRunner
    private let state = Mutex(ADBDiscoveryState())
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
    
    public init(runner: any ADBCommandRunner) {
        self.runner = runner
    }
    
    public convenience init(configuration: ADBConfiguration = ADBConfiguration()) {
        self.init(runner: ProcessADBCommandRunner(configuration: configuration))
    }
    
    public func startDiscovery() async throws {
        guard await runner.isAvailable() else {
            state.withLock { s in
                s.isDiscovering = false
                s.cachedDevices = []
            }
            throw DeviceError.ioError(message: "ADB is not available on this system.")
        }
        
        state.withLock { s in
            s.isDiscovering = true
        }
        
        let devices = try await fetchConnectedDevices()
        _ = continuationLock.withLock { c in
            c?.yield(devices)
        }
    }
    
    public func stopDiscovery() async {
        state.withLock { s in
            s.isDiscovering = false
        }
    }
    
    public func availableDevices() async -> [DeviceDescriptor] {
        if await runner.isAvailable() {
            if let devices = try? await fetchConnectedDevices() {
                return devices
            }
        }
        return state.withLock { $0.cachedDevices }
    }
    
    private func fetchConnectedDevices() async throws -> [DeviceDescriptor] {
        let result = try await runner.run(arguments: ["devices", "-l"], timeout: 10.0)
        guard result.isSuccess else {
            throw DeviceError.ioError(message: "Failed to list adb devices: \(result.stderr)")
        }
        
        let devices = Self.parseDevicesOutput(result.stdout)
        state.withLock { s in
            s.cachedDevices = devices
        }
        return devices
    }
    
    /// Pure parsing function for `adb devices -l` output.
    public static func parseDevicesOutput(_ output: String) -> [DeviceDescriptor] {
        var devices: [DeviceDescriptor] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty ||
               trimmed.starts(with: "List of devices attached") ||
               trimmed.starts(with: "* daemon") {
                continue
            }
            
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2 else { continue }
            
            let serial = String(parts[0])
            let statusRaw = String(parts[1]).lowercased()
            
            var model = "Android Device"
            var product = ""
            for part in parts.dropFirst(2) {
                let token = String(part)
                if token.hasPrefix("model:") {
                    model = token.replacingOccurrences(of: "model:", with: "").replacingOccurrences(of: "_", with: " ")
                } else if token.hasPrefix("product:") {
                    product = token.replacingOccurrences(of: "product:", with: "")
                }
            }
            
            let displayName: String
            if model != "Android Device" {
                displayName = "\(model) (\(serial))"
            } else if !product.isEmpty {
                displayName = "\(product) (\(serial))"
            } else {
                displayName = "Android Device (\(serial))"
            }
            
            let status: DeviceStatus
            switch statusRaw {
            case "device":
                status = .available
            case "unauthorized":
                status = .unauthorized(message: "Please authorize USB debugging on your Android device screen.")
            case "offline":
                status = .error(message: "Device is offline.")
            case "no", "permissions":
                status = .unauthorized(message: "Missing host USB permissions.")
            default:
                status = .error(message: "Reported state: \(statusRaw)")
            }
            
            devices.append(DeviceDescriptor(
                id: serial,
                name: displayName,
                model: model,
                connectionType: .usbADB,
                isSimulated: false,
                status: status
            ))
        }
        
        return devices
    }
}
