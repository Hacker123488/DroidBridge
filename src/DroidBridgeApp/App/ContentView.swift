import SwiftUI
import AppKit
import DroidBridgeCore

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
                            .disabled(viewModel.isTransferring)
                        }
                        Button(action: {
                            viewModel.promptAndUpload()
                        }) {
                            Label("Upload File...", systemImage: "arrow.up.circle.fill")
                        }
                        .disabled(viewModel.isTransferring || viewModel.activeTransport == nil)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    if viewModel.isTransferring {
                        VStack(spacing: 4) {
                            HStack {
                                Text(viewModel.transferStatusText)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Spacer()
                                Button("Cancel") {
                                    viewModel.cancelTransfer()
                                }
                                .font(.caption)
                            }
                            ProgressView(value: viewModel.transferProgressFraction)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.08))
                    }
                    
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
                                
                                Button(action: {
                                    viewModel.promptAndDownload(item: item)
                                }) {
                                    Image(systemName: "arrow.down.circle")
                                }
                                .buttonStyle(.borderless)
                                .disabled(viewModel.isTransferring)
                                .help("Download to Mac")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if item.isDirectory {
                                Task { await viewModel.navigateTo(item.path) }
                            }
                        }
                        .contextMenu {
                            if !item.isDirectory {
                                Button {
                                    viewModel.promptAndDownload(item: item)
                                } label: {
                                    Label("Download to Mac...", systemImage: "arrow.down.circle")
                                }
                                .disabled(viewModel.isTransferring)
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
                        .foregroundColor(viewModel.lastError != nil ? .red : .secondary)
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
