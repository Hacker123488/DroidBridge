import Foundation
import Synchronization

private struct MockADBState: ~Copyable {
    var isAvailable: Bool = true
    var recordedCalls: [[String]] = []
    var simulatedDevicesOutput: String = """
    List of devices attached
    RFCW10ABCDE            device usb:1-1 product:panther model:Pixel_7 device:panther transport_id:1
    192.168.1.50:5555      device product:husky model:Pixel_8_Pro device:husky transport_id:2
    HT7750201234           unauthorized usb:1-2 transport_id:3
    emulator-5554          offline transport_id:4
    """
    var simulatedLsOutputs: [String: String] = [:]
    var simulatedPushError: String? = nil
    var simulatedPullError: String? = nil
    var simulateTimeout: Bool = false
    var simulateDisconnect: Bool = false
    var mockStorageFiles: [String: Data] = [:]
}

/// Injected command runner simulating the ADB binary for deterministic unit testing.
public final class MockADBCommandRunner: ADBCommandRunner, @unchecked Sendable {
    public let adbPath: String
    private let state = Mutex(MockADBState())
    
    public init(adbPath: String = "/usr/local/bin/adb") {
        self.adbPath = adbPath
        state.withLock { s in
            s.simulatedLsOutputs["/sdcard"] = """
            drwxrwx--x  4 root sdcard_rw 4096 2026-10-29 18:00 DCIM/
            drwxrwx--x  3 root sdcard_rw 4096 2026-10-29 18:00 Download/
            drwxrwx--x  2 root sdcard_rw 4096 2026-10-29 18:00 Music/
            drwxrwx--x  2 root sdcard_rw 4096 2026-10-29 18:00 Documents/
            """
            s.simulatedLsOutputs["/sdcard/Download"] = """
            -rw-rw----  1 root sdcard_rw 1024 2026-10-29 18:01 welcome.txt
            -rw-rw----  1 root sdcard_rw 2048 2026-10-29 18:02 Unicode 测试 🚀.pdf
            """
            s.mockStorageFiles["/sdcard/Download/welcome.txt"] = "Real Android ADB remote payload content.".data(using: .utf8)
            s.mockStorageFiles["/sdcard/Download/Unicode 测试 🚀.pdf"] = "Unicode content payload".data(using: .utf8)
        }
    }
    
    public func setAvailable(_ available: Bool) {
        state.withLock { $0.isAvailable = available }
    }
    
    public func setSimulatedDevicesOutput(_ output: String) {
        state.withLock { $0.simulatedDevicesOutput = output }
    }
    
    public func setSimulatedPushError(_ error: String?) {
        state.withLock { $0.simulatedPushError = error }
    }
    
    public func setMockStorageFile(path: String, data: Data) {
        state.withLock { $0.mockStorageFiles[path] = data }
    }
    
    public func setSimulatedLsOutput(path: String, output: String) {
        state.withLock { $0.simulatedLsOutputs[path] = output }
    }
    
    public func setSimulatedPullError(_ error: String?) {
        state.withLock { $0.simulatedPullError = error }
    }
    
    public func setSimulateTimeout(_ timeout: Bool) {
        state.withLock { $0.simulateTimeout = timeout }
    }
    
    public func setSimulateDisconnect(_ disconnect: Bool) {
        state.withLock { $0.simulateDisconnect = disconnect }
    }
    
    public func recordedCalls() -> [[String]] {
        state.withLock { $0.recordedCalls }
    }
    
    public func isAvailable() async -> Bool {
        state.withLock { $0.isAvailable }
    }
    
    public func version() async throws -> String {
        guard await isAvailable() else {
            throw DeviceError.ioError(message: "adb binary not found")
        }
        return "Android Debug Bridge version 1.0.41\nVersion 35.0.1-11580221\nInstalled as \(adbPath)"
    }
    
    private func unquoteShellArg(_ arg: String) -> String {
        let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("'") && trimmed.hasSuffix("'") && trimmed.count >= 2 {
            let inner = trimmed.dropFirst().dropLast()
            return String(inner).replacingOccurrences(of: "'\\''", with: "'")
        }
        return trimmed
    }
    
    public func run(arguments: [String], timeout: TimeInterval?) async throws -> ADBCommandResult {
        guard await isAvailable() else {
            throw DeviceError.ioError(message: "adb executable not found.")
        }
        
        let timeoutTrigger = state.withLock { s -> Bool in
            s.recordedCalls.append(arguments)
            return s.simulateTimeout
        }
        
        if timeoutTrigger {
            try await Task.sleep(nanoseconds: 50_000_000)
            throw DeviceError.ioError(message: "Command timed out after \(timeout ?? 30.0) seconds.")
        }
        
        let disconnectTrigger = state.withLock { $0.simulateDisconnect }
        if disconnectTrigger {
            return ADBCommandResult(exitCode: 1, stdout: "", stderr: "error: device '\(arguments.count > 1 ? arguments[1] : "")' not found")
        }
        
        // Handle `adb version`
        if arguments == ["version"] {
            return ADBCommandResult(exitCode: 0, stdout: try await version(), stderr: "")
        }
        
        // Handle `adb devices -l`
        if arguments == ["devices", "-l"] {
            let output = state.withLock { $0.simulatedDevicesOutput }
            return ADBCommandResult(exitCode: 0, stdout: output, stderr: "")
        }
        
        // Handle `adb -s <serial> ...`
        if arguments.count >= 3 && arguments[0] == "-s" {
            let command = arguments[2]
            
            // `adb -s <serial> shell ls ...`
            if command == "shell" && arguments.count >= 4 && arguments[3] == "ls" {
                let targetPath = unquoteShellArg(arguments.last ?? "")
                let isStatMode = arguments.contains("-ld")
                
                if isStatMode {
                    let fileData = state.withLock { $0.mockStorageFiles[targetPath] }
                    if let data = fileData {
                        let name = (targetPath as NSString).lastPathComponent
                        return ADBCommandResult(exitCode: 0, stdout: "-rw-rw---- 1 root sdcard_rw \(data.count) 2026-10-30 00:00 \(name)", stderr: "")
                    }
                    let isKnownDir = state.withLock { s in
                        s.simulatedLsOutputs[targetPath] != nil || targetPath == "/" || targetPath == "/sdcard" || targetPath == "/sdcard/" || targetPath == "/sdcard/Download" || targetPath == "/sdcard/DCIM"
                    }
                    if isKnownDir {
                        let name = (targetPath as NSString).lastPathComponent
                        return ADBCommandResult(exitCode: 0, stdout: "drwxrwx--x 4 root sdcard_rw 4096 2026-10-30 00:00 \(name)/", stderr: "")
                    } else {
                        return ADBCommandResult(exitCode: 1, stdout: "", stderr: "ls: \(targetPath): No such file or directory")
                    }
                }
                
                let lsOutput = state.withLock { s -> String? in
                    s.simulatedLsOutputs[targetPath]
                }
                
                if let output = lsOutput {
                    return ADBCommandResult(exitCode: 0, stdout: output, stderr: "")
                } else {
                    return ADBCommandResult(exitCode: 1, stdout: "", stderr: "ls: \(targetPath): No such file or directory")
                }
            }
            
            // `adb -s <serial> shell mkdir <path>`
            if command == "shell" && arguments.count >= 4 && arguments[3] == "mkdir" {
                let dirPath = unquoteShellArg(arguments.last ?? "")
                state.withLock { s in
                    let parent = (dirPath as NSString).deletingLastPathComponent
                    let name = (dirPath as NSString).lastPathComponent
                    let currentLs = s.simulatedLsOutputs[parent] ?? ""
                    s.simulatedLsOutputs[parent] = currentLs + "\ndrwxrwx--x 2 root sdcard_rw 4096 2026-10-30 00:00 \(name)/"
                    s.simulatedLsOutputs[dirPath] = ""
                }
                return ADBCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
            
            // `adb -s <serial> shell rm [-rf/-d] <path>`
            if command == "shell" && arguments.count >= 4 && arguments[3] == "rm" {
                let target = unquoteShellArg(arguments.last ?? "")
                state.withLock { s in
                    s.simulatedLsOutputs.removeValue(forKey: target)
                    s.mockStorageFiles.removeValue(forKey: target)
                }
                return ADBCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
            
            // `adb -s <serial> shell mv <old> <new>`
            if command == "shell" && arguments.count >= 5 && arguments[3] == "mv" {
                let old = unquoteShellArg(arguments[4])
                let new = unquoteShellArg(arguments[5])
                state.withLock { s in
                    if let content = s.simulatedLsOutputs.removeValue(forKey: old) {
                        s.simulatedLsOutputs[new] = content
                    }
                    if let fileData = s.mockStorageFiles.removeValue(forKey: old) {
                        s.mockStorageFiles[new] = fileData
                    }
                }
                return ADBCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
            
            // `adb -s <serial> shell cp [-r] <source> <dest>`
            if command == "shell" && arguments.count >= 5 && arguments[3] == "cp" {
                let src = unquoteShellArg(arguments[arguments.count - 2])
                let dest = unquoteShellArg(arguments[arguments.count - 1])
                state.withLock { s in
                    if let content = s.simulatedLsOutputs[src] {
                        s.simulatedLsOutputs[dest] = content
                    }
                    if let fileData = s.mockStorageFiles[src] {
                        s.mockStorageFiles[dest] = fileData
                    }
                }
                return ADBCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
            
            // `adb -s <serial> push <local> <remote>`
            if command == "push" && arguments.count >= 5 {
                let pushErr = state.withLock { $0.simulatedPushError }
                if let err = pushErr {
                    return ADBCommandResult(exitCode: 1, stdout: "", stderr: err)
                }
                
                let localPath = arguments[3]
                let remotePath = arguments[4]
                
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: localPath, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        state.withLock { s in
                            s.simulatedLsOutputs[remotePath] = ""
                            let parent = (remotePath as NSString).deletingLastPathComponent
                            let name = (remotePath as NSString).lastPathComponent
                            let cur = s.simulatedLsOutputs[parent] ?? ""
                            s.simulatedLsOutputs[parent] = cur + "\ndrwxrwx--x 2 root sdcard_rw 4096 2026-10-31 00:00 \(name)/"
                        }
                        return ADBCommandResult(exitCode: 0, stdout: "\(localPath): 1 directory pushed, 0 skipped. 30.5 MB/s", stderr: "")
                    } else if let localData = FileManager.default.contents(atPath: localPath) {
                        state.withLock { s in
                            s.mockStorageFiles[remotePath] = localData
                        }
                        return ADBCommandResult(exitCode: 0, stdout: "\(localPath): 1 file pushed, 0 skipped. 30.5 MB/s (\(localData.count) bytes in 0.001s)", stderr: "")
                    }
                }
                return ADBCommandResult(exitCode: 1, stdout: "", stderr: "adb: error: cannot stat '\(localPath)': No such file or directory")
            }
            
            // `adb -s <serial> pull <remote> <local>`
            if command == "pull" && arguments.count >= 5 {
                let pullErr = state.withLock { $0.simulatedPullError }
                if let err = pullErr {
                    return ADBCommandResult(exitCode: 1, stdout: "", stderr: err)
                }
                
                let remotePath = arguments[3]
                let localPath = arguments[4]
                
                let remoteData = state.withLock { s -> Data? in
                    s.mockStorageFiles[remotePath]
                }
                
                if let data = remoteData {
                    try? data.write(to: URL(fileURLWithPath: localPath))
                    return ADBCommandResult(exitCode: 0, stdout: "\(remotePath): 1 file pulled, 0 skipped. 35.2 MB/s (\(data.count) bytes in 0.001s)", stderr: "")
                }
                
                let isDir = state.withLock { s in
                    s.simulatedLsOutputs[remotePath] != nil || remotePath == "/sdcard" || remotePath == "/sdcard/Download" || remotePath.hasSuffix("/")
                }
                if isDir {
                    try? FileManager.default.createDirectory(atPath: localPath, withIntermediateDirectories: true)
                    return ADBCommandResult(exitCode: 0, stdout: "\(remotePath): 1 directory pulled. 35.2 MB/s", stderr: "")
                }
                
                return ADBCommandResult(exitCode: 1, stdout: "", stderr: "adb: error: failed to stat remote object '\(remotePath)': No such file or directory")
            }
        }
        
        return ADBCommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}
