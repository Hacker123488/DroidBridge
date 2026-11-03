import Foundation
import AppKit
import QuickLookUI

/// Item conforming to QLPreviewItem for macOS Quick Look presentation.
public final class QuickLookItem: NSObject, QLPreviewItem, @unchecked Sendable {
    public let previewItemURL: URL?
    public let previewItemTitle: String?
    
    public init(url: URL, title: String) {
        self.previewItemURL = url
        self.previewItemTitle = title
        super.init()
    }
}

/// Central coordinator for macOS QLPreviewPanel presentation and lifecycle.
public final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate, @unchecked Sendable {
    @MainActor public static let shared = QuickLookCoordinator()
    
    @MainActor public var currentItem: QuickLookItem?
    @MainActor private var isPanelActive: Bool = false
    
    /// Presents Quick Look panel for a staged local file URL.
    @MainActor
    public func present(url: URL, title: String) {
        currentItem = QuickLookItem(url: url, title: title)
        isPanelActive = true
        guard NSApp.delegate != nil, let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
    }
    
    /// Toggles Quick Look panel for a given staged local file URL.
    @MainActor
    public func toggle(url: URL, title: String) {
        if isVisible {
            close()
        } else {
            present(url: url, title: title)
        }
    }
    
    /// Updates current preview without dismissing panel if already visible.
    @MainActor
    public func updatePreview(url: URL, title: String) {
        currentItem = QuickLookItem(url: url, title: title)
        guard let panel = QLPreviewPanel.shared(), isVisible else { return }
        panel.reloadData()
    }
    
    /// Closes Quick Look panel if currently visible.
    @MainActor
    public func close() {
        isPanelActive = false
        currentItem = nil
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        if NSApp.delegate != nil {
            panel.orderOut(nil)
        }
    }
    
    /// Checks whether Quick Look panel is currently active/visible.
    @MainActor
    public var isVisible: Bool {
        guard isPanelActive else { return false }
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            return true
        }
        return isPanelActive
    }
    
    // MARK: - QLPreviewPanelDataSource
    
    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            currentItem != nil ? 1 : 0
        }
    }
    
    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            currentItem
        }
    }
}
