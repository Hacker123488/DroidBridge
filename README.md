# DroidBridge

> High-Performance macOS Android File Transfer & Finder Integration.

**DroidBridge** is an independent, native macOS application designed to provide seamless bidirectional file management, high-throughput data transfer, and deep Finder integration for Android devices connected via USB or local Wi-Fi.

DroidBridge is engineered as a free, open, and robust alternative to commercial solutions such as MacDroid Pro and discontinued utilities like Google's Android File Transfer.

---

## Key Capabilities

- **Tri-Mode Connectivity:**
  - **USB ADB (Android Debug Bridge) ✅ Implemented (M2):** `adb` CLI binary transport via safe `Foundation.Process` wrapper. Argument-array invocation only. Supports device discovery, authorization status, file listing, upload, download, directory creation, delete, and rename.
  - **Authorized Wireless ADB (Wi-Fi) 🔜 Planned (M2.1):** Cable-free pairing and two-way transfers via Android 11+ mDNS discovery and TLS pairing.
  - **USB MTP (Media Transfer Protocol) 🔜 Planned (M3):** Hassle-free plug-and-play browsing of shared storage without enabling Developer Options.
- **Two-Way File & Directory Transfers:** Complete bidirectional read and write operations for files of any size (including full support for >4 GB files).
- **macOS System & Finder Integration:**
  - Native **FileProvider** extension (`NSFileProviderReplicatedExtension`) allowing Android storage to mount as a drive in Finder.
  - **FinderSync** extension providing contextual menus (*"Send to Android"*) and status badges.
  - Menu Bar status item with quick eject and connection telemetry.
- **Intelligent Transfer Queue:**
  - Asynchronous multi-item queuing with pause, resume, cancel, and priority reordering.
  - Real-time throughput graphs, speed metrics, and dynamic ETA estimation.
  - Automatic post-transfer Android media scanning (`MediaScanner`) so photos and songs appear immediately on the device.
- **Resilient & Fault-Tolerant:** Automatic handling of transient socket drops, device lock screens, and cable pulls with clean state teardown.

---

## Project Structure

```
File_Transfer/
├── docs/                        # Architecture, specs, and test definitions
│   ├── product-spec.md          # Comprehensive product requirements & goals
│   ├── feature-matrix.md        # Competitive benchmark vs MacDroid & OpenMTP
│   ├── architecture.md          # Subsystem design, protocols, and concurrency model
│   ├── investigation-notes.md   # Environmental findings, REA status, and analysis
│   └── acceptance-tests.md      # Test suites, SLAs, and verification scenarios
├── reference/                   # Clean-room specifications, protocol schemas & RFCs
├── evidence/                    # Benchmark traces, protocol captures & test logs
├── notes/                       # Developer notes and architectural decision records (ADRs)
├── src/                         # Swift source code
│   ├── DroidBridgeCore/         # Models, protocols, services, and providers
│   │   ├── Models/              # Domain models (StorageItem, DeviceDescriptor, etc.)
│   │   ├── Protocols/           # DeviceTransport, TransferService, DeviceFileSystem
│   │   ├── Services/            # TransferQueueService, ConnectionManager
│   │   ├── ADB/                 # ✅ M2: ADB CLI transport implementation
│   │   │   ├── ADBConfiguration.swift           # adb binary path resolution
│   │   │   ├── ADBCommandRunner.swift           # Protocol abstraction for adb invocation
│   │   │   ├── ProcessADBCommandRunner.swift    # Production Foundation.Process runner
│   │   │   ├── ADBDeviceDiscoveryService.swift  # Parses adb devices -l
│   │   │   ├── ADBDeviceTransport.swift         # DeviceTransport conformance
│   │   │   ├── ADBFileSystem.swift              # DeviceFileSystem via adb shell
│   │   │   ├── ADBTransferService.swift         # TransferService via adb push/pull
│   │   │   └── CompositeDeviceDiscoveryService.swift
│   │   └── Mock/                # MockDeviceTransport, MockADBCommandRunner (test doubles)
│   └── DroidBridgeApp/          # Native SwiftUI desktop application
│       └── App/                 # DroidBridgeApp entry point and ContentView
├── tests/                       # Unit and integration test suites
│   └── DroidBridgeTestRunner/   # Standalone executable test runner (103 assertions)
├── Package.swift                # Swift Package Manager manifest (macOS 15.0+, Swift 6)
└── README.md                    # Project overview and roadmap
```

---

## Build & Execution Guide

### System Prerequisites
- macOS 15.0 or later (tested on macOS 27.2 Apple Silicon arm64).
- Swift 6.0+ toolchain (Apple Swift 6.4 via Xcode Command Line Tools).
- **For ADB connectivity:** Android Platform Tools containing the `adb` binary.
  ```bash
  # Install via Homebrew (recommended)
  brew install --cask android-platform-tools

  # Or install Android Studio and add to PATH:
  # export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
  ```
  DroidBridge searches for `adb` in PATH, `/usr/local/bin`, `/opt/homebrew/bin`, and `~/Library/Android/sdk/platform-tools/` automatically. If none is found, ADB device discovery reports a clear error; mock/simulated devices remain available.

### Build Commands

```bash
# Build all targets (DroidBridgeCore, DroidBridgeApp, DroidBridgeTestRunner)
swift build --disable-sandbox --scratch-path /tmp/droidbridge-build -Xbuild-tools-swiftc -module-cache-path -Xbuild-tools-swiftc /tmp/clang-cache -Xswiftc -module-cache-path -Xswiftc /tmp/clang-cache

# Run the automated test suite (138 assertions across 17 test suites)
swift run --disable-sandbox --scratch-path /tmp/droidbridge-build -Xbuild-tools-swiftc -module-cache-path -Xbuild-tools-swiftc /tmp/clang-cache -Xswiftc -module-cache-path -Xswiftc /tmp/clang-cache DroidBridgeTestRunner

# Launch the SwiftUI macOS Application
swift run --disable-sandbox --scratch-path /tmp/droidbridge-build -Xbuild-tools-swiftc -module-cache-path -Xbuild-tools-swiftc /tmp/clang-cache -Xswiftc -module-cache-path -Xswiftc /tmp/clang-cache DroidBridgeApp
```

---

## Toolkit & Environment Status

- **REA Toolkit (`morluto/rea`):**
  - **Status:** Checked and verified; currently **not installed** in the local environment.
  - **Documented Setup:** Verified upstream setup requirements (`npx rea-agents setup`). Node.js (v24.14.1) is available on the host. In keeping with developer safety protocols, the tool has not been automatically installed into global agent configurations.
- **Reference Application Assessment (`MacDroid.app`):**
  - Found installed at `/Applications/MacDroid.app` (Mac App Store edition).
  - Inspected strictly at the metadata/bundle level to understand modern macOS integration patterns (FileProvider + FinderSync + libmtp + ADB).
  - **Strict Clean-Room Policy:** No proprietary code, license validation mechanisms, or copyrighted assets have been decompiled, copied, or bypassed.

---

## Architectural Principles

```mermaid
graph LR
    subgraph Host ["macOS Workstation"]
        UI["SwiftUI Main App / MenuBar"]
        FP["FileProvider / FinderSync"]
        Core["DroidBridge Engine & Transfer Queue"]
    end

    subgraph Transport ["Protocol Abstraction"]
        MTP["MTP Transport (USB)"]
        ADB["ADB Transport (USB)"]
        WIFI["Wireless ADB (Wi-Fi TLS)"]
    end

    subgraph Device ["Android Device"]
        MTPDev["MTP Storage"]
        ADBDev["ADB Daemon (USB)"]
        WiFiDev["ADB Daemon (Wi-Fi)"]
    end

    UI --> Core
    FP --> Core
    Core --> MTP --> MTPDev
    Core --> ADB --> ADBDev
    Core --> WIFI --> WiFiDev
```

For detailed architectural schematics, see [`docs/architecture.md`](file:///Volumes/New%20Volume%20(E)/Coding/projects/File_Transfer/docs/architecture.md).

---

## Documentation Index

1. [Product Specification](file:///Volumes/New%20Volume%20(E)/Coding/projects/File_Transfer/docs/product-spec.md)
2. [Feature Comparison Matrix](file:///Volumes/New%20Volume%20(E)/Coding/projects/File_Transfer/docs/feature-matrix.md)
3. [Architecture & System Design](file:///Volumes/New%20Volume%20(E)/Coding/projects/File_Transfer/docs/architecture.md)
4. [Investigation & Environmental Notes](file:///Volumes/New%20Volume%20(E)/Coding/projects/File_Transfer/docs/investigation-notes.md)
5. [Acceptance Test Plan](file:///Volumes/New%20Volume%20(E)/Coding/projects/File_Transfer/docs/acceptance-tests.md)

---

## Development Milestones

- [x] **Milestone 0: Workspace Discovery & Documentation Baseline**
  - Inspection of workspace, toolkit verification, clean-room investigation notes.
  - Architecture blueprint, product spec, feature matrix, and acceptance tests.
- [x] **Milestone 1: Mock Harness & Core Transport Protocol Interfaces**
  - Abstract protocols: `DeviceTransport`, `DeviceFileSystem`, `TransferService`, `TransferQueue`, `ConnectionManagerProtocol`, `DeviceDiscoveryService`.
  - Concrete mock provider (`MockDeviceTransport`) with isolated temporary filesystem and seeded Android storage (`/sdcard`, `DCIM`, `Download`, `Music`, `Documents`).
  - Security hardening: Path traversal validation (`..` and escaping checks) and conflict resolution policies.
  - `TransferQueueService`: Actor-isolated job queue with state transitions and progress reporting.
  - `DroidBridgeApp`: Native SwiftUI application with simulated device explorer and Dev Mock toggle.
  - Automated test harness (`DroidBridgeTestRunner`): 50/50 assertions passing across 9 test suites.
- [x] **Milestone 2: ADB USB Connectivity**
  - Production `ProcessADBCommandRunner`: safe `Foundation.Process` wrapper; argument arrays only; timeout enforcement; cancellation.
  - `ADBDeviceDiscoveryService`: parses `adb devices -l`; handles `authorized`, `unauthorized`, `offline`, multi-device, Wi-Fi (IP:PORT) serials.
  - `ADBFileSystem`: `adb shell ls/mkdir/rm/mv`; Unicode/spaces handled; path traversal validation.
  - `ADBTransferService`: `adb push` / `adb pull`; post-transfer verification; conflict resolution; error mapping.
  - `ADBDeviceTransport`: `DeviceTransport` conformance; `Synchronization.Mutex<T>` thread safety; authorization check before connect.
  - `CompositeDeviceDiscoveryService`: aggregates ADB + Mock discovery; real and simulated devices visually distinguished.
  - `MockADBCommandRunner`: deterministic test double; all ADB command surfaces covered.
- [x] **Milestone 2.1: Hardware Browsing Fix & File Transfer UI**
  - Follow Android symbolic links (`ls -la -L -p` / `ls -ld -L -p`): `/sdcard` recognized as directory, `/sdcard/Download` contents listed cleanly.
  - Implemented interactive transfer UI in `ContentView`: "Upload File..." toolbar button with `NSOpenPanel`, individual row Download button and right-click context menu with `NSSavePanel`, real-time transfer progress bar, cancellation, and error display.
  - Fixed `ADBConfiguration` override: explicit `customADBPath` returns executable or `nil`, preventing silent fallback to PATH/Homebrew when an invalid custom path was configured.
  - Automated test harness: **138/138 assertions passing** across 17 test suites (including symlink resolution, UI transfer integration, serial targeting, and error handling).
  - ⚠️ Physical Android device (Realme RMX3092) manual end-to-end verification checklist prepared; automated tests use injected runner.
- [ ] **Milestone 3: MTP USB Protocol Integration**
  - Integration with `libmtp` / USB bulk endpoints with strict actor-based concurrency.
- [ ] **Milestone 4: Transfer Queue & Scheduler**
  - Progress calculation, speed monitoring, pause/resume, and collision resolution.
- [ ] **Milestone 5: macOS UI & Finder Integration**
  - SwiftUI desktop browser, Menu Bar extra, FinderSync and FileProvider extensions.

---

## Ethical & Clean-Room Standards

DroidBridge is developed under strict clean-room software engineering standards. All protocol communications (MTP and ADB) rely exclusively on publicly documented standards (ISO 15740 / PTP, AOSP Android Open Source Project specifications) and standard open-source libraries (`libusb`, `libmtp`). No proprietary code, trade secrets, or licensing mechanisms from commercial tools are incorporated.
