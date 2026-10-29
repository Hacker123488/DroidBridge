import SwiftUI
import Observation
import DroidBridgeCore

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
    
    public init() {}
    
    public func loadDevices() async {
        let discovery = MockDeviceDiscoveryService(enableSimulatedDevices: isDevMockEnabled)
        devices = await discovery.availableDevices()
        if selectedDevice == nil, let first = devices.first {
            selectedDevice = first
            await connectToDevice(first)
        }
    }
    
    public func connectToDevice(_ device: DeviceDescriptor) async {
        statusMessage = "Connecting to \(device.name)..."
        let mockTransport = MockDeviceTransport(
            deviceID: device.id,
            deviceName: device.name,
            model: device.model
        )
        do {
            try await mockTransport.connect()
            self.activeTransport = mockTransport
            self.statusMessage = "Connected (\(device.name))"
            await navigateTo("/sdcard")
        } catch {
            self.statusMessage = "Connection failed: \(error.localizedDescription)"
        }
    }
    
    public func navigateTo(_ path: String) async {
        guard let transport = activeTransport else { return }
        do {
            storageItems = try await transport.fileSystem.listDirectory(at: path)
            currentPath = path
        } catch {
            statusMessage = "Error opening \(path): \(error.localizedDescription)"
        }
    }
    
    public func navigateUp() async {
        let parent = (currentPath as NSString).deletingLastPathComponent
        let target = parent.isEmpty ? "/" : parent
        await navigateTo(target)
    }
}

public struct ContentView: View {
    var viewModel = AppViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Devices")
                        .font(.headline)
                    Spacer()
                    Button(viewModel.isDevMockEnabled ? "Mocks: ON" : "Mocks: OFF") {
                        viewModel.isDevMockEnabled.toggle()
                        Task { await viewModel.loadDevices() }
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                
                List(viewModel.devices) { device in
                    HStack {
                        Image(systemName: device.isSimulated ? "desktopcomputer" : "cable.connector")
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.body)
                            Text(device.connectionType.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if device.isSimulated {
                            Spacer()
                            Text("SIMULATED")
                                .font(.system(size: 9, weight: .bold))
                                .padding(3)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedDevice = device
                        Task { await viewModel.connectToDevice(device) }
                    }
                }
                
                Button("Refresh Devices") {
                    Task { await viewModel.loadDevices() }
                }
                .padding()
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(spacing: 0) {
                if let _ = viewModel.selectedDevice {
                    HStack {
                        Text(viewModel.currentPath)
                            .font(.system(.subheadline, design: .monospaced))
                        Spacer()
                        if viewModel.currentPath != "/sdcard" && viewModel.currentPath != "/" {
                            Button("Up") {
                                Task { await viewModel.navigateUp() }
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    List(viewModel.storageItems) { item in
                        HStack {
                            Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                                .foregroundColor(item.isDirectory ? .blue : .primary)
                            Text(item.name)
                            Spacer()
                            if !item.isDirectory {
                                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if item.isDirectory {
                                Task { await viewModel.navigateTo(item.path) }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Android Device Selected")
                            .font(.headline)
                        Text("Connect a device via USB/Wi-Fi or enable Dev Mocks to test simulated devices.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                
                Divider()
                HStack {
                    Text("Status: \(viewModel.statusMessage)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(8)
            }
        }
        .task {
            await viewModel.loadDevices()
        }
    }
}
