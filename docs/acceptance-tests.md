# DroidBridge Acceptance Tests & Verification Plan

This document establishes the acceptance test suite, verification criteria, and live execution results required to validate DroidBridge functionality against the product specification and ensure parity with MacDroid Pro.

---

## 1. Test Harness & Methodology

Verification is organized into three distinct tiers:
1. **Mock Unit & Harness Tests (`tests/DroidBridgeTestRunner`):** Reproducible, hermetic async tests using simulated device transports (`MockDeviceTransport`) verifying protocol abstractions, queue state machines, security path traversal rules, and fault recovery.
2. **Integration Tests (`tests/IntegrationTests/`):** Automated harness testing actual ADB / MTP protocol packet framing over loopback sockets or virtual device emulators.
3. **End-to-End Acceptance Tests (Hardware Lab):** Manual and scripted testing against physical Android test devices across multiple Android versions (Android 10, 12, 14, 15) and OEM vendors (Google Pixel, Samsung Galaxy, Xiaomi).

---

## 2. Milestone 1 Verification Results (Executed 2026-10-30)

The Milestone 1 core harness was compiled and executed via `swift run DroidBridgeTestRunner`. All 9 test suites and 50 assertions passed with zero errors:

| Test Suite | Assertions | Passed | Failed | Status |
| :--- | :---: | :---: | :---: | :---: |
| **1. Device Connection & Disconnection** | 5 | 5 | 0 | ✅ PASSED |
| **2. Directory Listing & Filesystem Mutation** | 8 | 8 | 0 | ✅ PASSED |
| **3. Bidirectional File Transfers (Push/Pull)** | 7 | 7 | 0 | ✅ PASSED |
| **4. Transfer Queue & State Transitions** | 5 | 5 | 0 | ✅ PASSED |
| **5. Transfer Cancellation & Task Abort** | 3 | 3 | 0 | ✅ PASSED |
| **6. Path Traversal & Security Validation** | 6 | 6 | 0 | ✅ PASSED |
| **7. Duplicate Filename & Conflict Handling** | 5 | 5 | 0 | ✅ PASSED |
| **8. Provider Errors & Fault Recovery** | 6 | 6 | 0 | ✅ PASSED |
| **9. Device Isolation (Multi-Device Independence)**| 5 | 5 | 0 | ✅ PASSED |
| **Total Test Assertions** | **50** | **50** | **0** | **100% PASS** |

---

## 3. Comprehensive Acceptance Test Suites

### Suite 1: Device Discovery & Hotplug Lifecycle

| Test ID | Scenario | Procedure | Expected Result | Milestone 1 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-DISC-01** | Mock Device Connection | Connect to simulated device via `MockDeviceTransport`. | Transitions to `connected`; exposes seeded filesystem. | ✅ Verified (Mock) |
| **TC-DISC-02** | Device Disconnection | Disconnect simulated device. | Transitions to `disconnected`; operations fail cleanly. | ✅ Verified (Mock) |
| **TC-DISC-03** | Multi-Device Isolation | Connect two distinct mock devices concurrently. | Filesystem changes on Device A do not leak to Device B. | ✅ Verified (Mock) |
| **TC-DISC-04** | USB MTP Plug & Play | Connect physical Android device via USB (MTP). | Detects device within 2s; displays volumes. | ⏳ Planned (M3) |
| **TC-DISC-05** | USB ADB Plug & Play | Connect physical device with USB Debugging enabled. | Authorizes host RSA key; transitions to Ready. | ⏳ Planned (M2) |
| **TC-DISC-06** | Wi-Fi mDNS Discovery | Discover Android 11+ pairing service via mDNS. | Discovers service; initiates TLS pairing handshake. | ⏳ Planned (M2) |

---

### Suite 2: Directory Browsing & Filesystem Operations

| Test ID | Scenario | Procedure | Expected Result | Milestone 1 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-DIR-01** | Root & Storage Enumeration | List `/` and `/sdcard` directories. | Lists standard folders (`DCIM`, `Download`, `Music`). | ✅ Verified (Mock) |
| **TC-DIR-02** | Subfolder Listing & Metadata | Enumerate `/sdcard/DCIM/sample_photo.jpg`. | Accurate filename, size, and modified date reported. | ✅ Verified (Mock) |
| **TC-DIR-03** | Create Directory | Create `/sdcard/CustomFolder`. | Folder created and verified in subsequent listing. | ✅ Verified (Mock) |
| **TC-DIR-04** | Delete Item | Delete file or directory. | Item deleted and removed from directory listing. | ✅ Verified (Mock) |
| **TC-DIR-05** | Path Traversal Security | Attempt `../`, `/../../etc/passwd`, `/sdcard/..`. | Throws `.pathTraversalForbidden`; escapes blocked. | ✅ Verified (Mock) |
| **TC-DIR-06** | Empty Path Validation | Attempt listing empty string path `""`. | Throws `.invalidPath`. | ✅ Verified (Mock) |

---

### Suite 3: Bidirectional File Transfers & Queue Scheduling

| Test ID | Scenario | Procedure | Expected Result | Milestone 1 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-XFER-01** | Host to Android (Push) | Upload local macOS file to `/sdcard/Download`. | Byte parity verified; progress updates emitted. | ✅ Verified (Mock) |
| **TC-XFER-02** | Android to Host (Pull) | Download `/sdcard/Download/welcome.txt` to Mac. | File written to destination with identical contents. | ✅ Verified (Mock) |
| **TC-XFER-03** | Zero-Byte File Transfer | Upload and download 0-byte file (`zero.bin`). | Handled cleanly without truncation or hanging. | ✅ Verified (Mock) |
| **TC-XFER-04** | Queue Enqueue & States | Enqueue job; transition pending -> inProgress. | State machine updates with fraction and speed. | ✅ Verified (Mock) |
| **TC-XFER-05** | Queue Pause & Resume | Pause in-progress job; resume after delay. | Job state preserves progress fraction upon resume. | ✅ Verified (Mock) |
| **TC-XFER-06** | Transfer Cancellation | Cancel active `Task` and queued job. | Stream aborts cleanly; throws `.transferCancelled`. | ✅ Verified (Mock) |
| **TC-XFER-07** | Conflict Handling (Fail) | Upload existing filename with policy `.fail`. | Throws `.itemAlreadyExists`. | ✅ Verified (Mock) |
| **TC-XFER-08** | Conflict Handling (Overwrite)| Upload existing filename with policy `.overwrite`.| Target file overwritten with new payload. | ✅ Verified (Mock) |
| **TC-XFER-09** | Conflict Handling (Rename) | Upload existing filename with `.renameWithTimestamp`.| New file created with timestamped suffix. | ✅ Verified (Mock) |
| **TC-XFER-10** | Large File (> 4 GB) | Transfer 12 GB file in both directions. | 64-bit offsets handled correctly. | ⏳ Planned (M2/M3) |

---

### Suite 4: Fault Tolerance & Error Recovery

| Test ID | Scenario | Procedure | Expected Result | Milestone 1 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-ERR-01** | Simulated Disconnection | Trigger `simulateDisconnection()` mid-session. | Subsequent operations throw `.deviceDisconnected`. | ✅ Verified (Mock) |
| **TC-ERR-02** | Recovery on Reconnect | Call `connect()` after simulated disconnect. | Device re-establishes connection and resumes I/O. | ✅ Verified (Mock) |
| **TC-ERR-03** | Transient I/O Failure | Trigger `simulateFailureOnNextOperation()`. | Throws `.ioError`; next call succeeds cleanly. | ✅ Verified (Mock) |
| **TC-ERR-04** | macOS Sleep / Wake | Put Mac to sleep during active USB transfer. | Graceful socket abort; cleanly handles wake. | ⏳ Planned (M2/M3) |

---

### Suite 5: macOS Finder & System Integration

| Test ID | Scenario | Procedure | Expected Result | Milestone 1 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-FND-01** | Native Finder Drive Mount | Expose Android storage via FileProvider extension. | Mounts under Locations in Finder sidebar. | ⏳ Planned (M5) |
| **TC-FND-02** | Finder Drag-and-Drop | Drag file from macOS desktop to mounted folder. | Triggers FileProvider write to device. | ⏳ Planned (M5) |
| **TC-FND-03** | FinderSync Context Menus | Right click file in Finder on Mac. | "Send to Android with DroidBridge" available. | ⏳ Planned (M5) |

---

## 4. Performance Benchmarks & SLAs

| Metric | Target (Minimum SLA) | Milestone 1 (Mock In-Memory) | Target Hardware SLA |
| :--- | :--- | :--- | :--- |
| **USB 3.0 ADB Throughput** | ≥ 40 MB/s sustained | N/A (Simulated) | Milestone 2 |
| **USB 2.0 MTP Throughput** | ≥ 25 MB/s sustained | N/A (Simulated) | Milestone 3 |
| **Wi-Fi 5 GHz ADB Throughput** | ≥ 15 MB/s sustained | N/A (Simulated) | Milestone 2 |
| **Application Idle Memory** | ≤ 40 MB RAM | ~ 18 MB RAM | Milestone 5 |
| **Active Transfer Memory** | ≤ 80 MB RAM | ~ 24 MB RAM | Milestone 5 |
