import Foundation

/// Manages resolution and verification of the official Android Debug Bridge (adb) executable path.
public struct ADBConfiguration: Sendable, Equatable {
    /// Explicit override for the adb executable path.
    public var customADBPath: String?
    
    /// Standard fallback paths searched when adb is not found in PATH.
    public static let candidatePaths: [String] = [
        "/opt/homebrew/bin/adb",
        "/usr/local/bin/adb",
        ("~" as NSString).expandingTildeInPath + "/Library/Android/sdk/platform-tools/adb",
        "/Library/Android/sdk/platform-tools/adb"
    ]
    
    public init(customADBPath: String? = nil) {
        self.customADBPath = customADBPath
    }
    
    /// Resolves the absolute URL to the adb binary if available on this system.
    public func resolveExecutableURL() -> URL? {
        if let custom = customADBPath, !custom.isEmpty {
            let expanded = (custom as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
            // Explicit override supplied but invalid/non-executable -> do not fall back
            return nil
        }
        
        // Check PATH environment variable
        if let pathVar = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathVar.split(separator: ":") {
                let candidate = String(dir) + "/adb"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }
        
        // Check candidate standard installation paths
        for candidate in Self.candidatePaths {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        
        return nil
    }
    
    /// True if a valid adb executable is resolved on the machine.
    public var isAvailable: Bool {
        resolveExecutableURL() != nil
    }
}
