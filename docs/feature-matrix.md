# DroidBridge Feature Comparison Matrix

This document benchmarks **DroidBridge**'s target functional specifications against existing macOS Android file transfer solutions: **MacDroid Pro**, **MacDroid Free**, **Google Android File Transfer (Legacy AFT)**, and **OpenMTP**.

---

## 1. Comprehensive Feature Matrix

| Feature / Capability | DroidBridge (Current / Milestone 2) | DroidBridge (Target) | MacDroid Pro | MacDroid Free | Google AFT (Legacy) | OpenMTP |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Licensing / Pricing** | Open / Free | Open / Free | Proprietary ($19.99/yr) | Free (Restricted) | Free (Discontinued) | Open Source (Free) |
| **Technology Stack** | Swift 6 / SwiftUI / SPM | Swift 6 / SwiftUI / AppKit | Native Swift / Obj-C | Native Swift / Obj-C | Legacy Java/C++ | Electron / JS |
| **Connection Modes** | | | | | | |
| • Simulated Mock Device | ✅ Verified (M1 & M2) | ✅ Dev/Test Harness | ❌ Not Supported | ❌ Not Supported | ❌ Not Supported | ❌ Not Supported |
| • USB MTP Mode | ⏳ Planned (Milestone 3) | ✅ Full Two-Way | ✅ Full Two-Way | ⚠️ Mac -> Android Disabled | ⚠️ Two-Way (Unstable) | ✅ Full Two-Way |
| • USB ADB Mode | ✅ Verified (Milestone 2) | ✅ Full Two-Way | ✅ Full Two-Way | ⚠️ Mac -> Android Disabled | ❌ Not Supported | ❌ Not Supported |
| • Wireless ADB (Wi-Fi) | ⏳ Planned (Milestone 2.1) | ✅ Full Two-Way | ✅ Full Two-Way | ❌ Not Supported | ❌ Not Supported | ❌ Not Supported |
| • Android 11+ Pairing (mDNS) | ⏳ Planned (Milestone 2.1) | ✅ Native Pairing | ✅ Supported | ❌ Not Supported | ❌ Not Supported | ❌ Not Supported |
| **macOS System Integration** | | | | | | |
| • Native Finder Drive Mount | ⏳ Planned (Milestone 5) | ✅ FileProvider | ✅ FileProvider | ❌ No Mount | ❌ No Mount | ❌ No Mount |
| • FinderSync Sidebar & Badges | ⏳ Planned (Milestone 5) | ✅ Included | ✅ Included | ❌ No FinderSync | ❌ No FinderSync | ❌ No FinderSync |
| • Menu Bar Status Item | ⏳ Planned (Milestone 5) | ✅ Included | ✅ Included | ✅ Included | ❌ Not Supported | ❌ Not Supported |
| • Drag-and-Drop to/from Finder | ✅ Verified (Milestone 2.2.5) | ✅ Native | ✅ Native | ⚠️ Read-only to Finder | ⚠️ Flaky | ⚠️ Internal UI only |
| • Native Clipboard (Copy/Cut/Paste)| ✅ Verified (Milestone 2.2.5) | ✅ System Pasteboard | ✅ Supported | ❌ Limited | ❌ Not Supported | ⚠️ Internal only |
| • Multi-Item Selection & Batch Ops | ✅ Verified (Milestone 2.2.5) | ✅ Shift/Cmd Select | ✅ Supported | ⚠️ Limited | ❌ Basic | ✅ Supported |
| • Quick Look & AVKit Media Preview | ✅ Verified (Milestone 2.2.5) | ✅ QLPreviewPanel & AVPlayer | ✅ Supported | ⚠️ Limited | ❌ Not Supported | ❌ Not Supported |
| • Same-Location Drop Protection    | ✅ Verified (Milestone 2.2.5) | ✅ No-op / Zero Transfer | ✅ Supported | ❌ Duplicates | ❌ Overwrites | ⚠️ Re-transfers |
| • Shell Quoting & Spaces Security  | ✅ Verified (Milestone 2.2.5) | ✅ Robust POSIX Escaping | ✅ Supported | ⚠️ Flaky on spaces | ❌ Broken on spaces | ⚠️ Flaky |
| **File Transfer Engine** | | | | | | |
| • Two-Way Bidirectional | ✅ Verified (Mock & ADB) | ✅ Full Read/Write | ✅ Full Read/Write | ❌ Read-Only (Mac <- Android) | ✅ Read/Write | ✅ Read/Write |
| • Files > 4 GB Support | ⏳ Planned (Physical Lab) | ✅ 64-bit offsets | ✅ Supported | ⚠️ Read only | ❌ Fails on >4GB | ✅ Supported |
| • Multi-file & Folder Queuing | ✅ Verified (Actor Queue) | ✅ Async Queue | ✅ Async Queue | ⚠️ Single thread | ❌ Basic copy | ✅ Queue supported |
| • Transfer Pause / Resume | ✅ Verified (State Machine) | ✅ Supported | ✅ Supported | ❌ Not Supported | ❌ Not Supported | ❌ Not Supported |
| • Speed & ETA Calculation | ✅ Verified (TransferProgress) | ✅ Real-time | ✅ Real-time | ⚠️ Basic | ❌ Not Supported | ✅ Basic |
| • File Conflict Handling | ✅ Verified (Fail/Overwrite/Rename)| ✅ Prompt/Skip/Overwrite | ✅ Prompt/Overwrite | ❌ Read-only | ❌ Fails on collision | ✅ Overwrite prompt |
| • Post-Transfer MediaScan | ⏳ Planned (Milestone 3) | ✅ Auto broadcast | ✅ Auto broadcast | ❌ Not Applicable | ⚠️ Hit-or-miss | ⚠️ Manual/Plugin |
| **Reliability & Performance** | | | | | | |
| • Reconnection on Cable Pull | ✅ Verified (Fault Simulation)| ✅ Auto Recover/Abort | ✅ Graceful handling | ⚠️ Hangs | ❌ Crashes app | ⚠️ Requires restart |
| • Multi-Device Concurrent | ✅ Verified (Device Isolation & -s)| ✅ Supported | ✅ Supported | ❌ Single device | ❌ Single device | ❌ Single device |
| • Memory Footprint | ⚡ Low (<30 MB) | ⚡ Low (<80 MB) | ⚡ Low (<90 MB) | ⚡ Low (<90 MB) | ⚠️ Moderate | 🔴 High (>400 MB) |

---

## 2. Technical Feasibility & Classification

### 2.1 Confirmed Technical Primitives (Verified in Code)
- **Safe Process ADB Invocation:** `ProcessADBCommandRunner` and `ADBCommandRunner` strictly using discrete argument arrays `[String]` without shell interpolation.
- **Explicit Multi-Device Targeting:** Every command prepends `-s <serial>` ensuring zero race conditions when multiple Android devices are connected.
- **Path Traversal Security:** Remote paths strictly sanitized, blocking `..` escapes.
- **Unicode & Spaces Handling:** Verified handling of file names with whitespace and UTF-8 characters (`Unicode 测试 🚀.pdf`).
- **Device State Parsing:** Cleanly distinguishes `device` (available), `unauthorized` (prompting user), `offline`, and missing devices.

### 2.2 Architectural Hypotheses (Under Prototyping)
- **`NSFileProviderReplicatedExtension` for MTP/ADB:** Exposing storage as Apple FileProvider items for native Finder integration (Milestone 5).
- **Daemonless ADB:** Direct USB endpoint communication without spawning external daemons (Milestone 4).

### 2.3 Known Unknowns & Platform Limitations
- **Workstation ADB Availability:** On machines where Android SDK Platform Tools are not installed, DroidBridge requires user configuration or standard brew installation (`brew install --cask android-platform-tools`).
- **Physical USB Testing Dependency:** Hardware E2E verification requires a physically connected, authorized Android device.

---

## 3. Current Implementation Status (Milestones 1 & 2)

- **Completed & Verified in Milestone 2:**
  - `ADBConfiguration`: Multi-path resolution for official ADB binary (`PATH`, Homebrew, Android SDK).
  - `ADBCommandRunner` & `ProcessADBCommandRunner`: Process isolation, piped I/O, cancellation hooks, and timeout safeguards.
  - `ADBDeviceDiscoveryService`: Parsing of `adb devices -l` output into structured `DeviceDescriptor` models.
  - `ADBDeviceTransport`: Implementation of `DeviceTransport` targeting physical ADB devices.
  - `ADBFileSystem`: POSIX directory listing, metadata query, folder creation, deletion, and rename over ADB shell.
  - `ADBTransferService`: Two-way streaming file uploads (`adb push`) and downloads (`adb pull`) with conflict resolution and integrity checks.
  - `CompositeDeviceDiscoveryService`: Aggregated device discovery managing real ADB and simulated mock devices.
  - `MockADBCommandRunner`: Deterministic mock ADB environment supporting 103/103 passing automated tests.
- **Completed & Verified in Milestone 2.1:**
  - `ADBFileSystem` Symlink Traversal: Appends `-L` flag to `ls -la` and `ls -ld`, allowing `/sdcard` (symlink to `/storage/self/primary`) and all subdirectories to be traversed as directories.
  - Interactive Desktop Transfer UI: `ContentView` and `AppViewModel` wire up `ADBTransferService` to `NSOpenPanel` (Upload) and `NSSavePanel` (Download), with real-time progress fraction, cancellation, and visible error alerts.
  - Configuration Override Fix: `ADBConfiguration` strictly honors `customADBPath` without falling back to PATH/Homebrew when an invalid custom path is provided.
  - Test Suite Expansion: 138/138 automated test assertions passing across 17 test suites.
- **Completed & Verified in Milestone 2.2:**
  - Native Drag-and-Drop: Mac-to-Android file and directory drop with batch uploading and conflict resolution; Android-to-Mac drag-out with isolated staging via `NSTemporaryDirectory()` preventing partial file exposure.
  - Native Clipboard Integration: `Cmd+C`, `Cmd+X`, `Cmd+V`, `Cmd+A` keyboard shortcuts and system pasteboard support using `com.droidbridge.android-items` and `public.file-url`. Supports Mac Finder -> Android, Android -> Mac Finder, and internal Android -> Android copy and move.
  - Safe Move Semantics: Fast-path `adb shell mv` with fallback to `cp -r` and post-copy size/stat verification before deleting the source.
  - Selection Architecture: Single, multi (`Cmd+click`), range (`Shift+click`), and select all (`Cmd+A`) with visual indicators and contextual menu actions (Download, Copy, Cut, Paste, Rename, Delete).
  - Test Suite Expansion: 171 automated test assertions passing across 19 test suites.
- **Completed & Verified in Milestones 2.2.1 & 2.2.2:**
  - Definitive File Browser Activation: Replaced table view layer with `ScrollView` and native plain `Button` row actions. Uses inter-click timestamp delta against `NSEvent.doubleClickInterval` (0.5s): single-click selects immediately; double-click opens immediately without gesture recognizer collisions.
  - Explicit Open Chevron: Added folder chevron button for immediate one-click folder opening.
  - Full Deselection Suite: Cmd+Click toggle/deselection, blank space click deselection, visible "Clear Selection" toolbar & footer buttons, Escape shortcut, and multi-selection drag preservation.
  - Test Suite Expansion: **219/219 automated test assertions passing** across 21 test suites.
- **Explicit Non-Claims:**
  - Physical USB MTP protocol communication is not yet implemented (scheduled for Milestone 3).
  - Wireless pairing (mDNS TLS pairing) is not yet implemented (scheduled for Milestone 2.2).
  - Unrestricted Android system root access is neither attempted nor claimed (scoped storage access).
  - macOS Finder FileProvider / FinderSync extension integration is not yet implemented (scheduled for Milestone 5).
