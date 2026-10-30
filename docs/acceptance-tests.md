# DroidBridge Acceptance Tests & Verification Plan

This document establishes the acceptance test suite, verification criteria, and live execution results required to validate DroidBridge functionality against the product specification and ensure parity with MacDroid Pro.

---

## 1. Test Harness & Methodology

Verification is organized into three distinct tiers:
1. **Mock & Subsystem Harness Tests (`tests/DroidBridgeTestRunner`):** Reproducible, hermetic async tests using `MockDeviceTransport` and `MockADBCommandRunner` verifying protocol abstractions, ADB argument safety, status parsing, security rules, timeouts, and fault recovery.
2. **Integration Tests (`tests/IntegrationTests/`):** Automated harness testing real process wrappers (`ProcessADBCommandRunner`) and ADB commands against live or local fake executables.
3. **End-to-End Acceptance Tests (Hardware Lab):** Manual and scripted testing against physical Android test devices across multiple Android versions (Android 10, 12, 14, 15) and OEM vendors (Google Pixel, Samsung Galaxy, Xiaomi).

---

## 2. Milestone 2 & 2.1 Verification Results (Executed 2026-10-31)

The verification suite was compiled and executed via `swift run DroidBridgeTestRunner`. All 17 test suites and 138 assertions passed with zero errors:

| Test Suite | Assertions | Passed | Failed | Status |
| :--- | :---: | :---: | :---: | :---: |
| **1. M1 Regression: Device Connection & Disconnection** | 5 | 5 | 0 | ✅ PASSED |
| **2. M1 Regression: Directory Listing & Mutation** | 8 | 8 | 0 | ✅ PASSED |
| **3. M1 Regression: Bidirectional Transfers** | 7 | 7 | 0 | ✅ PASSED |
| **4. M1 Regression: Transfer Queue & States** | 5 | 5 | 0 | ✅ PASSED |
| **5. M1 Regression: Transfer Cancellation** | 3 | 3 | 0 | ✅ PASSED |
| **6. M1 Regression: Path Traversal Security** | 6 | 6 | 0 | ✅ PASSED |
| **7. M1 Regression: Conflict Resolution** | 5 | 5 | 0 | ✅ PASSED |
| **8. M1 Regression: Provider Error Recovery** | 6 | 6 | 0 | ✅ PASSED |
| **9. M1 Regression: Device Isolation** | 5 | 5 | 0 | ✅ PASSED |
| **10. M2: ADB Configuration & Availability** | 8 | 8 | 0 | ✅ PASSED |
| **11. M2: ADB Device Discovery & Status Parsing** | 16 | 16 | 0 | ✅ PASSED |
| **12. M2: Command Safety & Multi-Device Targeting** | 7 | 7 | 0 | ✅ PASSED |
| **13. M2: ADB Filesystem & Unicode/Spaces** | 9 | 9 | 0 | ✅ PASSED |
| **14. M2: Real ADB Transfers & Verification** | 11 | 11 | 0 | ✅ PASSED |
| **15. M2: Command Timeouts & Cancellation** | 2 | 2 | 0 | ✅ PASSED |
| **16. M2.1: Symlink Resolution & Navigation** | 14 | 14 | 0 | ✅ PASSED |
| **17. M2.1: Transfer UI Integration & Serial Targeting** | 21 | 21 | 0 | ✅ PASSED |
| **Total Test Assertions** | **138** | **138** | **0** | **100% PASS** |

---

## 3. Physical Hardware Testing Status (Realme RMX3092)

- **Connected Device:** Realme RMX3092 (Serial: `AE9PH68T4DV86L9P`).
- **ADB Connection State:** `device` (Authorized, USB Debugging active).
- **Terminal Benchmarks:**
  - `adb -s AE9PH68T4DV86L9P shell ls -la -L -p /sdcard`: Verified directory listing with 23 folders (including `/sdcard/Download`, `DCIM`, `Documents`).
  - Terminal `adb push` and `adb pull` roundtrip verified with matching sha256 checksums.
- **Milestone 2.1 Code Status:**
  - Symlink dereferencing (`-L`) and Upload/Download UI implemented and automated tests verified (138/138).
- **Physical In-App Verification Requirement:**
  - Per clean-room and verification protocol, physical in-app transfers are **not claimed as verified** until manually run through the GUI application on the connected device using the verification checklist below.

### Manual Physical-Device In-App Verification Checklist

1. [ ] Launch `DroidBridgeApp` via `swift run DroidBridgeApp`.
2. [ ] In the Devices sidebar, select **RMX3092 (AE9PH68T4DV86L9P)**. Verify that the device connects without error and status bar displays `"Connected (RMX3092 (AE9PH68T4DV86L9P))"`.
3. [ ] Confirm that `/sdcard` displays the directory contents (`Download`, `DCIM`, `Documents`, etc.) rather than a raw symlink item `lrw-r--r-- ... /sdcard -> /storage/self/primary`.
4. [ ] Double-click / tap **Download** folder. Confirm that `/sdcard/Download` opens and displays files.
5. [ ] Click **Upload File...** in the toolbar. Select a test image/text file using `NSOpenPanel`. Confirm that:
   - Progress bar appears.
   - Status bar reports `"Uploaded <filename> successfully"`.
   - The uploaded file appears in the directory listing.
6. [ ] Locate the file in the list. Click the **Download** icon button (or right-click -> **Download to Mac...**).
7. [ ] Select destination via `NSSavePanel` (e.g. `~/Downloads/test_download.txt`). Confirm that:
   - File downloads.
   - Status reports `"Downloaded <filename> successfully"`.
   - Content and hash match the original file on macOS (`shasum -a 256`).

---

## 4. Comprehensive Acceptance Test Suites

### Suite 1: Device Discovery & Hotplug Lifecycle

| Test ID | Scenario | Procedure | Expected Result | Milestone 2 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-DISC-01** | Mock Device Connection | Connect to simulated device via `MockDeviceTransport`. | Transitions to `connected`; exposes seeded filesystem. | ✅ Verified (Mock) |
| **TC-DISC-02** | Device Disconnection | Disconnect simulated device. | Transitions to `disconnected`; operations fail cleanly. | ✅ Verified (Mock) |
| **TC-DISC-03** | Multi-Device Isolation | Connect two distinct mock devices concurrently. | Filesystem changes on Device A do not leak to Device B. | ✅ Verified (Mock) |
| **TC-DISC-04** | ADB Device Discovery Parsing | Parse `adb devices -l` with multiple devices. | Extracts serials, models, and states accurately. | ✅ Verified (Runner) |
| **TC-DISC-05** | Unauthorized Device Handling | Connect device in `unauthorized` ADB state. | Throws `.permissionDenied` prompting user. | ✅ Verified (Runner) |
| **TC-DISC-06** | Offline Device Handling | Connect device in `offline` ADB state. | Mapped cleanly to `.error("Device is offline")`. | ✅ Verified (Runner) |
| **TC-DISC-07** | USB MTP Plug & Play | Connect physical Android device via USB (MTP). | Detects device within 2s; displays volumes. | ⏳ Planned (M3) |
| **TC-DISC-08** | Wi-Fi mDNS Discovery | Discover Android 11+ pairing service via mDNS. | Discovers service; initiates TLS pairing handshake. | ⏳ Planned (M2.1) |

---

### Suite 2: Directory Browsing & Filesystem Operations

| Test ID | Scenario | Procedure | Expected Result | Milestone 2 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-DIR-01** | Root & Storage Enumeration | List `/` and `/sdcard` directories via ADB shell. | Lists standard folders (`DCIM`, `Download`, `Music`). | ✅ Verified (Runner) |
| **TC-DIR-02** | Unicode & Space Filenames | Enumerate files with spaces and CJK/emoji characters. | Correctly parses `Unicode 测试 🚀.pdf`. | ✅ Verified (Runner) |
| **TC-DIR-03** | Create Directory via ADB | Create `/sdcard/Folder With Spaces` via `mkdir`. | Folder created and verified in subsequent listing. | ✅ Verified (Runner) |
| **TC-DIR-04** | Delete Item via ADB | Delete file or directory via `rm`. | Item deleted and removed from directory listing. | ✅ Verified (Runner) |
| **TC-DIR-05** | Rename Item via ADB | Move/rename file via `mv`. | Target renamed and accessible under new name. | ✅ Verified (Runner) |
| **TC-DIR-06** | Path Traversal Security | Attempt `../`, `/../../etc/passwd`, `/sdcard/..`. | Throws `.pathTraversalForbidden`; escapes blocked. | ✅ Verified (Runner) |

---

### Suite 3: Bidirectional File Transfers & Queue Scheduling

| Test ID | Scenario | Procedure | Expected Result | Milestone 2 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-XFER-01** | Host to Android (Push) | Upload local macOS file to `/sdcard/Download` via ADB. | Verified by post-upload remote stat check. | ✅ Verified (Runner) |
| **TC-XFER-02** | Android to Host (Pull) | Download `/sdcard/Download/welcome.txt` to Mac. | File written to destination with verified contents. | ✅ Verified (Runner) |
| **TC-XFER-03** | Zero-Byte File Transfer | Upload and download 0-byte file (`zero.bin`). | Handled cleanly without truncation or hanging. | ✅ Verified (Mock) |
| **TC-XFER-04** | Queue Enqueue & States | Enqueue job; transition pending -> inProgress. | State machine updates with fraction and speed. | ✅ Verified (Mock) |
| **TC-XFER-05** | Queue Pause & Resume | Pause in-progress job; resume after delay. | Job state preserves progress fraction upon resume. | ✅ Verified (Mock) |
| **TC-XFER-06** | Transfer Cancellation | Cancel active `Task` during ADB streaming. | Process terminated; throws `.transferCancelled`. | ✅ Verified (Runner) |
| **TC-XFER-07** | Conflict Handling (Fail) | Upload existing filename with policy `.fail`. | Throws `.itemAlreadyExists`. | ✅ Verified (Runner) |
| **TC-XFER-08** | Conflict Handling (Overwrite)| Upload existing filename with policy `.overwrite`.| Target file overwritten with new payload. | ✅ Verified (Runner) |
| **TC-XFER-09** | Out of Space Error | ADB reports "No space left on device". | Mapped accurately to `.storageFull`. | ✅ Verified (Runner) |
| **TC-XFER-10** | Large File (> 4 GB) | Transfer 12 GB file in both directions. | 64-bit offsets handled correctly. | ⏳ Planned (Physical Lab) |

---

### Suite 4: Fault Tolerance & Error Recovery

| Test ID | Scenario | Procedure | Expected Result | Milestone 2 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-ERR-01** | Command Timeout | ADB command takes longer than timeout limit. | Process killed; throws `.ioError` with timeout message. | ✅ Verified (Runner) |
| **TC-ERR-02** | Cable Pull Mid-Transfer | ADB returns "device 'SERIAL' not found". | Mapped accurately to `.deviceDisconnected`. | ✅ Verified (Runner) |
| **TC-ERR-03** | Recovery on Reconnect | Call `connect()` after simulated disconnect. | Device re-establishes connection and resumes I/O. | ✅ Verified (Runner) |
| **TC-ERR-04** | macOS Sleep / Wake | Put Mac to sleep during active USB transfer. | Graceful socket abort; cleanly handles wake. | ⏳ Planned (M3) |

---

### Suite 5: macOS Finder & System Integration

| Test ID | Scenario | Procedure | Expected Result | Milestone 2 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-FND-01** | Native Finder Drive Mount | Expose Android storage via FileProvider extension. | Mounts under Locations in Finder sidebar. | ⏳ Planned (M5) |
| **TC-FND-02** | Finder Drag-and-Drop | Drag file from macOS desktop to mounted folder. | Triggers FileProvider write to device. | ⏳ Planned (M5) |
| **TC-FND-03** | FinderSync Context Menus | Right click file in Finder on Mac. | "Send to Android with DroidBridge" available. | ⏳ Planned (M5) |
