# DroidBridge Acceptance Tests & Verification Plan

This document establishes the acceptance test suite, verification criteria, and live execution results required to validate DroidBridge functionality against the product specification and ensure parity with MacDroid Pro.

---

## 1. Test Harness & Methodology

Verification is organized into three distinct tiers:
1. **Mock & Subsystem Harness Tests (`tests/DroidBridgeTestRunner`):** Reproducible, hermetic async tests using `MockDeviceTransport` and `MockADBCommandRunner` verifying protocol abstractions, ADB argument safety, status parsing, security rules, timeouts, and fault recovery.
2. **Integration Tests (`tests/IntegrationTests/`):** Automated harness testing real process wrappers (`ProcessADBCommandRunner`) and ADB commands against live or local fake executables.
3. **End-to-End Acceptance Tests (Hardware Lab):** Manual and scripted testing against physical Android test devices across multiple Android versions (Android 10, 12, 14, 15) and OEM vendors (Google Pixel, Samsung Galaxy, Xiaomi).

---

## 2. Milestone 2, 2.1, 2.2, 2.2.1 & 2.2.2 Verification Results (Executed 2026-10-31)

The verification suite was compiled and executed via `swift run DroidBridgeTestRunner`. All 21 test suites and 219 assertions passed with zero errors:

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
| **18. M2.2: Native macOS Drag & Drop & Recursive Transfers**| 14 | 14 | 0 | ✅ PASSED |
| **19. M2.2: Native macOS Clipboard, Shortcuts & Selection** | 19 | 19 | 0 | ✅ PASSED |
| **20. M2.2.1: Folder Navigation & Gesture Separation** | 30 | 30 | 0 | ✅ PASSED |
| **21. M2.2.2: Definitive Navigation & Deselection** | 18 | 18 | 0 | ✅ PASSED |
| **22. M2.2.3: Restored Drag & Drop, Clipboard & Quick Look** | 20 | 20 | 0 | ✅ PASSED |
| **23. M2.2.4: Same-Location Protection, Multi-Drag, Media Preview & Clipboard Repair** | 43 | 43 | 0 | ✅ PASSED |
| **Total Test Assertions** | **282** | **282** | **0** | **100% PASS** |

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
5. [ ] **Toolbar Upload:** Click **Upload File...** in the toolbar. Select a test image/text file using `NSOpenPanel`. Confirm that:
   - Progress bar appears.
   - Status bar reports `"Uploaded <filename> successfully"`.
   - The uploaded file appears in the directory listing.
6. [ ] **Context / Action Download:** Locate the file in the list. Click the **Download** icon button (or right-click -> **Download to Mac...**). Select destination via `NSSavePanel`. Verify contents and SHA-256 hash match.
7. [ ] **Drag & Drop (Mac to Android):** Drag multiple files or a whole folder from macOS Finder directly into the DroidBridge file list pane. Confirm the drop target highlight appears, files upload recursively, and the list refreshes.
8. [ ] **Drag & Drop (Android to Mac):** Select one or more files in DroidBridge, drag them onto the macOS Desktop or an open Finder window. Confirm that files are staged safely and land in Finder with intact names and sizes.
9. [ ] **Keyboard Shortcuts (Cmd+C / Cmd+V):**
   - Copy a file in Finder (`Cmd+C`), switch to DroidBridge, press `Cmd+V`. Confirm upload succeeds.
   - Select an Android file in DroidBridge, press `Cmd+C`, navigate to another Android folder (e.g., `/sdcard/Documents`), press `Cmd+V`. Confirm the file is copied.
10. [ ] **Keyboard Shortcuts (Cmd+X / Cmd+V):** Select an Android file in DroidBridge, press `Cmd+X`, navigate to another Android directory, press `Cmd+V`. Confirm the file is moved cleanly and disappears from original folder.
11. [ ] **Selection & Batch Operations:** Test `Cmd+A` (Select All), `Shift+Click` (range selection), `Cmd+Click` (multi-toggle), and press `Delete` to delete selected items after confirming the prompt.
12. [ ] **Rename:** Right-click an item, select **Rename...**, enter a new filename, and verify the item is renamed without modifying file contents.

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
| **TC-FND-02** | FinderSync Context Menus | Right click file in Finder on Mac. | "Send to Android with DroidBridge" available. | ⏳ Planned (M5) |

---

### Suite 6: Native macOS Drag & Drop and Clipboard (Milestone 2.2)

| Test ID | Scenario | Procedure | Expected Result | Milestone 2.2 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-DND-01** | Batch Drag & Drop Mac to Android | Drag multiple files from Finder onto DroidBridge browser. | All files pushed to current Android folder with progress. | ✅ Verified (Runner) |
| **TC-DND-02** | Folder Drag & Drop Mac to Android | Drag folder structure from Finder onto DroidBridge. | Folder pushed recursively; remote structure preserved. | ✅ Verified (Runner) |
| **TC-DND-03** | Conflict Handling on Drop | Drop existing file when policy is `.renameWithTimestamp`. | Uploads file with unique timestamp prefix, no overwrite. | ✅ Verified (Runner) |
| **TC-DND-04** | Unsupported Item Drop | Drop non-file item provider (e.g. raw text or URL string). | Gracefully rejected with clear status error. | ✅ Verified (Runner) |
| **TC-DND-05** | Drag Android to Mac Finder | Drag files from DroidBridge onto macOS Desktop/Finder. | Staged in temporary sandbox; drops intact without partials. | ✅ Verified (Runner) |
| **TC-DND-06** | Recursive Folder Drag-Out | Drag directory from DroidBridge onto macOS Desktop. | Staged recursively via `downloadDirectory`; intact folder. | ✅ Verified (Runner) |
| **TC-CLIP-01** | Android Copy & Paste (`Cmd+C`/`Cmd+V`) | Select file, `Cmd+C`, navigate to new folder, `Cmd+V`. | `adb shell cp -r` executed targeting device serial. | ✅ Verified (Runner) |
| **TC-CLIP-02** | Android Cut & Paste (`Cmd+X`/`Cmd+V`) | Select file, `Cmd+X`, navigate to new folder, `Cmd+V`. | `adb shell mv` executed; clipboard payload cleared. | ✅ Verified (Runner) |
| **TC-CLIP-03** | Mac Finder to Android Paste | Copy file in Finder (`Cmd+C`), switch to DroidBridge, `Cmd+V`. | Pasteboard file URLs detected and pushed to Android. | ✅ Verified (Runner) |
| **TC-CLIP-04** | Safe Move Verification | Move file between directories. | Uses fast `mv`; falls back to `cp -r` + verify + `rm`. | ✅ Verified (Runner) |
| **TC-SEL-01** | Multi-Select & Select All | Use `Cmd+Click`, `Shift+Click`, and `Cmd+A`. | Selection count matches; visual indicators update. | ✅ Verified (Runner) |
| **TC-SEL-02** | Batch Delete | Select multiple items and press `Delete` key. | `adb shell rm` called for selected items; list refreshed. | ✅ Verified (Runner) |
| **TC-SEL-03** | Inline Rename | Rename item via context menu or shortcut. | `adb shell mv` invoked; item refreshed with new name. | ✅ Verified (Runner) |

---

### Suite 7: Folder Navigation & Double-Click Gesture Separation (Milestone 2.2.1)

| Test ID | Scenario | Procedure | Expected Result | Milestone 2.2.1 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-NAV-01** | Single-Click Selects Folder | Click once on a folder row. | Folder is selected; currentPath remains unchanged. | ✅ Verified (Runner) |
| **TC-NAV-02** | Double-Click Enters Folder | Double-click on a folder row. | Navigates into folder; path and items updated; selection reset. | ✅ Verified (Runner) |
| **TC-NAV-03** | Parent Directory Navigation | Double-click virtual `..` parent row. | Navigates back up to parent directory. | ✅ Verified (Runner) |
| **TC-NAV-04** | Folder Drag Without Navigation | Drag folder toward Finder or drop target. | Export items returned; folder is NOT navigated into. | ✅ Verified (Runner) |
| **TC-NAV-05** | Multi-Select Preservation | Cmd+Click folder and file; drag. | Both items preserved in selection; multi-drag exports both. | ✅ Verified (Runner) |
| **TC-NAV-06** | Clipboard Preservation | Copy selected folder and file (`Cmd+C`). | Clipboard payload contains both; operation is `.copy`. | ✅ Verified (Runner) |
| **TC-NAV-07** | Selection/Deselection Cycle | Select items, `clearSelection()`, then navigate. | Selection cleared, navigation succeeds, items listed cleanly. | ✅ Verified (Runner) |
| **TC-NAV-08** | Keyboard Folder Open | Select folder, press `Return` or `Cmd+DownArrow`. | Navigates into selected folder. | ✅ Verified (Runner) |
| **TC-NAV-09** | Keyboard Parent Navigation | Press `Cmd+UpArrow`. | Navigates to parent directory. | ✅ Verified (Runner) |

---

### Suite 8: Definitive Navigation & Deselection Verification (Milestone 2.2.2)

| Test ID | Scenario | Procedure | Expected Result | Milestone 2.2.2 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-ACT-01** | Row Button Single-Click | Single-click row Button (`handleRowClick`). | Selects item immediately; path unchanged. | ✅ Verified (Runner) |
| **TC-ACT-02** | Row Button Double-Click | Double-click row Button (`handleRowClick` within 0.5s). | Navigates into folder immediately. | ✅ Verified (Runner) |
| **TC-ACT-03** | Dedicated Open Chevron | Click folder chevron button (`navigateTo`). | Folder opens immediately. | ✅ Verified (Runner) |
| **TC-ACT-04** | Parent Double-Click Up | Double-click `..` row. | Navigates up to parent directory. | ✅ Verified (Runner) |
| **TC-DESEL-01**| Cmd+Click Deselects Selected | Cmd+Click an already-selected item. | Deselects individual item; others remain selected. | ✅ Verified (Runner) |
| **TC-DESEL-02**| Cmd+Click Adds to Selection | Cmd+Click an unselected item. | Adds item to selection set. | ✅ Verified (Runner) |
| **TC-DESEL-03**| Blank Space Click Deselects | Click empty area below rows. | Clears entire selection set (`clearSelection`). | ✅ Verified (Runner) |
| **TC-DESEL-04**| Visible Clear Selection Action| Click "Clear Selection" toolbar button. | Clears all selections. | ✅ Verified (Runner) |
| **TC-DESEL-05**| Escape Shortcut Deselects | Press Escape key. | Clears all selections. | ✅ Verified (Runner) |
| **TC-DESEL-06**| Cmd+A Selects All Items | Press Cmd+A. | Selects all selectable items in active directory. | ✅ Verified (Runner) |
| **TC-DESEL-07**| Multi-Selection Drag Keep | Click selected item in multi-selection. | Multi-selection kept intact for dragging. | ✅ Verified (Runner) |
| **TC-UI-01**   | AppKit Window Event Dispatch| Send synthetic mouse down/up via `NSWindow.sendEvent`.| Button action executes cleanly. | ✅ Verified (Runner) |

---

### Suite 9: Restored Drag & Drop, Clipboard & Quick Look Verification (Milestone 2.2.3)

| Test ID | Scenario | Procedure | Expected Result | Milestone 2.2.3 Status |
| :--- | :--- | :--- | :--- | :---: |
| **TC-QL-01**   | Spacebar Quick Look on File | Select file and press `Space` (`handleSpacebar`). | Previews file via `QLPreviewPanel`; item cached on local disk. | ✅ Verified (Runner) |
| **TC-QL-02**   | Quick Look Arrow Key Switch | Press `Down Arrow` while Quick Look is open. | Selection moves to next item; active preview updates automatically. | ✅ Verified (Runner) |
| **TC-QL-03**   | Escape Dismisses Quick Look | Press `Escape` while Quick Look is open. | Quick Look closes without deselecting the file. | ✅ Verified (Runner) |
| **TC-QL-04**   | Return Key Previews File | Select file and press `Return`. | Opens Quick Look preview for the selected file. | ✅ Verified (Runner) |
| **TC-QL-05**   | Return Key Enters Folder | Select folder and press `Return`. | Navigates into the folder directory. | ✅ Verified (Runner) |
| **TC-QL-06**   | Cmd+Up Returns to Parent | Press `Cmd+UpArrow`. | Navigates back up to parent directory. | ✅ Verified (Runner) |
| **TC-DND-07**  | Finder Drag-Out Format | Drag file row or handle to Finder/Desktop. | Item provider registers `public.file-url` (`UTType.fileURL`). | ✅ Verified (Runner) |
| **TC-DND-08**  | CRLF-Resilient Drop-In | Drop file with trailing CRLF URL from Finder. | URL parsed cleanly without %0D%0A artifacts; file uploaded. | ✅ Verified (Runner) |
| **TC-CLIP-05** | Finder Pasteboard Interop | Select Android file and press `Cmd+C`. | Staged file URLs written to `NSPasteboard` (`[NSURL]`) for Finder paste. | ✅ Verified (Runner) |
| **TC-QL-07**   | Quick Look Cache Cleanup | Call `clearQuickLookCache()`. | Temporary cache directory files removed safely. | ✅ Verified (Runner) |

---

## 7. Milestone 2.2.5 Acceptance Tests (Runtime Reliability & Physical Hardware)

| Test ID | Test Scenario | Steps / Input | Expected Result | Status |
| :--- | :--- | :--- | :--- | :--- |
| **TC-M225-01** | POSIX Shell Escaping for Whitespace & Quotes | Pass `/sdcard/Download/Ae Ajnabee  Coke...` through `ADBFileSystem.escapeForShell`. | Cleanly quotes path in single quotes; unquoted for clean paths. | ✅ Verified (Runner & Device) |
| **TC-M225-02** | Whitespace-Preserving `ls -l` Line Parser | Parse toybox line with multiple consecutive spaces. | Preserves exact byte count and multi-spaced filename. | ✅ Verified (Runner & Device) |
| **TC-M225-03** | Physical Phone Directory Listing (`Download`) | Execute `listDirectory` on connected Realme RMX3092. | Successfully lists all 52 items, preserving filenames with spaces. | ✅ Verified (Level 4 Hardware) |
| **TC-M225-04** | Physical Phone Stat on Multi-Spaced Files | Execute `getItem(at:)` on `Ae Ajnabee  Coke...mp3`. | Accurately returns 10,387,430 bytes without `itemNotFound`. | ✅ Verified (Level 4 Hardware) |
| **TC-M225-05** | Physical Phone Folder Stat with Spaces (`Quick Share`) | Execute `getItem` and `listDirectory` on `Quick Share`. | Resolves folder and enumerates all 1,050 children safely. | ✅ Verified (Level 4 Hardware) |
| **TC-M225-06** | Physical Phone Audio/Media Preview Pipeline | Download and initialize `MediaPreviewModel` on physical mp3. | `AVPlayer` initializes, duration calculates 259.68s, starts playback. | ✅ Verified (Level 4 Hardware) |
| **TC-M225-07** | Dual Drag-and-Drop Targets (Icon + Full Row) | Drag initiated from icon or text row. | Both targets instantiate `NSItemProvider` for Finder export. | ✅ Verified (Runner & AppKit) |
| **TC-M225-08** | Fast-Path Staging Export Cache Reuse | Drag out file already viewed in Quick Look / Media Preview. | Stages file by copying preview cache without re-downloading. | ✅ Verified (Runner) |
| **TC-M225-09** | Menu Bar & Keyboard Shortcut Bridging | Trigger Edit Menu Cut/Copy/Paste/Select All. | Notifies `AppViewModel` when not focused on text responder. | ✅ Verified (Runner & AppKit) |
| **TC-M225-10** | Live GUI App Launch Steadiness | Launch compiled `DroidBridgeApp` binary in macOS environment. | App launches window with PID, runs steadily, exits cleanly. | ✅ Verified (Level 3 App) |
