# DroidBridge Product Specification

## 1. Executive Summary

**DroidBridge** is a modern, high-performance macOS native application engineered to deliver seamless two-way file transfer, storage browsing, and filesystem integration between macOS workstations and Android devices. 

DroidBridge provides functionality comparable to commercial solutions such as **MacDroid Pro**, offering full support for USB MTP, USB ADB, and Authorized Wireless ADB (Wi-Fi), paired with native macOS Finder integration (via FileProvider and FinderSync) and a dedicated standalone transfer manager.

---

## 2. Goals & Non-Goals

### 2.1 Goals
- **Universal Connectivity:** Seamless connection to any Android device running Android 5.0 through Android 15+ via USB (MTP or ADB) or Wireless Local Network (ADB over Wi-Fi).
- **Two-Way Transfers:** Full bidirectional read and write support (Mac-to-Android and Android-to-Mac) for individual files, nested folder structures, and large media files (>4 GB).
- **Finder Integration:** Ability to access Android storage directly inside Apple's native Finder, complete with custom device sidebar icons, badges, and contextual menus.
- **Robust Transfer Queue:** Asynchronous multi-item transfer queue featuring real-time throughput metrics, pause/resume, cancel, error retry policies, and collision handling.
- **Modern Apple Experience:** Native Swift/SwiftUI and AppKit interface optimized for Apple Silicon (M-series) and Intel architectures, respecting macOS design conventions, Dark Mode, and energy efficiency guidelines.
- **Clean-Room & Legal Compliance:** Strict adherence to clean-room reverse engineering principles, public standard specifications, and zero inclusion of proprietary or cracked code.

### 2.2 Non-Goals
- **Device Rooting or Bootloader Unlocking:** DroidBridge will not provide exploits, rooting tools, or flashing utilities (e.g., Fastboot / Odin).
- **Screen Mirroring / Remote Control:** DroidBridge focuses strictly on storage, filesystem operations, and file transfer (not Scrcpy-style video streaming).
- **Cloud Relay / Remote Internet Access:** DroidBridge transfers occur strictly over direct USB connection or secure local Wi-Fi. No user data traverses external servers.

---

## 3. Supported Connection Modes

### 3.1 Mode A: USB MTP (Media Transfer Protocol)
- **Target Audience:** General consumers who want plug-and-play operation without enabling Android Developer Options or USB Debugging.
- **Mechanism:** Direct USB communication via user-space MTP protocol engine (libmtp/libusb abstraction).
- **Permissions:** Standard Android "File Transfer / MTP" toggle selected on the device.
- **Capabilities:**
  - Read/write access to Android shared user storage (`/sdcard`, `DCIM`, `Download`, `Documents`, `Music`, `Movies`).
  - Automatic triggering of Android MediaScanner upon transfer completion so files appear immediately in Gallery/Music apps.

### 3.2 Mode B: USB ADB (Android Debug Bridge)
- **Target Audience:** Power users, developers, photographers, and audio/video professionals requiring maximum throughput, access to secondary storage, and enhanced reliability.
- **Mechanism:** Communication via local ADB daemon using ADB Sync protocol (`SYNC` command stream over TCP socket).
- **Permissions:** USB Debugging enabled on Android, host machine RSA public key authorized via device prompt.
- **Capabilities:**
  - Significantly faster transfer speeds than MTP due to full-duplex socket streaming.
  - Access to app-specific external storage and non-media directory hierarchies.
  - Granular POSIX file attributes (timestamps, permissions, exact byte sizes).

### 3.3 Mode C: Authorized Wireless ADB (Wi-Fi)
- **Target Audience:** Users desiring wireless convenience without connecting physical cables.
- **Mechanism:** 
  - Discovery via mDNS / Bonjour (`_adb-tls-connect._tcp` and `_adb-tls-pairing._tcp`).
  - Android 11+ secure pairing via 6-digit numeric code or pairing QR code.
  - Fallback to classic Wi-Fi ADB (`adb tcpip 5555`) for older Android releases.
- **Security:** End-to-end TLS encryption with host RSA keys securely stored in the macOS Keychain.

---

## 4. Functional Requirements

### 4.1 Device Discovery & Session Management
- **Hotplug Detection:** Real-time detection of USB connection and disconnection using IOKit device matching without requiring app restarts.
- **Multi-Device Support:** Simultaneous connection and distinct session management for multiple connected Android devices (e.g., phone and tablet connected concurrently).
- **Connection Health Monitoring:** Continuous heartbeat pinging; automatic graceful disconnection and UI state update when a cable is detached or Wi-Fi drops.

### 4.2 File Management & Browsing
- **Hierarchical Directory Navigation:** Fast tree and column browsing with deep directory path traversal.
- **File Metadata Presentation:** Filename, exact byte size, modification timestamp, file format type, and read/write permission flags.
- **Directory Operations:**
  - Create directory (`mkdir`).
  - Rename file or directory.
  - Delete single or multiple items (recursive deletion with confirmation dialog).
  - Quick Look preview integration (previewing images, audio, video, and text directly from device cache).
- **Search & Filter:** Instant in-memory client-side filtering and deep server-side directory search.

### 4.3 Transfer Engine & Queue Architecture
- **Bidirectional Streaming:** 
  - Host to Device (Upload / Push)
  - Device to Host (Download / Pull)
- **Chunked I/O:** 64 KB – 1 MB dynamically sized transfer chunks to maximize throughput while bounding memory usage.
- **Queue Controls:**
  - Pause, Resume, and Cancel per transfer job.
  - Global pause and clear completed.
  - Re-ordering and priority queueing.
- **Conflict Handling:** Configurable overwrite policies: Overwrite, Skip, Rename (Append timestamp), or Prompt User.
- **Integrity Verification:** Optional post-transfer checksum verification (CRC32 / MD5 / SHA-256) where supported by protocol.

### 4.4 Error Recovery & Fault Tolerance
- **Transient Network/Socket Retry:** Automatic exponential backoff retries (up to 3 attempts) for interrupted wireless socket streams.
- **Partial Resumption:** Ability to resume interrupted file downloads/uploads where the underlying protocol or filesystem allows append/offset writes.
- **Device Lock Detection:** Clear user prompts if the Android device is locked with a lock-screen passcode preventing MTP storage access.

### 4.5 Finder Integration
- **FileProvider Virtual Drive:** Integration with Apple's `FileProvider` framework (`NSFileProviderReplicatedExtension`), exposing the Android device as an external volume in the Finder sidebar and Locations list.
- **FinderSync Extensions:** Visual badge indicators on synchronized items and custom contextual right-click actions (e.g., "Copy to Android", "Open in DroidBridge").
- **Drag-and-Drop:** Full native drag-and-drop between Finder windows, desktop, and DroidBridge UI.

---

## 5. Non-Functional Requirements

### 5.1 Performance
- **Throughput:** Capable of saturating available interface bandwidth:
  - USB 3.0 ADB: > 45 MB/s sustained
  - USB 2.0 MTP: > 25–35 MB/s sustained
  - Wi-Fi 5 GHz: > 15–25 MB/s sustained
- **Resource Usage:** Memory usage capped under 80 MB for the core manager; zero buffer bloat (no full-file buffering in RAM).

### 5.2 Compatibility & Platform Support
- **Host OS:** macOS 12.0 (Monterey), macOS 13.0 (Ventura), macOS 14.0 (Sonoma), and macOS 15.0+ (Sequoia).
- **Hardware Architecture:** Universal 2 binary (Native Apple Silicon arm64 + Intel x86_64).
- **Target OS:** Android 5.0 (Lollipop) through Android 15+.

### 5.3 Security & Sandbox Compliance
- Compliance with macOS App Sandbox requirements.
- Secure key generation and storage: ADB private keys stored in macOS Keychain (`kSecClassKey`).
- Zero telemetry or network tracking.

---

## 6. Architecture & Implementation Principles
- **Languages:** 100% Swift 6.0 with Swift Concurrency (`async/await`, structured concurrency, actors for thread isolation).
- **UI Framework:** SwiftUI for primary interfaces and preferences; AppKit for native MenuBar and FinderSync extensions.
- **Modularity:** Strict separation of protocol transports (`DeviceTransport`) from presentation and queue scheduling.
