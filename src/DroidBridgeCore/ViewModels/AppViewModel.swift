import Foundation
import SwiftUI
import AppKit
import Observation

@Observable
@MainActor
public final class AppViewModel {
    public var devices: [DeviceDescriptor] = []
    public var selectedDevice: DeviceDescriptor?
    public var storageItems: [StorageItem] = []
    public var currentPath: String = "/sdcard"
    public var statusMessage: String = "Ready"
    public var isDevMockEnabled: Bool = true
    public var activeTransport: (any DeviceTransport)?
    public var isTransferring: Bool = false
    public var transferProgressFraction: Double = 0.0
    public var transferStatusText: String = ""
    public var lastError: String?
    
    private var activeTransferTask: Task<Void, Never>?
    public let connectionManager: ConnectionManager
    
    public init(connectionManager: ConnectionManager = ConnectionManager()) {
        self.connectionManager = connectionManager
    }
    
    public func loadDevices(adbRunner: (any ADBCommandRunner)? = nil) async {
        let adbDiscovery: ADBDeviceDiscoveryService
        if let runner = adbRunner {
            adbDiscovery = ADBDeviceDiscoveryService(runner: runner)
        } else {
            adbDiscovery = ADBDeviceDiscoveryService()
        }
        let mockDiscovery = MockDeviceDiscoveryService(enableSimulatedDevices: isDevMockEnabled)
        let composite = CompositeDeviceDiscoveryService(adbDiscovery: adbDiscovery, mockDiscovery: mockDiscovery)
        devices = await composite.availableDevices()
        if selectedDevice == nil, let first = devices.first {
            selectedDevice = first
            await connectToDevice(first)
        }
    }
    
    public func connectToDevice(_ device: DeviceDescriptor) async {
        statusMessage = "Connecting to \(device.name)..."
        lastError = nil
        do {
            let transport = try await connectionManager.connect(to: device)
            self.activeTransport = transport
            self.selectedDevice = device
            self.statusMessage = "Connected (\(device.name))"
            await navigateTo("/sdcard")
        } catch {
            self.statusMessage = "Connection failed: \(error.localizedDescription)"
            self.lastError = error.localizedDescription
        }
    }
    
    public func navigateTo(_ path: String) async {
        guard let transport = activeTransport else { return }
        do {
            storageItems = try await transport.fileSystem.listDirectory(at: path)
            currentPath = path
        } catch {
            statusMessage = "Error opening \(path): \(error.localizedDescription)"
            lastError = error.localizedDescription
        }
    }
    
    public func navigateUp() async {
        let parent = (currentPath as NSString).deletingLastPathComponent
        let target = parent.isEmpty ? "/" : parent
        await navigateTo(target)
    }
    
    public func upload(localURL: URL) async {
        guard let transport = activeTransport, let device = selectedDevice else {
            statusMessage = "Cannot upload: No device connected."
            lastError = "No device connected."
            return
        }
        guard !isTransferring else {
            statusMessage = "Transfer already in progress."
            return
        }
        
        isTransferring = true
        transferProgressFraction = 0.0
        transferStatusText = "Uploading \(localURL.lastPathComponent)..."
        statusMessage = "Uploading \(localURL.lastPathComponent) to \(currentPath)..."
        lastError = nil
        
        let targetDir = currentPath
        let task = Task { [weak self, transport, device] in
            do {
                _ = try await transport.transferService.upload(
                    localURL: localURL,
                    remotePath: targetDir,
                    options: TransferOptions(conflictResolution: .renameWithTimestamp),
                    progress: { [weak self] prog in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            let frac = prog.totalBytes > 0 ? Double(prog.bytesTransferred) / Double(prog.totalBytes) : 0.0
                            self.transferProgressFraction = frac
                            let transferredStr = ByteCountFormatter.string(fromByteCount: prog.bytesTransferred, countStyle: .file)
                            let totalStr = ByteCountFormatter.string(fromByteCount: prog.totalBytes, countStyle: .file)
                            self.transferStatusText = "Uploading: \(transferredStr) / \(totalStr)"
                        }
                    }
                )
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.isTransferring = false
                    self.transferProgressFraction = 1.0
                    self.statusMessage = "Uploaded \(localURL.lastPathComponent) successfully to \(device.name)."
                    self.transferStatusText = "Upload complete."
                }
                
                await self?.navigateTo(targetDir)
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.isTransferring = false
                    self.statusMessage = "Upload cancelled."
                    self.transferStatusText = "Cancelled."
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.isTransferring = false
                    self.lastError = error.localizedDescription
                    self.statusMessage = "Upload failed: \(error.localizedDescription)"
                    self.transferStatusText = "Upload failed."
                }
            }
        }
        
        activeTransferTask = task
        await task.value
    }
    
    public func download(item: StorageItem, to destinationURL: URL) async {
        guard let transport = activeTransport, let device = selectedDevice else {
            statusMessage = "Cannot download: No device connected."
            lastError = "No device connected."
            return
        }
        guard !isTransferring else {
            statusMessage = "Transfer already in progress."
            return
        }
        guard !item.isDirectory else {
            statusMessage = "Cannot download a directory directly."
            lastError = "Cannot download a directory directly."
            return
        }
        
        isTransferring = true
        transferProgressFraction = 0.0
        transferStatusText = "Downloading \(item.name)..."
        statusMessage = "Downloading \(item.name) from \(device.name)..."
        lastError = nil
        
        let task = Task { [weak self, transport, device] in
            do {
                try await transport.transferService.download(
                    remotePath: item.path,
                    localURL: destinationURL,
                    options: TransferOptions(conflictResolution: .overwrite),
                    progress: { [weak self] prog in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            let frac = prog.totalBytes > 0 ? Double(prog.bytesTransferred) / Double(prog.totalBytes) : 0.0
                            self.transferProgressFraction = frac
                            let transferredStr = ByteCountFormatter.string(fromByteCount: prog.bytesTransferred, countStyle: .file)
                            let totalStr = ByteCountFormatter.string(fromByteCount: prog.totalBytes, countStyle: .file)
                            self.transferStatusText = "Downloading: \(transferredStr) / \(totalStr)"
                        }
                    }
                )
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.isTransferring = false
                    self.transferProgressFraction = 1.0
                    self.statusMessage = "Downloaded \(item.name) successfully from \(device.name)."
                    self.transferStatusText = "Download complete."
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.isTransferring = false
                    self.statusMessage = "Download cancelled."
                    self.transferStatusText = "Cancelled."
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.isTransferring = false
                    self.lastError = error.localizedDescription
                    self.statusMessage = "Download failed: \(error.localizedDescription)"
                    self.transferStatusText = "Download failed."
                }
            }
        }
        
        activeTransferTask = task
        await task.value
    }
    
    public func cancelTransfer() {
        activeTransferTask?.cancel()
        activeTransferTask = nil
        isTransferring = false
        statusMessage = "Transfer cancelled by user."
        transferStatusText = "Cancelled."
    }
    
    public func promptAndUpload() {
        guard activeTransport != nil, !isTransferring else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Upload"
        panel.message = "Choose a file to upload to \(currentPath)"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await upload(localURL: url)
            }
        }
    }
    
    public func promptAndDownload(item: StorageItem) {
        guard activeTransport != nil, !isTransferring, !item.isDirectory else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.prompt = "Download"
        panel.message = "Choose destination for \(item.name)"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await download(item: item, to: url)
            }
        }
    }
}
