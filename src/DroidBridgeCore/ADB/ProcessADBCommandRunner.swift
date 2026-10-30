import Foundation

/// Safe, production-ready implementation of ADBCommandRunner using Foundation.Process.
/// Passes exact argument arrays directly to the executable without shell interpolation.
public final class ProcessADBCommandRunner: ADBCommandRunner, @unchecked Sendable {
    public let configuration: ADBConfiguration
    private let defaultTimeout: TimeInterval
    
    public var adbPath: String {
        configuration.resolveExecutableURL()?.path ?? (configuration.customADBPath ?? "adb")
    }
    
    public init(configuration: ADBConfiguration = ADBConfiguration(), defaultTimeout: TimeInterval = 30.0) {
        self.configuration = configuration
        self.defaultTimeout = defaultTimeout
    }
    
    public func isAvailable() async -> Bool {
        guard let url = configuration.resolveExecutableURL() else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }
    
    public func version() async throws -> String {
        let result = try await run(arguments: ["version"], timeout: 5.0)
        guard result.isSuccess else {
            throw DeviceError.ioError(message: "adb version command failed: \(result.stderr)")
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public func run(arguments: [String], timeout: TimeInterval? = nil) async throws -> ADBCommandResult {
        guard let executableURL = configuration.resolveExecutableURL() else {
            throw DeviceError.ioError(message: "Android Debug Bridge (adb) executable not found. Please install Android Platform Tools or configure custom path.")
        }
        
        let effectiveTimeout = timeout ?? defaultTimeout
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // Asynchronous stream readers to prevent pipe buffer deadlock
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: DeviceError.ioError(message: "Failed to launch adb process: \(error.localizedDescription)"))
                    return
                }
                
                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                    if process.isRunning {
                        process.terminate()
                    }
                }
                
                DispatchQueue.global(qos: .userInitiated).async {
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timeoutTask.cancel()
                    
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    let exitCode = process.terminationStatus
                    
                    continuation.resume(returning: ADBCommandResult(
                        exitCode: exitCode,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
