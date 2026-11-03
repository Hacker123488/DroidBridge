import SwiftUI
import AppKit
import DroidBridgeCore

final class DroidBridgeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
public struct DroidBridgeApp: App {
    @NSApplicationDelegateAdaptor(DroidBridgeAppDelegate.self) var appDelegate
    
    public init() {}
    
    public var body: some Scene {
        WindowGroup("DroidBridge") {
            ContentView()
                .frame(minWidth: 700, minHeight: 450)
        }
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    guard NSApp.isActive, let window = NSApp.keyWindow, window.isKeyWindow, window.attachedSheet == nil else { return }
                    if let responder = window.firstResponder,
                       responder is NSText || responder is NSTextView || responder is NSTextField {
                        NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                    } else {
                        NotificationCenter.default.post(name: .droidBridgeCut, object: nil)
                    }
                }
                .keyboardShortcut("x", modifiers: .command)
                
                Button("Copy") {
                    guard NSApp.isActive, let window = NSApp.keyWindow, window.isKeyWindow, window.attachedSheet == nil else { return }
                    if let responder = window.firstResponder,
                       responder is NSText || responder is NSTextView || responder is NSTextField {
                        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    } else {
                        NotificationCenter.default.post(name: .droidBridgeCopy, object: nil)
                    }
                }
                .keyboardShortcut("c", modifiers: .command)
                
                Button("Paste") {
                    guard NSApp.isActive, let window = NSApp.keyWindow, window.isKeyWindow, window.attachedSheet == nil else { return }
                    if let responder = window.firstResponder,
                       responder is NSText || responder is NSTextView || responder is NSTextField {
                        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    } else {
                        NotificationCenter.default.post(name: .droidBridgePaste, object: nil)
                    }
                }
                .keyboardShortcut("v", modifiers: .command)
                
                Button("Select All") {
                    guard NSApp.isActive, let window = NSApp.keyWindow, window.isKeyWindow, window.attachedSheet == nil else { return }
                    if let responder = window.firstResponder,
                       responder is NSText || responder is NSTextView || responder is NSTextField {
                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    } else {
                        NotificationCenter.default.post(name: .droidBridgeSelectAll, object: nil)
                    }
                }
                .keyboardShortcut("a", modifiers: .command)
            }
        }
    }
}
