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
    
    /// Escapes an argument safely for POSIX shell execution on Android (toybox/toolbox).
    public static func escapeForShell(_ string: String) -> String {
        let specialChars = CharacterSet(charactersIn: " \t\n\r'\"()[]{}*?~$\\!;&|<>#^")
        if string.rangeOfCharacter(from: specialChars) != nil {
            return "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return string
    }
    
    /// Parses a single line of `ls -la -p` or `ls -ld -p` preserving spaces in filenames.
    public static func parseLsLine(_ line: String) -> (permissions: String, size: Int64, rawName: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.starts(with: "total ") {
            return nil
        }
        
        var tokens: [(string: String, range: Range<String.Index>)] = []
        var searchIndex = trimmed.startIndex
        
        while searchIndex < trimmed.endIndex && tokens.count < 8 {
            while searchIndex < trimmed.endIndex && trimmed[searchIndex].isWhitespace {
                searchIndex = trimmed.index(after: searchIndex)
            }
            if searchIndex >= trimmed.endIndex { break }
            let tokenStart = searchIndex
            while searchIndex < trimmed.endIndex && !trimmed[searchIndex].isWhitespace {
                searchIndex = trimmed.index(after: searchIndex)
            }
            let tokenEnd = searchIndex
            let tokenStr = String(trimmed[tokenStart..<tokenEnd])
            tokens.append((tokenStr, tokenStart..<tokenEnd))
        }
        
        guard tokens.count >= 7 else { return nil }
        
        let permissions = tokens[0].string
        let size = Int64(tokens[4].string) ?? 0
        let dateToken = tokens[5].string
        
        let filenameStartIndex: String.Index
        if dateToken.contains("-") {
            // ISO date: date (token 5), time (token 6) -> name starts after token 6
            guard tokens.count >= 7 else { return nil }
            var idx = tokens[6].range.upperBound
            while idx < trimmed.endIndex && trimmed[idx].isWhitespace {
                idx = trimmed.index(after: idx)
            }
            filenameStartIndex = idx
        } else {
            // BSD date: month (token 5), day (token 6), time/year (token 7) -> name starts after token 7
            guard tokens.count >= 8 else { return nil }
            var idx = tokens[7].range.upperBound
            while idx < trimmed.endIndex && trimmed[idx].isWhitespace {
                idx = trimmed.index(after: idx)
            }
            filenameStartIndex = idx
        }
        
        guard filenameStartIndex <= trimmed.endIndex else { return nil }
        var rawName = String(trimmed[filenameStartIndex...])
        
        if let arrowRange = rawName.range(of: " -> ") {
            rawName = String(rawName[..<arrowRange.lowerBound])
        }
        
        return (permissions, size, rawName)
    }
    
    public func listDirectory(at path: String) async throws -> [StorageItem] {
        let validPath = try Self.validateRemotePath(path)
        let escapedPath = Self.escapeForShell(validPath)
        
        let result = try await runner.run(arguments: ["-s", serial, "shell", "ls", "-la", "-L", "-p", escapedPath])
        
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
        let escapedPath = Self.escapeForShell(validPath)
        
        let result = try await runner.run(arguments: ["-s", serial, "shell", "ls", "-ld", "-L", "-p", escapedPath])
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
        if let parsed = Self.parseLsLine(trimmed) {
            var rawName = parsed.rawName
            let isDir = parsed.permissions.hasPrefix("d") || rawName.hasSuffix("/")
            if rawName.hasSuffix("/") {
                rawName = String(rawName.dropLast())
            }
            let displayName = (rawName as NSString).lastPathComponent
            return StorageItem(
                id: displayName,
                name: displayName,
                path: validPath,
                size: isDir ? 0 : parsed.size,
                modifiedDate: Date(),
                isDirectory: isDir,
                permissions: StoragePermissions(
                    canRead: parsed.permissions.contains("r"),
                    canWrite: parsed.permissions.contains("w"),
                    canDelete: parsed.permissions.contains("w")
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
        let result = try await runner.run(arguments: ["-s", serial, "shell", "mkdir", Self.escapeForShell(targetPath)])
        
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
        let result = try await runner.run(arguments: ["-s", serial, "shell", "rm", rmFlag, Self.escapeForShell(validPath)])
        
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
        
        let result = try await runner.run(arguments: ["-s", serial, "shell", "mv", Self.escapeForShell(validPath), Self.escapeForShell(targetPath)])
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
    
    public func moveItem(from sourcePath: String, to destinationPath: String) async throws -> StorageItem {
        let validSource = try Self.validateRemotePath(sourcePath)
        let validDest = try Self.validateRemotePath(destinationPath)
        
        // Ensure source exists
        _ = try await getItem(at: validSource)
        
        let result = try await runner.run(arguments: ["-s", serial, "shell", "mv", Self.escapeForShell(validSource), Self.escapeForShell(validDest)])
        if !result.isSuccess {
            let err = result.stderr.lowercased()
            if err.contains("no such file") {
                throw DeviceError.itemNotFound(path: validSource)
            }
            if err.contains("file exists") {
                throw DeviceError.itemAlreadyExists(path: validDest)
            }
            
            // Safe move fallback: copy first, verify destination, and only then delete source
            let cpResult = try await runner.run(arguments: ["-s", serial, "shell", "cp", "-r", Self.escapeForShell(validSource), Self.escapeForShell(validDest)])
            guard cpResult.isSuccess else {
                throw DeviceError.ioError(message: "Failed to move item: \(result.stderr) (copy fallback failed: \(cpResult.stderr))")
            }
            
            // Verify destination exists before removing source
            let destinationItem = try await getItem(at: validDest)
            try await deleteItem(at: validSource, isRecursive: true)
            return destinationItem
        }
        
        return try await getItem(at: validDest)
    }
    
    public func copyItem(from sourcePath: String, to destinationPath: String) async throws -> StorageItem {
        let validSource = try Self.validateRemotePath(sourcePath)
        let validDest = try Self.validateRemotePath(destinationPath)
        
        // Ensure source exists
        _ = try await getItem(at: validSource)
        
        let result = try await runner.run(arguments: ["-s", serial, "shell", "cp", "-r", Self.escapeForShell(validSource), Self.escapeForShell(validDest)])
        if !result.isSuccess {
            let err = result.stderr.lowercased()
            if err.contains("no such file") {
                throw DeviceError.itemNotFound(path: validSource)
            }
            if err.contains("file exists") {
                throw DeviceError.itemAlreadyExists(path: validDest)
            }
            throw DeviceError.ioError(message: "Failed to copy item: \(result.stderr)")
        }
        
        return try await getItem(at: validDest)
    }
    
    /// Parses `ls -la -p` lines into structured StorageItems preserving filenames with spaces.
    public static func parseLsOutput(_ output: String, parentPath: String) -> [StorageItem] {
        var items: [StorageItem] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            guard let parsed = parseLsLine(line) else { continue }
            
            var rawName = parsed.rawName
            if rawName == "./" || rawName == "../" || rawName == "." || rawName == ".." {
                continue
            }
            
            let isDir = parsed.permissions.hasPrefix("d") || rawName.hasSuffix("/")
            if rawName.hasSuffix("/") {
                rawName = String(rawName.dropLast())
            }
            
            let itemPath = parentPath.hasSuffix("/") ? "\(parentPath)\(rawName)" : "\(parentPath)/\(rawName)"
            
            items.append(StorageItem(
                id: rawName,
                name: rawName,
                path: itemPath,
                size: isDir ? 0 : parsed.size,
                modifiedDate: Date(),
                isDirectory: isDir,
                permissions: StoragePermissions(
                    canRead: parsed.permissions.contains("r"),
                    canWrite: parsed.permissions.contains("w"),
                    canDelete: parsed.permissions.contains("w")
                )
            ))
        }
        
        return items
    }
}
