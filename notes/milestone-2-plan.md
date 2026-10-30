# Milestone 2 Implementation Plan: Real Android ADB Connectivity

## 1. Environmental Findings & Prerequisites
- **Host OS:** macOS 27.2 (Darwin arm64).
- **Toolchain:** Apple Swift 6.4 (CommandLineTools).
- **ADB Availability:** `adb` is currently not present in the system PATH or standard directories (`~/Library/Android/sdk/platform-tools/`).
- **Official Installation Options for User:**
  1. **Homebrew:** `brew install --cask android-platform-tools`
  2. **Official Google Android Developer SDK:** Download Platform Tools for Mac from `https://developer.android.com/tools/releases/platform-tools` and extract to `~/Library/Android/sdk/platform-tools/`.
  3. **DroidBridge Configuration:** Provide `ADBConfiguration` with an explicit `adbPath` property and multi-path fallback detection.
- **Physical Device Status:** No physical USB Android devices currently attached to the system.

## 2. Interface Impact Analysis
- **`DeviceTransport`:** Compatible without breaking changes.
- **`DeviceFileSystem`:** Compatible without breaking changes.
- **`TransferService`:** Compatible without breaking changes.
- **`ConnectionManagerProtocol` & `ConnectionManager`:**
  - Extended to support connecting real `.usbADB` devices via `ADBDeviceTransport`.
  - Added dependency injection for `ADBCommandRunner` and `ADBConfiguration`.
- **`DeviceDiscoveryService`:**
  - Introduce `ADBDeviceDiscoveryService` conforming to `DeviceDiscoveryService`.
  - Introduce `CompositeDeviceDiscoveryService` that combines both real ADB discovery and optional simulated mock devices.

## 3. Subsystem Architecture & Components to Build
1. **`ADBConfiguration` & `ADBCommandRunner` (`src/DroidBridgeCore/ADB/`):**
   - `ADBCommandRunner` protocol & `ADBCommandResult` struct.
   - `ProcessADBCommandRunner`: Production runner using Swift `Process`, passing argument arrays (`[String]`), piped stderr/stdout, timeout enforcement, and cancellation safety.
   - `MockADBCommandRunner`: Deterministic mock runner for automated unit testing without physical hardware.
2. **`ADBDeviceDiscoveryService` (`src/DroidBridgeCore/ADB/`):**
   - Executes `adb devices -l`.
   - Parses device statuses (`device`, `unauthorized`, `offline`, `unauthorized`).
   - Extracts device product and model labels.
3. **`ADBDeviceTransport` (`src/DroidBridgeCore/ADB/`):**
   - Implements `DeviceTransport`. Enforces `-s <serial>` targeting for all operations.
4. **`ADBFileSystem` (`src/DroidBridgeCore/ADB/`):**
   - Implements `DeviceFileSystem` via `adb shell` POSIX operations.
   - Sanitizes and validates paths (blocks `..` traversal).
   - Handles Unicode and whitespace in filenames.
5. **`ADBTransferService` (`src/DroidBridgeCore/ADB/`):**
   - Implements `TransferService` via `adb push` and `adb pull`.
   - Streaming I/O with process lifecycle controls.
   - Verification of transfer completion before returning.
6. **Testing Harness (`tests/`):**
   - Unit tests covering missing ADB, output parsing, argument safety, path traversal, Unicode/spaces, timeouts, cancellation, conflict resolution, and disconnection.
   - Verification that all 50 existing Milestone 1 tests continue passing.
