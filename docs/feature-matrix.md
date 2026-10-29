# DroidBridge Feature Comparison Matrix

This document benchmarks **DroidBridge**'s target functional specifications against existing macOS Android file transfer solutions: **MacDroid Pro**, **MacDroid Free**, **Google Android File Transfer (Legacy AFT)**, and **OpenMTP**.

---

## 1. Comprehensive Feature Matrix

| Feature / Capability | DroidBridge (Current / Milestone 1) | DroidBridge (Target) | MacDroid Pro | MacDroid Free | Google AFT (Legacy) | OpenMTP |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Licensing / Pricing** | Open / Free | Open / Free | Proprietary ($19.99/yr) | Free (Restricted) | Free (Discontinued) | Open Source (Free) |
| **Technology Stack** | Swift 6 / SwiftUI / SPM | Swift 6 / SwiftUI / AppKit | Native Swift / Obj-C | Native Swift / Obj-C | Legacy Java/C++ | Electron / JS |
| **Connection Modes** | | | | | | |
| • Simulated Mock Device | ✅ Verified (Milestone 1) | ✅ Dev/Test Harness | ❌ Not Supported | ❌ Not Supported | ❌ Not Supported | ❌ Not Supported |
| • USB MTP Mode | ⏳ Planned (Milestone 3) | ✅ Full Two-Way | ✅ Full Two-Way | ⚠️ Mac -> Android Disabled | ⚠️ Two-Way (Unstable) | ✅ Full Two-Way |
| • USB ADB Mode | ⏳ Planned (Milestone 2) | ✅ Full Two-Way | ✅ Full Two-Way | ⚠️ Mac -> Android Disabled | ❌ Not Supported | ❌ Not Supported |
| • Wireless ADB (Wi-Fi) | ⏳ Planned (Milestone 2) | ✅ Full Two-Way | ✅ Full Two-Way | ❌ Not Supported | ❌ Not Supported | ❌ Not Supported |
| • Android 11+ Pairing (mDNS) | ⏳ Planned (Milestone 2) | ✅ Native Pairing | ✅ Supported | ❌ Not Supported | ❌ Not Supported | ❌ Not Supported |
| **macOS System Integration** | | | | | | |
| • Native Finder Drive Mount | ⏳ Planned (Milestone 5) | ✅ FileProvider | ✅ FileProvider | ❌ No Mount | ❌ No Mount | ❌ No Mount |
| • FinderSync Sidebar & Badges | ⏳ Planned (Milestone 5) | ✅ Included | ✅ Included | ❌ No FinderSync | ❌ No FinderSync | ❌ No FinderSync |
| • Menu Bar Status Item | ⏳ Planned (Milestone 5) | ✅ Included | ✅ Included | ✅ Included | ❌ Not Supported | ❌ Not Supported |
| • Drag-and-Drop to/from Finder | ⏳ Planned (Milestone 5) | ✅ Native | ✅ Native | ⚠️ Read-only to Finder | ⚠️ Flaky | ⚠️ Internal UI only |
| • Quick Look File Previews | ⏳ Planned (Milestone 5) | ✅ Supported | ✅ Supported | ⚠️ Limited | ❌ Not Supported | ❌ Not Supported |
| **File Transfer Engine** | | | | | | |
| • Two-Way Bidirectional | ✅ Verified (Mock) | ✅ Full Read/Write | ✅ Full Read/Write | ❌ Read-Only (Mac <- Android) | ✅ Read/Write | ✅ Read/Write |
| • Files > 4 GB Support | ⏳ Planned (Milestone 2/3) | ✅ 64-bit offsets | ✅ Supported | ⚠️ Read only | ❌ Fails on >4GB | ✅ Supported |
| • Multi-file & Folder Queuing | ✅ Verified (Actor Queue) | ✅ Async Queue | ✅ Async Queue | ⚠️ Single thread | ❌ Basic copy | ✅ Queue supported |
| • Transfer Pause / Resume | ✅ Verified (State Machine) | ✅ Supported | ✅ Supported | ❌ Not Supported | ❌ Not Supported | ❌ Not Supported |
| • Speed & ETA Calculation | ✅ Verified (TransferProgress) | ✅ Real-time | ✅ Real-time | ⚠️ Basic | ❌ Not Supported | ✅ Basic |
| • File Conflict Handling | ✅ Verified (Fail/Overwrite/Rename)| ✅ Prompt/Skip/Overwrite | ✅ Prompt/Overwrite | ❌ Read-only | ❌ Fails on collision | ✅ Overwrite prompt |
| • Post-Transfer MediaScan | ⏳ Planned (Milestone 2/3) | ✅ Auto broadcast | ✅ Auto broadcast | ❌ Not Applicable | ⚠️ Hit-or-miss | ⚠️ Manual/Plugin |
| **Reliability & Performance** | | | | | | |
| • Reconnection on Cable Pull | ✅ Verified (Fault Simulation)| ✅ Auto Recover/Abort | ✅ Graceful handling | ⚠️ Hangs | ❌ Crashes app | ⚠️ Requires restart |
| • Multi-Device Concurrent | ✅ Verified (Device Isolation) | ✅ Supported | ✅ Supported | ❌ Single device | ❌ Single device | ❌ Single device |
| • Memory Footprint | ⚡ Low (<30 MB) | ⚡ Low (<80 MB) | ⚡ Low (<90 MB) | ⚡ Low (<90 MB) | ⚠️ Moderate | 🔴 High (>400 MB) |

---

## 2. Technical Feasibility & Classification

To ensure rigorous product engineering, features are tagged according to their development classification:

### 2.1 Confirmed Technical Primitives (Verified Feasible)
- **USB Device Enumeration:** IOKit `IOServiceAddMatchingNotification` for USB Vendor ID/Product ID events.
- **ADB Stream Protocol:** Local TCP socket communication with ADB daemon (`SYNC` commands: `STAT`, `LIST`, `SEND`, `DATA`, `DONE`). Proven in Android Open Source Project (AOSP) specification.
- **MTP Communication:** `libmtp` / `libusb` user-space protocol implementation. No kernel drivers needed.
- **FinderSync Integration:** Standard Apple API (`FIFinderSyncController`) for sidebar items and contextual menus.
- **App Sandbox Entitlements:** `com.apple.security.device.usb` and `com.apple.security.network.client` allow sandboxed operation while maintaining USB and local network access.

### 2.2 Architectural Hypotheses (Under Prototyping)
- **`NSFileProviderReplicatedExtension` for MTP:**
  - *Premise:* Exposing Android storage as an Apple FileProvider item gives true Finder mounting without third-party kexts or macFUSE.
  - *Risk:* MTP's half-duplex, single-threaded nature may cause Finder delays during burst file reads (e.g., QuickLook thumbnail generation).
  - *Mitigation:* Implement an in-memory metadata cache and throttled request batching.
- **Daemonless ADB:**
  - *Premise:* Directly speaking ADB over USB endpoints in Swift without spawning a standalone `adb` binary.
  - *Evaluation:* Bundling an isolated `adb` binary or running on a non-standard port (e.g. 5038) is currently far more robust across varying OEM Android fastboot/bootloader states.

### 2.3 Known Unknowns & Platform Limitations
- **Samsung OneUI MTP File Handle Locks:**
  - Certain Samsung devices hold internal lock contention if the Samsung Gallery scanner is active while MTP writes occur.
- **macOS Sleep/Wake Edge Cases:**
  - Putting macOS to sleep during an active 10 GB transfer drops USB power states. The app must detect `NSWorkspace.willSleepNotification` and pause or cleanly abort active queue operations to avoid filesystem corruption on Android storage.

---

## 3. Current Implementation Status (Milestone 1)

- **Completed & Verified:**
  - Abstract protocol definitions: `DeviceTransport`, `DeviceFileSystem`, `TransferService`, `TransferQueue`, `ConnectionManagerProtocol`, `DeviceDiscoveryService`.
  - Core domain models: `ConnectionType`, `DeviceDescriptor`, `StorageItem`, `TransferJob`, `TransferProgress`, `TransferOptions`, `DeviceError`.
  - `MockDeviceTransport`: In-memory and local temporary filesystem provider with seeded Android paths (`/sdcard`, `DCIM`, `Download`, `Music`, `Documents`).
  - Security hardening: Path traversal validation strictly rejects `..` and non-canonical escapements.
  - Conflict resolution: Comprehensive support for `.fail`, `.overwrite`, and `.renameWithTimestamp`.
  - `TransferQueueService`: Actor-isolated job queue with state transitions (`pending`, `inProgress`, `paused`, `completed`, `cancelled`).
  - `MockDeviceDiscoveryService`: Safe discovery implementation keeping mock devices completely hidden from production discovery unless explicitly requested.
  - SwiftUI Application: `DroidBridgeApp` with `AppViewModel` supporting device selection, simulated directory navigation, and mock status toggling.
  - Automated Test Suite: 50 assertions across 9 test suites passing with 100% success rate.
- **Explicit Non-Claims:**
  - Physical USB MTP communication is not yet implemented (scheduled for Milestone 3).
  - Physical USB ADB and Wireless Wi-Fi ADB communication are not yet implemented (scheduled for Milestone 2).
  - macOS Finder FileProvider / FinderSync extension integration is not yet implemented (scheduled for Milestone 5).
