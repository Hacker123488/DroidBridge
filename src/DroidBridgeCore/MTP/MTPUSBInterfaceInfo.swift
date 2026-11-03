import Foundation
import IOKit
import IOKit.usb

/// Strongly-typed information describing a discovered USB interface,
/// extracted purely through passive IOKit registry inspection without opening the device.
public struct MTPUSBInterfaceInfo: Sendable, Equatable {
    /// 64-bit unique IOKit registry entry ID for tracking arrival and termination.
    public let entryID: UInt64
    
    /// USB Vendor ID (e.g. 0x22D9 for Realme/OPPO, 0x18D1 for Google, 0x04E8 for Samsung).
    public let vendorID: UInt16
    
    /// USB Product ID.
    public let productID: UInt16
    
    /// USB Interface Class (e.g. 6 for PTP/Still Image, 255 for Vendor-Specific).
    public let interfaceClass: UInt8
    
    /// USB Interface SubClass.
    public let interfaceSubClass: UInt8
    
    /// USB Interface Protocol.
    public let interfaceProtocol: UInt8
    
    /// Zero-based USB Interface Number (e.g. 0).
    public let interfaceNumber: UInt8
    
    /// USB Product Name (e.g. "RMX3092").
    public let productName: String
    
    /// USB Serial Number (e.g. "AE9PH68T4DV86L9P").
    public let serialNumber: String
    
    /// IOKit registry entry name (e.g. "MTP", "IOUSBHostInterface").
    public let registryName: String
    
    public init(
        entryID: UInt64,
        vendorID: UInt16,
        productID: UInt16,
        interfaceClass: UInt8,
        interfaceSubClass: UInt8,
        interfaceProtocol: UInt8,
        interfaceNumber: UInt8,
        productName: String,
        serialNumber: String,
        registryName: String
    ) {
        self.entryID = entryID
        self.vendorID = vendorID
        self.productID = productID
        self.interfaceClass = interfaceClass
        self.interfaceSubClass = interfaceSubClass
        self.interfaceProtocol = interfaceProtocol
        self.interfaceNumber = interfaceNumber
        self.productName = productName
        self.serialNumber = serialNumber
        self.registryName = registryName
    }
    
    /// Evaluates whether this USB interface matches standard or vendor-specific MTP/PTP patterns.
    public var isMTPCandidate: Bool {
        // Standard PTP / Still Image / MTP: Class 6 (Still Imaging), SubClass 1 (Still Image Capture), Protocol 1 (PIMA 15740)
        let isStandardPTP = (interfaceClass == 6 && interfaceSubClass == 1 && interfaceProtocol == 1)
        
        // Android Vendor-Specific MTP: Class 255 (0xFF), SubClass 255 (0xFF), Protocol 0 (0x00)
        let isAndroidVendorMTP = (interfaceClass == 255 && interfaceSubClass == 255 && interfaceProtocol == 0)
        
        // Secondary identifier: Interface or product name contains "MTP"
        let isNamedMTP = registryName == "MTP" || productName.localizedCaseInsensitiveContains("MTP")
        
        return isStandardPTP || isAndroidVendorMTP || isNamedMTP
    }
    
    /// Extracts interface information from an active IOKit `io_service_t` purely via passive registry queries.
    /// Never invokes `USBDeviceOpen`, `USBInterfaceOpen`, or any COM claiming method.
    public static func extract(from service: io_service_t) -> MTPUSBInterfaceInfo? {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else {
            return nil
        }
        
        var rawName = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(service, &rawName)
        let regName = rawName.withUnsafeBufferPointer { ptr in
            String(cString: ptr.baseAddress!)
        }
        
        // Query interface properties
        let bIntfClass = (readProperty(service, key: "bInterfaceClass") as Int?) ?? 0
        let bIntfSubClass = (readProperty(service, key: "bInterfaceSubClass") as Int?) ?? 0
        let bIntfProtocol = (readProperty(service, key: "bInterfaceProtocol") as Int?) ?? 0
        let intfNumber = (readProperty(service, key: "bInterfaceNumber") as Int?) ?? 0
        
        // VID, PID, Product Name, Serial Number may reside on the interface or its parent IOUSBDevice
        let vid = (readProperty(service, key: "idVendor", checkParent: true) as Int?) ?? 0
        let pid = (readProperty(service, key: "idProduct", checkParent: true) as Int?) ?? 0
        let prodName = (readProperty(service, key: "USB Product Name", checkParent: true) as String?) ?? regName
        let serial = (readProperty(service, key: "USB Serial Number", checkParent: true) as String?) ?? ""
        
        return MTPUSBInterfaceInfo(
            entryID: entryID,
            vendorID: UInt16(clamping: vid),
            productID: UInt16(clamping: pid),
            interfaceClass: UInt8(clamping: bIntfClass),
            interfaceSubClass: UInt8(clamping: bIntfSubClass),
            interfaceProtocol: UInt8(clamping: bIntfProtocol),
            interfaceNumber: UInt8(clamping: intfNumber),
            productName: prodName,
            serialNumber: serial.trimmingCharacters(in: .whitespacesAndNewlines),
            registryName: regName
        )
    }
    
    /// Safe helper to read a CFProperty from a registry entry, optionally falling back to its parent entry.
    private static func readProperty<T>(_ service: io_service_t, key: String, checkParent: Bool = false) -> T? {
        if let prop = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T {
            return prop
        }
        
        if checkParent {
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
                defer { IOObjectRelease(parent) }
                if let prop = IORegistryEntryCreateCFProperty(parent, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? T {
                    return prop
                }
            }
        }
        
        return nil
    }
}
