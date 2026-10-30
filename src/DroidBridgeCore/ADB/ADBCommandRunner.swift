import Foundation

/// Encapsulates the execution result of an ADB command.
public struct ADBCommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    
    public var isSuccess: Bool {
        exitCode == 0
    }
    
    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Abstract contract for executing ADB operations behind a safe, testable abstraction.
public protocol ADBCommandRunner: Sendable {
    /// Resolved path to the adb binary or identifier.
    var adbPath: String { get }
    
    /// Checks whether ADB is available and callable.
    func isAvailable() async -> Bool
    
    /// Queries the installed ADB version string (e.g. "Android Debug Bridge version 1.0.41").
    func version() async throws -> String
    
    /// Executes an ADB command with exact argument array.
    /// Never constructs shell strings or uses `/bin/sh -c`.
    func run(arguments: [String], timeout: TimeInterval?) async throws -> ADBCommandResult
}

extension ADBCommandRunner {
    public func run(arguments: [String]) async throws -> ADBCommandResult {
        try await run(arguments: arguments, timeout: nil)
    }
}
