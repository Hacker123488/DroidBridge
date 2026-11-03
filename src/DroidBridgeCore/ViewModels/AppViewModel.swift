import Foundation
import SwiftUI
import AppKit
import Observation
import UniformTypeIdentifiers

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
    
    // Transfer & Progress State
    public var isTransferring: Bool = false
    public var transferProgressFraction: Double = 0.0
    public var transferStatusText: String = ""
    public var lastError: String?
    
    // Selection State
    public var selectedItemIDs: Set<String> = []
    public var lastSelectedItemID: String?
    
    // Clipboard State
    public var clipboardPayload: AndroidClipboardPayload?
    
    // Drag and Drop State
    public var isDropTargeted: Bool = false
    
    // Conflict Settings
    public var conflictResolution: ConflictResolutionPolicy = .renameWithTimestamp
    
    // Rename Dialog State
    public var showingRenameSheet: Bool = false
    public var renameTargetItem: StorageItem?
    public var renameNewName: String = ""
    
    // Drag Context for Same-Location Protection
    public struct DragSessionContext: Sendable {
        public let deviceID: String
        public let sourceDirectory: String
        public let itemNames: Set<String>
        public let stagedURLs: [URL]
        
        public init(deviceID: String, sourceDirectory: String, itemNames: Set<String>, stagedURLs: [URL] = []) {
            self.deviceID = deviceID
            self.sourceDirectory = sourceDirectory
            self.itemNames = itemNames
            self.stagedURLs = stagedURLs
        }
    }
    public var activeDragContext: DragSessionContext?
    public private(set) var lastStagedExportURLs: [URL] = []
    public private(set) var lastCopyPasteboardChangeCount: Int = -1
    
    // Media Preview State
    public let mediaPreviewModel = MediaPreviewModel()
    public var showingMediaPreview: Bool = false
    public var activeMediaItem: StorageItem?
    
    private var activeTransferTask: Task<Void, Never>?
    public let connectionManager: ConnectionManager
    
    public init(connectionManager: ConnectionManager = ConnectionManager()) {
        self.connectionManager = connectionManager
    }
    
    // MARK: - Selected Items Helper
    
    public var selectedItems: [StorageItem] {
        storageItems.filter { selectedItemIDs.contains($0.id) }
    }
    
    // MARK: - Device Lifecycle
    
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
            self.selectedItemIDs.removeAll()
            await navigateTo("/sdcard")
        } catch {
            self.statusMessage = "Connection failed: \(error.localizedDescription)"
            self.lastError = error.localizedDescription
        }
    }
    
    // MARK: - Navigation
    
    public var canNavigateUp: Bool {
        return currentPath != "/" && currentPath != "/sdcard"
    }
    
    public var parentDirectoryItem: StorageItem? {
        guard canNavigateUp else { return nil }
        let parent = (currentPath as NSString).deletingLastPathComponent
        let target = parent.isEmpty ? "/" : parent
        return StorageItem(
            id: "__parent_directory__",
            name: "..",
            path: target,
            size: 0,
            modifiedDate: Date(),
            isDirectory: true
        )
    }
    
    public func navigateTo(_ path: String) async {
        guard let transport = activeTransport else { return }
        closeQuickLook()
        do {
            storageItems = try await transport.fileSystem.listDirectory(at: path)
            currentPath = path
            selectedItemIDs.removeAll()
            lastSelectedItemID = nil
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
    
    public func openSelectedFolder() async {
        guard selectedItemIDs.count == 1,
              let itemID = selectedItemIDs.first,
              let item = storageItems.first(where: { $0.id == itemID }),
              item.isDirectory else { return }
        await navigateTo(item.path)
    }
    
    // MARK: - User Click & Double-Click Actions
    
    public var lastClickTime: Date?
    public var lastClickedItemID: String?
    
    public func handleRowClick(_ item: StorageItem, eventModifiers: NSEvent.ModifierFlags = []) async {
        let now = Date()
        let isMulti = eventModifiers.contains(.command)
        let isRange = eventModifiers.contains(.shift)
        
        // Double-click detection: same item clicked twice within double-click threshold without modifier keys
        if !isMulti && !isRange,
           lastClickedItemID == item.id,
           let lastTime = lastClickTime,
           now.timeIntervalSince(lastTime) <= NSEvent.doubleClickInterval {
            lastClickTime = nil
            lastClickedItemID = nil
            await handleItemDoubleClick(item)
            return
        }
        
        lastClickTime = now
        lastClickedItemID = item.id
        handleItemClick(item, multiSelect: isMulti, rangeSelect: isRange)
    }
    
    public func handleItemClick(_ item: StorageItem, multiSelect: Bool = false, rangeSelect: Bool = false) {
        selectItem(item, multiSelect: multiSelect, rangeSelect: rangeSelect)
    }
    
    public func handleItemDoubleClick(_ item: StorageItem) async {
        if item.id == "__parent_directory__" {
            await handleParentDirectoryDoubleClick()
        } else if item.isDirectory {
            await navigateTo(item.path)
        } else {
            await openOrPreviewFile(item: item)
        }
    }
    
    public func handleParentDirectoryDoubleClick() async {
        await navigateUp()
    }
    
    // MARK: - Path Normalization & Same-Location Utilities
    
    public static func normalizePath(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while p.contains("//") {
            p = p.replacingOccurrences(of: "//", with: "/")
        }
        if p.count > 1 && p.hasSuffix("/") {
            p = String(p.dropLast())
        }
        if p.hasPrefix("/storage/emulated/0") {
            p = "/sdcard" + p.dropFirst("/storage/emulated/0".count)
        } else if p.hasPrefix("/storage/self/primary") {
            p = "/sdcard" + p.dropFirst("/storage/self/primary".count)
        }
        return p
    }
    
    public static func isSameLocation(sourceRemotePath: String, targetDirectory: String, itemName: String) -> Bool {
        let normSource = normalizePath(sourceRemotePath)
        let targetFull = targetDirectory.hasSuffix("/") ? "\(targetDirectory)\(itemName)" : "\(targetDirectory)/\(itemName)"
        let normTarget = normalizePath(targetFull)
        return normSource == normTarget
    }
    
    public func handleItemDragInitiated(_ item: StorageItem) -> [StorageItem] {
        let items: [StorageItem]
        if selectedItemIDs.contains(item.id) && !selectedItems.isEmpty {
            items = selectedItems
        } else {
            items = [item]
        }
        if let device = selectedDevice {
            activeDragContext = DragSessionContext(
                deviceID: device.id,
                sourceDirectory: currentPath,
                itemNames: Set(items.map { $0.name })
            )
        }
        return items
    }
    
    public func openOrPreviewFile(item: StorageItem) async {
        guard activeTransport != nil, !item.isDirectory else { return }
        await openPreview(for: item)
    }
    
    // MARK: - Selection Management
    
    public func selectItem(_ item: StorageItem, multiSelect: Bool = false, rangeSelect: Bool = false) {
        if rangeSelect, let lastID = lastSelectedItemID,
           let lastIdx = storageItems.firstIndex(where: { $0.id == lastID }),
           let currentIdx = storageItems.firstIndex(where: { $0.id == item.id }) {
            let lower = min(lastIdx, currentIdx)
            let upper = max(lastIdx, currentIdx)
            for idx in lower...upper {
                selectedItemIDs.insert(storageItems[idx].id)
            }
        } else if multiSelect {
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
                lastSelectedItemID = item.id
            }
        } else {
            if selectedItemIDs.contains(item.id) && selectedItemIDs.count > 1 {
                // Keep multi-selection intact for dragging
                lastSelectedItemID = item.id
            } else {
                selectedItemIDs = [item.id]
                lastSelectedItemID = item.id
            }
        }
    }
    
    public func selectAll() {
        selectedItemIDs = Set(storageItems.map { $0.id })
    }
    
    public func clearSelection() {
        selectedItemIDs.removeAll()
        lastSelectedItemID = nil
        lastClickTime = nil
        lastClickedItemID = nil
    }
    
    // MARK: - Clipboard Operations (Cmd+C, Cmd+X, Cmd+V)
    
    public func copySelection() {
        guard let device = selectedDevice, !selectedItems.isEmpty else { return }
        let clipItems = selectedItems.map { ClipboardItem(storageItem: $0, deviceID: device.id) }
        let payload = AndroidClipboardPayload(operation: .copy, deviceID: device.id, items: clipItems)
        self.clipboardPayload = payload
        
        let pboard = NSPasteboard.general
        pboard.clearContents()
        if let data = payload.serialize() {
            pboard.setData(data, forType: NSPasteboard.PasteboardType(AndroidClipboardPayload.pasteboardTypeString))
        }
        lastCopyPasteboardChangeCount = pboard.changeCount
        statusMessage = "Copied \(clipItems.count) item(s) to clipboard."
        
        let itemsToExport = selectedItems
        Task { [weak self] in
            guard let self = self else { return }
            if let urls = try? await self.stageItemsForExport(itemsToExport) {
                await MainActor.run {
                    pboard.clearContents()
                    pboard.writeObjects(urls as [NSURL])
                    if let data = payload.serialize() {
                        pboard.setData(data, forType: NSPasteboard.PasteboardType(AndroidClipboardPayload.pasteboardTypeString))
                    }
                    self.lastCopyPasteboardChangeCount = pboard.changeCount
                }
            }
        }
    }
    
    public func copySelectionAndStageForFinder() async {
        guard let device = selectedDevice, !selectedItems.isEmpty else { return }
        let clipItems = selectedItems.map { ClipboardItem(storageItem: $0, deviceID: device.id) }
        let payload = AndroidClipboardPayload(operation: .copy, deviceID: device.id, items: clipItems)
        self.clipboardPayload = payload
        
        let pboard = NSPasteboard.general
        pboard.clearContents()
        if let data = payload.serialize() {
            pboard.setData(data, forType: NSPasteboard.PasteboardType(AndroidClipboardPayload.pasteboardTypeString))
        }
        lastCopyPasteboardChangeCount = pboard.changeCount
        statusMessage = "Copied \(clipItems.count) item(s) to clipboard."
        
        let itemsToExport = selectedItems
        if let urls = try? await stageItemsForExport(itemsToExport) {
            pboard.clearContents()
            pboard.writeObjects(urls as [NSURL])
            if let data = payload.serialize() {
                pboard.setData(data, forType: NSPasteboard.PasteboardType(AndroidClipboardPayload.pasteboardTypeString))
            }
            self.lastCopyPasteboardChangeCount = pboard.changeCount
        }
    }
    
    public func cutSelection() {
        guard let device = selectedDevice, !selectedItems.isEmpty else { return }
        let clipItems = selectedItems.map { ClipboardItem(storageItem: $0, deviceID: device.id) }
        let payload = AndroidClipboardPayload(operation: .cut, deviceID: device.id, items: clipItems)
        self.clipboardPayload = payload
        
        let pboard = NSPasteboard.general
        pboard.clearContents()
        if let data = payload.serialize() {
            pboard.setData(data, forType: NSPasteboard.PasteboardType(AndroidClipboardPayload.pasteboardTypeString))
        }
        lastCopyPasteboardChangeCount = pboard.changeCount
        statusMessage = "Cut \(clipItems.count) item(s) to clipboard."
    }
    
    public func paste() async {
        guard let transport = activeTransport, let device = selectedDevice else {
            statusMessage = "Cannot paste: No device connected."
            return
        }
        
        let pboard = NSPasteboard.general
        let currentChangeCount = pboard.changeCount
        
        // 1. Android-to-Android Paste (Internal Copy or Move from system pasteboard)
        if let data = pboard.data(forType: NSPasteboard.PasteboardType(AndroidClipboardPayload.pasteboardTypeString)),
           let payload = AndroidClipboardPayload.deserialize(from: data) {
            if payload.deviceID == device.id {
                await executeAndroidPaste(payload: payload, transport: transport)
                return
            }
        }
        
        // 2. Mac-to-Android Paste (URLs from Finder)
        if let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
            let validURLs = fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !validURLs.isEmpty {
                await uploadItems(at: validURLs)
                return
            }
        }
        
        // 3. In-App payload fallback ONLY if pasteboard hasn't been modified by another app
        if currentChangeCount == lastCopyPasteboardChangeCount,
           let localPayload = clipboardPayload,
           localPayload.deviceID == device.id {
            await executeAndroidPaste(payload: localPayload, transport: transport)
            return
        }
        
        statusMessage = "Clipboard is empty or contains unsupported content."
    }
    
    private func executeAndroidPaste(payload: AndroidClipboardPayload, transport: any DeviceTransport) async {
        let opName = payload.operation == .cut ? "Moving" : "Copying"
        lastError = nil
        
        // Pre-filter same-location items
        var sameLocationCount = 0
        var itemsToProcess: [(item: ClipboardItem, targetPath: String)] = []
        
        for item in payload.items {
            let normSource = Self.normalizePath(item.remotePath)
            let rawTarget = currentPath.hasSuffix("/") ? "\(currentPath)\(item.name)" : "\(currentPath)/\(item.name)"
            let normTarget = Self.normalizePath(rawTarget)
            
            if normSource == normTarget {
                sameLocationCount += 1
            } else {
                itemsToProcess.append((item: item, targetPath: rawTarget))
            }
        }
        
        if itemsToProcess.isEmpty {
            statusMessage = "Source and destination are the same location. No changes made."
            return
        }
        
        isTransferring = true
        transferProgressFraction = 0.0
        statusMessage = "\(opName) \(itemsToProcess.count) item(s)..."
        
        var succeeded = 0
        for entry in itemsToProcess {
            do {
                if payload.operation == .cut {
                    _ = try await transport.fileSystem.moveItem(from: entry.item.remotePath, to: entry.targetPath)
                } else {
                    _ = try await transport.fileSystem.copyItem(from: entry.item.remotePath, to: entry.targetPath)
                }
                succeeded += 1
                transferProgressFraction = Double(succeeded) / Double(itemsToProcess.count)
            } catch {
                lastError = error.localizedDescription
                statusMessage = "Failed to \(payload.operation.rawValue) \(entry.item.name): \(error.localizedDescription)"
            }
        }
        
        if payload.operation == .cut && succeeded > 0 {
            clipboardPayload = nil
            NSPasteboard.general.clearContents()
            lastCopyPasteboardChangeCount = NSPasteboard.general.changeCount
        }
        
        isTransferring = false
        if succeeded > 0 {
            statusMessage = "\(payload.operation == .cut ? "Moved" : "Copied") \(succeeded) item(s) successfully."
        }
        await navigateTo(currentPath)
    }
    
    // MARK: - Deletion & Renaming
    
    public func deleteSelectedItems() async {
        guard let transport = activeTransport, !selectedItems.isEmpty else { return }
        let itemsToDelete = selectedItems
        statusMessage = "Deleting \(itemsToDelete.count) item(s)..."
        lastError = nil
        
        for item in itemsToDelete {
            do {
                try await transport.fileSystem.deleteItem(at: item.path, isRecursive: item.isDirectory)
            } catch {
                lastError = error.localizedDescription
                statusMessage = "Error deleting \(item.name): \(error.localizedDescription)"
            }
        }
        
        clearSelection()
        await navigateTo(currentPath)
    }
    
    public func renameItem(_ item: StorageItem, to newName: String) async {
        guard let transport = activeTransport else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        
        do {
            _ = try await transport.fileSystem.renameItem(at: item.path, newName: trimmed)
            statusMessage = "Renamed \(item.name) to \(trimmed)."
            await navigateTo(currentPath)
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Rename failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Single & Multiple Uploads (Mac -> Android)
    
    public func upload(localURL: URL) async {
        await uploadItems(at: [localURL])
    }
    
    public func uploadItems(at urls: [URL], conflictResolution: ConflictResolutionPolicy? = nil) async {
        guard let transport = activeTransport, let device = selectedDevice else {
            statusMessage = "Cannot upload: No device connected."
            lastError = "No device connected."
            return
        }
        guard !isTransferring else {
            statusMessage = "Transfer already in progress."
            return
        }
        
        let validURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validURLs.isEmpty else {
            statusMessage = "No valid files or folders to upload."
            lastError = "Invalid files."
            return
        }
        
        isTransferring = true
        transferProgressFraction = 0.0
        let resolution = conflictResolution ?? self.conflictResolution
        let targetDir = currentPath
        lastError = nil
        
        let task = Task { [weak self, transport, device] in
            var uploadedCount = 0
            for (idx, localURL) in validURLs.enumerated() {
                do {
                    await MainActor.run { [weak self] in
                        self?.transferStatusText = "Uploading \(localURL.lastPathComponent) (\(idx + 1)/\(validURLs.count))..."
                        self?.statusMessage = "Uploading \(localURL.lastPathComponent) to \(targetDir)..."
                    }
                    
                    _ = try await transport.transferService.upload(
                        localURL: localURL,
                        remotePath: targetDir,
                        options: TransferOptions(conflictResolution: resolution),
                        progress: { [weak self] prog in
                            Task { @MainActor [weak self] in
                                guard let self = self else { return }
                                let itemFraction = prog.totalBytes > 0 ? Double(prog.bytesTransferred) / Double(prog.totalBytes) : 0.0
                                let overallFraction = (Double(idx) + itemFraction) / Double(validURLs.count)
                                self.transferProgressFraction = overallFraction
                            }
                        }
                    )
                    uploadedCount += 1
                } catch is CancellationError {
                    await MainActor.run { [weak self] in
                        self?.isTransferring = false
                        self?.statusMessage = "Upload cancelled."
                        self?.transferStatusText = "Cancelled."
                    }
                    return
                } catch {
                    await MainActor.run { [weak self] in
                        self?.lastError = error.localizedDescription
                        self?.statusMessage = "Upload failed for \(localURL.lastPathComponent): \(error.localizedDescription)"
                    }
                }
            }
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.isTransferring = false
                self.transferProgressFraction = 1.0
                if uploadedCount > 0 {
                    self.statusMessage = "Uploaded \(uploadedCount) item(s) successfully to \(device.name)."
                    self.transferStatusText = "Upload complete."
                }
            }
            
            await self?.navigateTo(targetDir)
        }
        
        activeTransferTask = task
        await task.value
    }
    
    // MARK: - Drag and Drop Handlers
    
    public func handleDrop(providers: [NSItemProvider]) async -> Bool {
        defer {
            isDropTargeted = false
        }
        guard activeTransport != nil, !isTransferring else { return false }
        
        // Same-location drop protection from active in-app drag session
        if let dragCtx = activeDragContext,
           let device = selectedDevice,
           dragCtx.deviceID == device.id {
            let normSource = Self.normalizePath(dragCtx.sourceDirectory)
            let normCurrent = Self.normalizePath(currentPath)
            if normSource == normCurrent {
                statusMessage = "Item(s) already in this location. No changes made."
                activeDragContext = nil
                return true
            }
        }
        activeDragContext = nil
        
        var droppedURLs: [URL] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) {
                    if let url = item as? URL {
                        droppedURLs.append(url)
                    } else if let nsURL = item as? NSURL, let url = nsURL as URL? {
                        droppedURLs.append(url)
                    } else if let urlData = item as? Data {
                        if let str = String(data: urlData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           let url = URL(string: str) {
                            droppedURLs.append(url)
                        } else if let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                            droppedURLs.append(url)
                        }
                    } else if let str = item as? String {
                        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let url = URL(string: trimmed) {
                            droppedURLs.append(url)
                        } else {
                            droppedURLs.append(URL(fileURLWithPath: trimmed))
                        }
                    }
                }
            }
        }
        
        guard !droppedURLs.isEmpty else {
            statusMessage = "Dropped items are not supported local files or folders."
            lastError = "Unsupported dropped items."
            return false
        }
        
        // Protection against dropping staged exports back into their own origin folder
        let filteredURLs = droppedURLs.filter { localURL in
            let name = localURL.lastPathComponent
            if localURL.path.contains("droidbridge_export_") || localURL.path.contains("droidbridge_quicklook_cache") || localURL.path.contains("droidbridge_media_cache") {
                if storageItems.contains(where: { $0.name == name }) {
                    return false
                }
            }
            return true
        }
        
        if filteredURLs.isEmpty {
            statusMessage = "Item(s) already in this location. No changes made."
            return true
        }
        
        await uploadItems(at: filteredURLs)
        return true
    }
    
    // MARK: - Staging Export for Drag to Finder (Android -> Mac)
    
    public func stageItemsForExport(_ items: [StorageItem]) async throws -> [URL] {
        guard let transport = activeTransport else {
            throw DeviceError.deviceDisconnected(deviceID: "none")
        }
        let urls = try await Self.performExportStaging(items: items, transport: transport)
        lastStagedExportURLs = urls
        return urls
    }
    
    public nonisolated static func performExportStaging(items: [StorageItem], transport: DeviceTransport) async throws -> [URL] {
        let stagingSessionID = UUID().uuidString
        let stagingDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("droidbridge_export_\(stagingSessionID)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        
        var stagedURLs: [URL] = []
        
        do {
            for item in items {
                try Task.checkCancellation()
                let destinationURL = stagingDir.appendingPathComponent(item.name)
                
                // Fast-path: check if file was already cached with matching size in preview caches
                let qlCache = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("droidbridge_quicklook_cache")
                    .appendingPathComponent(item.name)
                let mediaCache = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("droidbridge_media_cache")
                    .appendingPathComponent(item.name)
                
                var copiedFromCache = false
                if FileManager.default.fileExists(atPath: qlCache.path),
                   let attrs = try? FileManager.default.attributesOfItem(atPath: qlCache.path),
                   (attrs[.size] as? Int64) == item.size {
                    try? FileManager.default.copyItem(at: qlCache, to: destinationURL)
                    copiedFromCache = FileManager.default.fileExists(atPath: destinationURL.path)
                } else if FileManager.default.fileExists(atPath: mediaCache.path),
                          let attrs = try? FileManager.default.attributesOfItem(atPath: mediaCache.path),
                          (attrs[.size] as? Int64) == item.size {
                    try? FileManager.default.copyItem(at: mediaCache, to: destinationURL)
                    copiedFromCache = FileManager.default.fileExists(atPath: destinationURL.path)
                }
                
                if !copiedFromCache {
                    if item.isDirectory {
                        try await transport.transferService.downloadDirectory(
                            remotePath: item.path,
                            localURL: destinationURL,
                            options: TransferOptions(conflictResolution: .overwrite),
                            progress: { _ in }
                        )
                    } else {
                        try await transport.transferService.download(
                            remotePath: item.path,
                            localURL: destinationURL,
                            options: TransferOptions(conflictResolution: .overwrite),
                            progress: { _ in }
                        )
                    }
                }
                
                guard FileManager.default.fileExists(atPath: destinationURL.path) else {
                    throw DeviceError.ioError(message: "Staged export file \(item.name) was not created.")
                }
                stagedURLs.append(destinationURL)
            }
        } catch {
            // Clean up staging directory on any failure so incomplete files are never exposed
            try? FileManager.default.removeItem(at: stagingDir)
            throw error
        }
        
        return stagedURLs
    }
    
    // MARK: - Download Single & Directory
    
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
    
    public func downloadDirectory(item: StorageItem, to destinationURL: URL) async {
        guard let transport = activeTransport, let device = selectedDevice else {
            statusMessage = "Cannot download: No device connected."
            lastError = "No device connected."
            return
        }
        guard !isTransferring else {
            statusMessage = "Transfer already in progress."
            return
        }
        guard item.isDirectory else {
            await download(item: item, to: destinationURL)
            return
        }
        
        isTransferring = true
        transferProgressFraction = 0.0
        transferStatusText = "Exporting folder \(item.name)..."
        statusMessage = "Downloading directory \(item.name) from \(device.name)..."
        lastError = nil
        
        let task = Task { [weak self, transport, device] in
            do {
                try await transport.transferService.downloadDirectory(
                    remotePath: item.path,
                    localURL: destinationURL,
                    options: TransferOptions(conflictResolution: .overwrite),
                    progress: { [weak self] prog in
                        Task { @MainActor [weak self] in
                            self?.transferProgressFraction = 0.5
                        }
                    }
                )
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.isTransferring = false
                    self.transferProgressFraction = 1.0
                    self.statusMessage = "Downloaded folder \(item.name) successfully from \(device.name)."
                    self.transferStatusText = "Export complete."
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
                    self.statusMessage = "Directory download failed: \(error.localizedDescription)"
                    self.transferStatusText = "Failed."
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
    
    // MARK: - Panel Prompts
    
    public func promptAndUpload() {
        guard activeTransport != nil, !isTransferring else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        panel.message = "Choose file(s) or folder(s) to upload to \(currentPath)"
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task {
                await uploadItems(at: urls)
            }
        }
    }
    
    public func promptAndDownload(item: StorageItem) {
        guard activeTransport != nil, !isTransferring else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.prompt = "Download"
        panel.message = "Choose destination for \(item.name)"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                if item.isDirectory {
                    await downloadDirectory(item: item, to: url)
                } else {
                    await download(item: item, to: url)
                }
            }
        }
    }
    
    // MARK: - Spacebar Quick Look & Unified Media Preview
    
    public var currentQuickLookItem: StorageItem?
    
    public var isQuickLookVisible: Bool {
        QuickLookCoordinator.shared.isVisible
    }
    
    public func toggleQuickLook(for item: StorageItem? = nil) async {
        await togglePreview(for: item)
    }
    
    public func togglePreview(for item: StorageItem? = nil) async {
        if showingMediaPreview {
            closeMediaPreview()
            return
        }
        if isQuickLookVisible {
            closeQuickLook()
            return
        }
        
        let targetItem = item ?? (selectedItems.count == 1 ? selectedItems.first : nil)
        guard let target = targetItem else {
            statusMessage = "Select a file to preview with Spacebar."
            return
        }
        
        await openPreview(for: target)
    }
    
    public func openPreview(for item: StorageItem) async {
        guard !item.isDirectory else {
            statusMessage = "Cannot preview a folder."
            return
        }
        if item.isMedia {
            await openMediaPreview(for: item)
        } else {
            await openQuickLook(for: item)
        }
    }
    
    public func openMediaPreview(for item: StorageItem) async {
        guard let transport = activeTransport else {
            statusMessage = "Cannot preview: No device connected."
            return
        }
        
        closeQuickLook()
        
        let cacheDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("droidbridge_media_cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        let safeName = item.name.replacingOccurrences(of: "/", with: "_")
        let targetURL = cacheDir.appendingPathComponent(safeName)
        
        var needDownload = true
        if FileManager.default.fileExists(atPath: targetURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
           let size = attrs[.size] as? Int64,
           size == item.size {
            needDownload = false
        }
        
        if needDownload {
            statusMessage = "Loading media preview for \(item.name)..."
            do {
                try await transport.transferService.download(
                    remotePath: item.path,
                    localURL: targetURL,
                    options: TransferOptions(conflictResolution: .overwrite),
                    progress: { _ in }
                )
            } catch {
                statusMessage = "Failed to preview \(item.name): \(error.localizedDescription)"
                lastError = error.localizedDescription
                return
            }
        }
        
        activeMediaItem = item
        showingMediaPreview = true
        mediaPreviewModel.loadMedia(url: targetURL, title: item.name, type: item.mediaType)
        statusMessage = "Previewing \(item.name)"
    }
    
    public func closeMediaPreview() {
        mediaPreviewModel.cleanup()
        showingMediaPreview = false
        activeMediaItem = nil
    }
    
    public func openQuickLook(for item: StorageItem) async {
        guard let transport = activeTransport else {
            statusMessage = "Cannot preview: No device connected."
            return
        }
        
        guard !item.isDirectory else {
            statusMessage = "Cannot preview a folder in Quick Look."
            return
        }
        
        closeMediaPreview()
        
        let cacheDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("droidbridge_quicklook_cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        let safeName = item.name.replacingOccurrences(of: "/", with: "_")
        let targetURL = cacheDir.appendingPathComponent(safeName)
        
        var needDownload = true
        if FileManager.default.fileExists(atPath: targetURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: targetURL.path),
           let size = attrs[.size] as? Int64,
           size == item.size {
            needDownload = false
        }
        
        if needDownload {
            statusMessage = "Loading Quick Look for \(item.name)..."
            do {
                try await transport.transferService.download(
                    remotePath: item.path,
                    localURL: targetURL,
                    options: TransferOptions(conflictResolution: .overwrite),
                    progress: { _ in }
                )
            } catch {
                statusMessage = "Failed to preview \(item.name): \(error.localizedDescription)"
                lastError = error.localizedDescription
                return
            }
        }
        
        currentQuickLookItem = item
        statusMessage = "Previewing \(item.name)"
        QuickLookCoordinator.shared.present(url: targetURL, title: item.name)
    }
    
    public func closeQuickLook() {
        QuickLookCoordinator.shared.close()
        currentQuickLookItem = nil
    }
    
    public func clearQuickLookCache() {
        let cacheDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("droidbridge_quicklook_cache")
        try? FileManager.default.removeItem(at: cacheDir)
        let mediaCacheDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("droidbridge_media_cache")
        try? FileManager.default.removeItem(at: mediaCacheDir)
    }
    
    // MARK: - Arrow Key & Keyboard Actions
    
    public func selectNextItem() async {
        guard !storageItems.isEmpty else { return }
        let nextIndex: Int
        if let lastID = lastSelectedItemID ?? selectedItemIDs.first,
           let idx = storageItems.firstIndex(where: { $0.id == lastID }) {
            nextIndex = min(idx + 1, storageItems.count - 1)
        } else {
            nextIndex = 0
        }
        let nextItem = storageItems[nextIndex]
        selectedItemIDs = [nextItem.id]
        lastSelectedItemID = nextItem.id
        
        if showingMediaPreview {
            if !nextItem.isDirectory && nextItem.isMedia {
                await openMediaPreview(for: nextItem)
            } else {
                closeMediaPreview()
            }
        } else if isQuickLookVisible {
            if !nextItem.isDirectory && !nextItem.isMedia {
                await openQuickLook(for: nextItem)
            } else if !nextItem.isDirectory && nextItem.isMedia {
                closeQuickLook()
                await openMediaPreview(for: nextItem)
            } else {
                closeQuickLook()
            }
        }
    }
    
    public func selectPreviousItem() async {
        guard !storageItems.isEmpty else { return }
        let prevIndex: Int
        if let lastID = lastSelectedItemID ?? selectedItemIDs.first,
           let idx = storageItems.firstIndex(where: { $0.id == lastID }) {
            prevIndex = max(idx - 1, 0)
        } else {
            prevIndex = storageItems.count - 1
        }
        let prevItem = storageItems[prevIndex]
        selectedItemIDs = [prevItem.id]
        lastSelectedItemID = prevItem.id
        
        if showingMediaPreview {
            if !prevItem.isDirectory && prevItem.isMedia {
                await openMediaPreview(for: prevItem)
            } else {
                closeMediaPreview()
            }
        } else if isQuickLookVisible {
            if !prevItem.isDirectory && !prevItem.isMedia {
                await openQuickLook(for: prevItem)
            } else if !prevItem.isDirectory && prevItem.isMedia {
                closeQuickLook()
                await openMediaPreview(for: prevItem)
            } else {
                closeQuickLook()
            }
        }
    }
    
    public func handleEscape() {
        if showingMediaPreview {
            closeMediaPreview()
        } else if isQuickLookVisible {
            closeQuickLook()
        } else {
            clearSelection()
        }
    }
    
    public func handleSpacebar() async {
        await togglePreview()
    }
    
    public func openSelectedFolderOrPreview() async {
        guard selectedItemIDs.count == 1,
              let itemID = selectedItemIDs.first,
              let item = storageItems.first(where: { $0.id == itemID }) else { return }
        if item.isDirectory {
            await navigateTo(item.path)
        } else {
            await openPreview(for: item)
        }
    }
}
