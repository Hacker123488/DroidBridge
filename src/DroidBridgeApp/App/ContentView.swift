import SwiftUI
import AppKit
import AVKit
import QuickLookUI
import UniformTypeIdentifiers
import DroidBridgeCore

public struct ContentView: View {
    @Bindable var viewModel = AppViewModel()
    
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
                        Image(systemName: device.isSimulated ? "desktopcomputer" : (device.connectionType == .usbMTP ? "cable.connector.horizontal" : "cable.connector"))
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
                if let device = viewModel.selectedDevice {
                    if device.connectionType == .usbMTP {
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "cable.connector.horizontal")
                                .font(.system(size: 48))
                                .foregroundColor(.accentColor)
                            Text(device.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("MTP Device Connected")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Native passive USB discovery is active.\nFull file browsing, uploads and downloads will be enabled in Milestone 3.3.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Path Header & Action Toolbar
                        HStack(spacing: 8) {
                            Text(viewModel.currentPath)
                                .font(.system(.subheadline, design: .monospaced))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if viewModel.currentPath != "/sdcard" && viewModel.currentPath != "/" {
                                Button("Up") {
                                    Task { await viewModel.navigateUp() }
                                }
                                .disabled(viewModel.isTransferring)
                            }
                            
                            // Upload Button
                            Button(action: {
                                viewModel.promptAndUpload()
                            }) {
                                Label("Upload...", systemImage: "arrow.up.circle.fill")
                            }
                            .disabled(viewModel.isTransferring || viewModel.activeTransport == nil)
                            
                            // Paste Button
                            Button(action: {
                                Task { await viewModel.paste() }
                            }) {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .disabled(viewModel.isTransferring || viewModel.activeTransport == nil)
                            
                            // Quick Look / Media Preview Toolbar Button
                            if viewModel.selectedItems.count == 1 && !(viewModel.selectedItems.first?.isDirectory ?? true) {
                                let item = viewModel.selectedItems.first!
                                Button(action: {
                                    Task { await viewModel.togglePreview() }
                                }) {
                                    Label(item.isMedia ? "Play" : "Preview", systemImage: item.isMedia ? "play.circle" : "eye")
                                }
                                .help(item.isMedia ? "Play Media Preview (Space)" : "Quick Look Preview (Space)")
                            }
                            
                            // Clear Selection Button (when items selected)
                            if !viewModel.selectedItemIDs.isEmpty {
                                Button(action: {
                                    viewModel.clearSelection()
                                }) {
                                    Label("Clear (\(viewModel.selectedItemIDs.count))", systemImage: "xmark.circle")
                                }
                                .buttonStyle(.bordered)
                                .help("Clear selection (Esc)")
                            }
                            
                            // Delete Button (when items selected)
                            if !viewModel.selectedItemIDs.isEmpty {
                                Button(role: .destructive, action: {
                                    Task { await viewModel.deleteSelectedItems() }
                                }) {
                                    Label("Delete (\(viewModel.selectedItemIDs.count))", systemImage: "trash")
                                }
                                .disabled(viewModel.isTransferring)
                            }
                            
                            // Conflict Resolution Menu
                            Menu {
                                Button("Rename with Timestamp") { viewModel.conflictResolution = .renameWithTimestamp }
                                Button("Overwrite") { viewModel.conflictResolution = .overwrite }
                                Button("Fail / Prompt") { viewModel.conflictResolution = .fail }
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                            }
                            .menuStyle(.borderlessButton)
                            .help("Conflict Resolution: \(viewModel.conflictResolution.rawValue)")
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        
                        // Transfer Progress Banner
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
                        
                        // File Browser with Native Activation, Multi-Selection & Drag & Drop
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                // Parent directory entry (..) when navigated inside a directory
                                if let parentItem = viewModel.parentDirectoryItem {
                                    Button(action: {
                                        let mods = NSEvent.modifierFlags
                                        Task { await viewModel.handleRowClick(parentItem, eventModifiers: mods) }
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "arrow.turn.up.left")
                                                 .foregroundColor(.blue)
                                                 .font(.system(size: 16))
                                            Text("..")
                                                .fontWeight(.semibold)
                                            Text("(Parent Directory)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                        }
                                        .padding(.vertical, 5)
                                        .padding(.horizontal, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                ForEach(viewModel.storageItems) { item in
                                    StorageItemRowView(item: item, viewModel: viewModel)
                                }
                                
                                // Blank Space click target: Clicking empty space clears selection
                                Button(action: {
                                    viewModel.clearSelection()
                                }) {
                                    Color.white.opacity(0.001)
                                        .frame(maxWidth: .infinity, minHeight: 120)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
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
                
                // Status Footer
                HStack {
                    Text("Status: \(viewModel.statusMessage)")
                        .font(.caption)
                        .foregroundColor(viewModel.lastError != nil ? .red : .secondary)
                    Spacer()
                    if !viewModel.selectedItemIDs.isEmpty {
                        Text("\(viewModel.selectedItemIDs.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Deselect All") {
                            viewModel.clearSelection()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                }
                .padding(8)
            }
            // Drop In from Finder anywhere in detail view (Mac -> Android)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL], isTargeted: Binding(get: { viewModel.isDropTargeted }, set: { viewModel.isDropTargeted = $0 })) { providers in
                viewModel.isDropTargeted = false
                
                // Same-location drop protection: cancel drop immediately to avoid promised data deadlock
                if let dragCtx = viewModel.activeDragContext,
                   let device = viewModel.selectedDevice,
                   dragCtx.deviceID == device.id {
                    let normSource = AppViewModel.normalizePath(dragCtx.sourceDirectory)
                    let normCurrent = AppViewModel.normalizePath(viewModel.currentPath)
                    if normSource == normCurrent {
                        viewModel.statusMessage = "Item(s) already in this location. No changes made."
                        viewModel.activeDragContext = nil
                        return false
                    }
                }
                
                Task {
                    _ = await viewModel.handleDrop(providers: providers)
                }
                return true
            }
            .overlay {
                if viewModel.isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .background(Color.accentColor.opacity(0.12))
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor)
                                Text("Drop files or folders to upload to \(viewModel.currentPath)")
                                    .font(.headline)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .allowsHitTesting(false)
                }
            }
        }
        // Native Keyboard Shortcuts & Event Monitor View
        .background {
            ZStack {
                KeyEventHandlerView { event in
                    let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
                    let isCmd = mods.contains(.command)
                    
                    // Spacebar (keyCode 49): Quick Look
                    if event.keyCode == 49 && mods.isEmpty {
                        Task { await viewModel.handleSpacebar() }
                        return true
                    }
                    
                    // Escape (keyCode 53): Close Quick Look or Clear Selection
                    if event.keyCode == 53 && mods.isEmpty {
                        viewModel.handleEscape()
                        return true
                    }
                    
                    // Return (keyCode 36): Open folder or Preview file
                    if event.keyCode == 36 && mods.isEmpty {
                        Task { await viewModel.openSelectedFolderOrPreview() }
                        return true
                    }
                    
                    // Up Arrow (keyCode 126)
                    if event.keyCode == 126 {
                        if isCmd {
                            Task { await viewModel.navigateUp() }
                            return true
                        } else if mods.isEmpty {
                            Task { await viewModel.selectPreviousItem() }
                            return true
                        }
                    }
                    
                    // Down Arrow (keyCode 125)
                    if event.keyCode == 125 {
                        if isCmd {
                            Task { await viewModel.openSelectedFolder() }
                            return true
                        } else if mods.isEmpty {
                            Task { await viewModel.selectNextItem() }
                            return true
                        }
                    }
                    
                    // Delete (51) / Forward Delete (117)
                    if (event.keyCode == 51 || event.keyCode == 117) && (mods.isEmpty || isCmd) {
                        Task { await viewModel.deleteSelectedItems() }
                        return true
                    }
                    
                    // Cmd shortcuts
                    if isCmd {
                        let char = event.charactersIgnoringModifiers?.lowercased()
                        let code = event.keyCode
                        
                        if char == "c" || code == 8 {
                            viewModel.copySelection()
                            return true
                        } else if char == "x" || code == 7 {
                            viewModel.cutSelection()
                            return true
                        } else if char == "v" || code == 9 {
                            Task { await viewModel.paste() }
                            return true
                        } else if char == "a" || code == 0 {
                            viewModel.selectAll()
                            return true
                        }
                    }
                    
                    return false
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)
                
                // Fallback SwiftUI keyboard shortcuts
                VStack {
                    Button("") {
                        guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
                        viewModel.copySelection()
                    }.keyboardShortcut("c", modifiers: .command)
                    Button("") {
                        guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
                        viewModel.cutSelection()
                    }.keyboardShortcut("x", modifiers: .command)
                    Button("") {
                        guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
                        Task { await viewModel.paste() }
                    }.keyboardShortcut("v", modifiers: .command)
                    Button("") {
                        guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
                        viewModel.selectAll()
                    }.keyboardShortcut("a", modifiers: .command)
                    Button("") {
                        guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
                        Task { await viewModel.deleteSelectedItems() }
                    }.keyboardShortcut(.delete, modifiers: [])
                    Button("") {
                        guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
                        viewModel.handleEscape()
                    }.keyboardShortcut(.escape, modifiers: [])
                    Button("") {
                        guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
                        Task { await viewModel.navigateUp() }
                    }.keyboardShortcut(.upArrow, modifiers: .command)
                    Button("") {
                        guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
                        Task { await viewModel.openSelectedFolder() }
                    }.keyboardShortcut(.downArrow, modifiers: .command)
                    Button("") {
                        guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
                        Task { await viewModel.openSelectedFolderOrPreview() }
                    }.keyboardShortcut(.return, modifiers: [])
                }
                .opacity(0)
                .frame(width: 0, height: 0)
            }
        }
        // Media Preview Sheet
        .sheet(isPresented: Binding(get: { viewModel.showingMediaPreview }, set: { if !$0 { viewModel.closeMediaPreview() } })) {
            MediaPreviewSheet(viewModel: viewModel)
        }
        // Rename Item Sheet
        .sheet(isPresented: Binding(get: { viewModel.showingRenameSheet }, set: { viewModel.showingRenameSheet = $0 })) {
            VStack(spacing: 16) {
                Text("Rename Item")
                    .font(.headline)
                
                TextField("New name", text: Binding(get: { viewModel.renameNewName }, set: { viewModel.renameNewName = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                
                HStack {
                    Button("Cancel") {
                        viewModel.showingRenameSheet = false
                    }
                    Button("Rename") {
                        if let target = viewModel.renameTargetItem {
                            let name = viewModel.renameNewName
                            Task { await viewModel.renameItem(target, to: name) }
                        }
                        viewModel.showingRenameSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.renameNewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
        }
        .onReceive(NotificationCenter.default.publisher(for: .droidBridgeCopy)) { _ in
            guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
            viewModel.copySelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .droidBridgeCut)) { _ in
            guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
            viewModel.cutSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .droidBridgePaste)) { _ in
            guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
            Task { await viewModel.paste() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .droidBridgeSelectAll)) { _ in
            guard NSApp.isActive, let w = NSApp.keyWindow, w.isKeyWindow, w.attachedSheet == nil else { return }
            viewModel.selectAll()
        }
        .task {
            await viewModel.loadDevices()
        }
    }
}

// MARK: - Dedicated Media Preview Sheet (Audio & Video)

struct MediaPreviewSheet: View {
    @Bindable var viewModel: AppViewModel
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: viewModel.mediaPreviewModel.mediaType == .audio ? "waveform" : "video.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text(viewModel.mediaPreviewModel.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: {
                    viewModel.closeMediaPreview()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Preview (Esc)")
            }
            .padding(.horizontal)
            .padding(.top)
            
            if let err = viewModel.mediaPreviewModel.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Media Playback Notice")
                        .font(.headline)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding()
            } else if let player = viewModel.mediaPreviewModel.player {
                if viewModel.mediaPreviewModel.mediaType == .video {
                    VideoPlayer(player: player)
                        .frame(minWidth: 480, minHeight: 300)
                        .cornerRadius(8)
                        .padding(.horizontal)
                } else {
                    // Audio Player View
                    VStack(spacing: 16) {
                        Image(systemName: "music.note")
                            .font(.system(size: 54))
                            .foregroundColor(.accentColor)
                            .padding(.top, 16)
                        
                        // Scrubber & Time
                        VStack(spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { viewModel.mediaPreviewModel.currentTime },
                                    set: { viewModel.mediaPreviewModel.seek(to: $0) }
                                ),
                                in: 0...max(0.1, viewModel.mediaPreviewModel.duration)
                            )
                            HStack {
                                Text(formatTime(viewModel.mediaPreviewModel.currentTime))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatTime(viewModel.mediaPreviewModel.duration))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Audio Controls
                        HStack(spacing: 24) {
                            Button(action: {
                                viewModel.mediaPreviewModel.seek(to: max(0, viewModel.mediaPreviewModel.currentTime - 10))
                            }) {
                                Image(systemName: "gobackward.10")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                viewModel.mediaPreviewModel.togglePlayPause()
                            }) {
                                Image(systemName: viewModel.mediaPreviewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help(viewModel.mediaPreviewModel.isPlaying ? "Pause" : "Play")
                            
                            Button(action: {
                                viewModel.mediaPreviewModel.seek(to: min(viewModel.mediaPreviewModel.duration, viewModel.mediaPreviewModel.currentTime + 10))
                            }) {
                                Image(systemName: "goforward.10")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 16)
                    }
                    .frame(minWidth: 380, minHeight: 200)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
            } else {
                ProgressView("Loading media...")
                    .frame(minWidth: 380, minHeight: 200)
            }
        }
        .padding(.bottom)
        .frame(minWidth: 440, minHeight: viewModel.mediaPreviewModel.mediaType == .video ? 360 : 250)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - AppKit Key Event Monitor Representable

struct KeyEventHandlerView: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> KeyMonitorNSView {
        let view = KeyMonitorNSView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: KeyMonitorNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

final class KeyMonitorNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    private var monitor: Any?
    
    // Support QLPreviewPanel responder chain
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }
    
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = QuickLookCoordinator.shared
            panel.delegate = QuickLookCoordinator.shared
        }
    }
    
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    }
    
    func shouldHandleKeyEvent(_ event: NSEvent) -> Bool {
        guard NSApp.isActive else { return false }
        guard let window = self.window,
              window.isKeyWindow,
              NSApp.keyWindow == window,
              window.attachedSheet == nil else {
            return false
        }
        if let eventWindow = event.window, eventWindow != window {
            return false
        }
        if let responder = window.firstResponder,
           responder is NSText || responder is NSTextView || responder is NSTextField {
            return false
        }
        return true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.shouldHandleKeyEvent(event) else { return event }
                if let handled = self.onKeyDown?(event), handled {
                    return nil
                }
                return event
            }
        } else if window == nil, let mon = monitor {
            NSEvent.removeMonitor(mon)
            monitor = nil
        }
    }
    
    isolated deinit {
        if let mon = monitor {
            NSEvent.removeMonitor(mon)
        }
    }
}

// MARK: - Dedicated Row View for Storage Items

struct StorageItemRowView: View {
    let item: StorageItem
    @Bindable var viewModel: AppViewModel
    
    var isSelected: Bool {
        viewModel.selectedItemIDs.contains(item.id)
    }
    
    var iconName: String {
        if isSelected {
            return "checkmark.circle.fill"
        }
        return item.isDirectory ? "folder.fill" : "doc"
    }
    
    var iconColor: Color {
        if isSelected {
            return .accentColor
        }
        return item.isDirectory ? .blue : .primary
    }
    
    private func makeDragItemProvider() -> NSItemProvider {
        let itemsToExport = viewModel.handleItemDragInitiated(item)
        let provider = NSItemProvider()
        provider.suggestedName = item.name
        
        guard let transport = viewModel.activeTransport else { return provider }
        
        let ext = (item.name as NSString).pathExtension
        let itemUTI = UTType(filenameExtension: ext) ?? .item
        provider.registerFileRepresentation(forTypeIdentifier: itemUTI.identifier, fileOptions: [], visibility: .all) { completion in
            Task.detached {
                do {
                    let staged = try await AppViewModel.performExportStaging(items: itemsToExport, transport: transport)
                    if let first = staged.first {
                        completion(first, true, nil)
                    } else {
                        completion(nil, false, DeviceError.itemNotFound(path: item.path))
                    }
                } catch {
                    completion(nil, false, error)
                }
            }
            return Progress()
        }
        
        provider.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { (completionHandler, expectedValueClass, options) in
            Task.detached {
                do {
                    let staged = try await AppViewModel.performExportStaging(items: itemsToExport, transport: transport)
                    if let first = staged.first {
                        let nsURL = first as NSURL
                        completionHandler?(nsURL, nil)
                    } else {
                        completionHandler?(nil, DeviceError.itemNotFound(path: item.path))
                    }
                } catch {
                    completionHandler?(nil, error)
                }
            }
        }
        return provider
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // 1. Dedicated Drag Handle & Icon (Finder drag source)
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.4))
                
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.system(size: 16))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onDrag {
                makeDragItemProvider()
            }
            .onTapGesture {
                let mods = NSEvent.modifierFlags
                Task { await viewModel.handleRowClick(item, eventModifiers: mods) }
            }
            .help("Drag to Finder or Desktop")
            
            // 2. Clickable File Name & Size: single click selects, double click opens, drag exports to Finder
            Button(action: {
                let mods = NSEvent.modifierFlags
                Task { await viewModel.handleRowClick(item, eventModifiers: mods) }
            }) {
                HStack {
                    Text(item.name)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if !item.isDirectory {
                        Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrag {
                makeDragItemProvider()
            }
            
            // 3. Quick Look or Media Preview button for files
            if !item.isDirectory {
                Button(action: {
                    Task { await viewModel.openPreview(for: item) }
                }) {
                    Image(systemName: item.isMedia ? (item.mediaType == .audio ? "waveform" : "play.circle") : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help(item.isMedia ? "Play Media Preview (Space)" : "Quick Look Preview (Space)")
            }
            
            // 4. Open folder chevron button
            if item.isDirectory {
                Button(action: {
                    Task { await viewModel.navigateTo(item.path) }
                }) {
                    Image(systemName: "chevron.right.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Open folder")
            }
            
            // 5. Download action button
            Button(action: {
                viewModel.promptAndDownload(item: item)
            }) {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isTransferring)
            .help(item.isDirectory ? "Download folder to Mac" : "Download file to Mac")
        }
        .padding(.horizontal, 4)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
        .contextMenu {
            if !item.isDirectory {
                Button {
                    Task { await viewModel.openPreview(for: item) }
                } label: {
                    Label(item.isMedia ? "Preview Media (Space)" : "Quick Look Preview (Space)", systemImage: item.isMedia ? "play.circle" : "eye")
                }
                Divider()
            }
            
            Button {
                if !isSelected { viewModel.selectItem(item) }
                viewModel.copySelection()
            } label: {
                Label("Copy (Cmd+C)", systemImage: "doc.on.doc")
            }
            
            Button {
                if !isSelected { viewModel.selectItem(item) }
                viewModel.cutSelection()
            } label: {
                Label("Cut (Cmd+X)", systemImage: "scissors")
            }
            
            Button {
                Task { await viewModel.paste() }
            } label: {
                Label("Paste into Folder (Cmd+V)", systemImage: "doc.on.clipboard")
            }
            
            Divider()
            
            Button {
                viewModel.promptAndDownload(item: item)
            } label: {
                Label(item.isDirectory ? "Download Folder to Mac..." : "Download to Mac...", systemImage: "arrow.down.circle")
            }
            .disabled(viewModel.isTransferring)
            
            Button {
                viewModel.renameTargetItem = item
                viewModel.renameNewName = item.name
                viewModel.showingRenameSheet = true
            } label: {
                Label("Rename...", systemImage: "pencil")
            }
            
            Divider()
            
            Button(role: .destructive) {
                Task {
                    if !isSelected { viewModel.selectItem(item) }
                    await viewModel.deleteSelectedItems()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            if !viewModel.selectedItemIDs.isEmpty {
                Divider()
                Button {
                    viewModel.clearSelection()
                } label: {
                    Label("Deselect All (Esc)", systemImage: "xmark.circle")
                }
            }
        }
    }
}
