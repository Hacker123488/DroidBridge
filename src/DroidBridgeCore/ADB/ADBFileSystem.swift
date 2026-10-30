import Foundation

/// Implementation of DeviceFileSystem backed by ADB shell operations.
public final class ADBFileSystem: DeviceFileSystem, @unchecked Sendable {
    public let serial: String
    public let runner: any ADBCommandRunner
    weak var transport: DeviceTransport?
    
    public init(serial: String, runner: any ADBCommandRunner, transport: DeviceTransport? = nil) {
        self.serial = serial
        self.runner = runner
        self.transport = transport
    }
    
    /// Sanitizes and validates remote Android path against traversal and injection attacks.
    public static func validateRemotePath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw DeviceError.invalidPath(path: path)
        }
        
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        for component in components {
            if component == ".." {
                throw DeviceError.pathTraversalForbidden(path: path)
            }
        }
        
        // Ensure path starts with /
        if !trimmed.hasPrefix("/") {
            return "/" + trimmed
        }
        return trimmed
    }
    
    public func listDirectory(at path: String) async throws -> [StorageItem] {
        let validPath = try Self.validateRemotePath(path)
        
        let result = try await runner.run(arguments: ["-s", serial, "shell", "ls", "-la", "-L", "-p", validPath])
        
        if !result.isSuccess {
            let err = result.stderr.lowercased() + result.stdout.lowercased()
            if err.contains("no such file") || err.contains("not found") {
                throw DeviceError.itemNotFound(path: validPath)
            }
            if err.contains("permission denied") {
                throw DeviceError.permissionDenied(path: validPath)
            }
            throw DeviceError.ioError(message: "Failed to list directory: \(result.stderr)")
        }
        
        return Self.parseLsOutput(result.stdout, parentPath: validPath)
    }
    
    public func getItem(at path: String) async throws -> StorageItem {
        let validPath = try Self.validateRemotePath(path)
        
        let result = try await runner.run(arguments: ["-s", serial, "shell", "ls", "-ld", "-L", "-p", validPath])
        if !result.isSuccess {
            let err = result.stderr.lowercased() + result.stdout.lowercased()
            if err.contains("no such file") || err.contains("not found") {
                throw DeviceError.itemNotFound(path: validPath)
            }
            if err.contains("permission denied") {
                throw DeviceError.permissionDenied(path: validPath)
            }
            throw DeviceError.ioError(message: "Failed to stat item: \(result.stderr)")
        }
        
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count >= 8 {
            let permissions = String(parts[0])
            let size = Int64(parts[4]) ?? 0
            let nameParts = parts.dropFirst(7)
            var rawName = nameParts.joined(separator: " ")
            if let arrowRange = rawName.range(of: " -> ") {
                rawName = String(rawName[..<arrowRange.lowerBound])
            }
            let isDir = permissions.hasPrefix("d") || rawName.hasSuffix("/")
            if rawName.hasSuffix("/") {
                rawName = String(rawName.dropLast())
            }
            let displayName = (rawName as NSString).lastPathComponent
            return StorageItem(
                id: displayName,
                name: displayName,
                path: validPath,
                size: isDir ? 0 : size,
                modifiedDate: Date(),
                isDirectory: isDir,
                permissions: StoragePermissions(
                    canRead: permissions.contains("r"),
                    canWrite: permissions.contains("w"),
                    canDelete: permissions.contains("w")
                )
            )
        }
        
        let isDir = validPath.hasSuffix("/")
        let name = (validPath as NSString).lastPathComponent
        return StorageItem(
            id: name,
            name: name,
            path: validPath,
            size: 0,
            modifiedDate: Date(),
            isDirectory: isDir
        )
    }
    
    public func createDirectory(at path: String, name: String) async throws -> StorageItem {
        let validParent = try Self.validateRemotePath(path)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName.contains("/") || trimmedName == ".." {
            throw DeviceError.invalidPath(path: name)
        }
        
        let targetPath = validParent.hasSuffix("/") ? "\(validParent)\(trimmedName)" : "\(validParent)/\(trimmedName)"
        let result = try await runner.run(arguments: ["-s", serial, "shell", "mkdir", targetPath])
        
        if !result.isSuccess {
            let err = result.stderr.lowercased()
            if err.contains("file exists") {
                throw DeviceError.itemAlreadyExists(path: targetPath)
            }
            if err.contains("permission denied") {
                throw DeviceError.permissionDenied(path: targetPath)
            }
            throw DeviceError.ioError(message: "Failed to create directory: \(result.stderr)")
        }
        
        return StorageItem(
            id: trimmedName,
            name: trimmedName,
            path: targetPath,
            size: 0,
            modifiedDate: Date(),
            isDirectory: true
        )
    }
    
    public func deleteItem(at path: String, isRecursive: Bool) async throws {
        let validPath = try Self.validateRemotePath(path)
        
        let rmFlag = isRecursive ? "-rf" : "-d"
        let result = try await runner.run(arguments: ["-s", serial, "shell", "rm", rmFlag, validPath])
        
        if !result.isSuccess {
            let err = result.stderr.lowercased()
            if err.contains("no such file") {
                throw DeviceError.itemNotFound(path: validPath)
            }
            if err.contains("permission denied") {
                throw DeviceError.permissionDenied(path: validPath)
            }
            throw DeviceError.ioError(message: "Failed to delete item: \(result.stderr)")
        }
    }
    
    public func renameItem(at path: String, newName: String) async throws -> StorageItem {
        let validPath = try Self.validateRemotePath(path)
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName.contains("/") || trimmedName == ".." {
            throw DeviceError.invalidPath(path: newName)
        }
        
        let parent = (validPath as NSString).deletingLastPathComponent
        let targetPath = parent.hasSuffix("/") ? "\(parent)\(trimmedName)" : "\(parent)/\(trimmedName)"
        
        let result = try await runner.run(arguments: ["-s", serial, "shell", "mv", validPath, targetPath])
        if !result.isSuccess {
            let err = result.stderr.lowercased()
            if err.contains("no such file") {
                throw DeviceError.itemNotFound(path: validPath)
            }
            if err.contains("file exists") {
                throw DeviceError.itemAlreadyExists(path: targetPath)
            }
            throw DeviceError.ioError(message: "Failed to rename item: \(result.stderr)")
        }
        
        return try await getItem(at: targetPath)
    }
    
    /// Parses `ls -la -p` lines into structured StorageItems.
    public static func parseLsOutput(_ output: String, parentPath: String) -> [StorageItem] {
        var items: [StorageItem] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.starts(with: "total ") {
                continue
            }
            
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 8 else { continue }
            
            let permissions = String(parts[0])
            let size = Int64(parts[4]) ?? 0
            
            let nameParts = parts.dropFirst(7)
            var rawName = nameParts.joined(separator: " ")
            if let arrowRange = rawName.range(of: " -> ") {
                rawName = String(rawName[..<arrowRange.lowerBound])
            }
            
            if rawName == "./" || rawName == "../" || rawName == "." || rawName == ".." {
                continue
            }
            
            let isDir = permissions.hasPrefix("d") || rawName.hasSuffix("/")
            if rawName.hasSuffix("/") {
                rawName = String(rawName.dropLast())
            }
            
            let itemPath = parentPath.hasSuffix("/") ? "\(parentPath)\(rawName)" : "\(parentPath)/\(rawName)"
            
            items.append(StorageItem(
                id: rawName,
                name: rawName,
                path: itemPath,
                size: isDir ? 0 : size,
                modifiedDate: Date(),
                isDirectory: isDir,
                permissions: StoragePermissions(
                    canRead: permissions.contains("r"),
                    canWrite: permissions.contains("w"),
                    canDelete: permissions.contains("w")
                )
            ))
        }
        
        return items
    }
}
