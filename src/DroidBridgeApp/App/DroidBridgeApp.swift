import SwiftUI
import DroidBridgeCore

@main
public struct DroidBridgeApp: App {
    public init() {}
    
    public var body: some Scene {
        WindowGroup("DroidBridge") {
            ContentView()
                .frame(minWidth: 700, minHeight: 450)
        }
    }
}
