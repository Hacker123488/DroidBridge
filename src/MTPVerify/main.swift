import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib

// MARK: - Constants & COM UUIDs

private let kIOUSBInterfaceUserClientTypeID_bytes = CFUUIDBytes(
    byte0: 0x2d, byte1: 0x97, byte2: 0x86, byte3: 0xc6,
    byte4: 0x9e, byte5: 0xf3, byte6: 0x11, byte7: 0xd4,
    byte8: 0xad, byte9: 0x51, byte10: 0x00, byte11: 0x0a,
    byte12: 0x27, byte13: 0x05, byte14: 0x28, byte15: 0x61
)

private let kIOCFPlugInInterfaceID_bytes = CFUUIDBytes(
    byte0: 0xc2, byte1: 0x44, byte2: 0xe8, byte3: 0x58,
    byte4: 0x10, byte5: 0x9c, byte6: 0x11, byte7: 0xd4,
    byte8: 0x91, byte9: 0xd4, byte10: 0x00, byte11: 0x50,
    byte12: 0xe4, byte13: 0xc6, byte14: 0x42, byte15: 0x6f
)

private let kIOUSBInterfaceInterfaceID500_bytes = CFUUIDBytes(
    byte0: 0x6c, byte1: 0x0d, byte2: 0x38, byte3: 0xc3,
    byte4: 0xb0, byte5: 0x93, byte6: 0x4e, byte7: 0xa7,
    byte8: 0x80, byte9: 0x9b, byte10: 0x09, byte11: 0xfb,
    byte12: 0x5d, byte13: 0xdd, byte14: 0xac, byte15: 0x16
)

private func createIOUSBInterfaceUserClientTypeID() -> CFUUID {
    CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, kIOUSBInterfaceUserClientTypeID_bytes)
}

private func createIOCFPlugInInterfaceID() -> CFUUID {
    CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, kIOCFPlugInInterfaceID_bytes)
}

// PTP Constants
private let PTP_USB_CONTAINER_HEADER_SIZE = 12
private let PTP_CONTAINER_TYPE_COMMAND: UInt16 = 1
private let PTP_CONTAINER_TYPE_DATA: UInt16 = 2
private let PTP_CONTAINER_TYPE_RESPONSE: UInt16 = 3
private let PTP_CONTAINER_TYPE_EVENT: UInt16 = 4

private let PTP_OPCODE_GET_DEVICE_INFO: UInt16 = 0x1001
private let PTP_OPCODE_OPEN_SESSION: UInt16 = 0x1002
private let PTP_OPCODE_CLOSE_SESSION: UInt16 = 0x1003
private let PTP_OPCODE_GET_STORAGE_IDS: UInt16 = 0x1004

private let PTP_RESPONSE_OK: UInt16 = 0x2001

// Standard error codes
private let kIOReturnExclusiveAccessCode: IOReturn = -536870203 // 0xE00002C5

// MARK: - PTP Container Structures

struct PTPContainer: Sendable {
    let length: UInt32
    let type: UInt16
    let code: UInt16
    let transactionID: UInt32
    let payload: Data
    
    init(type: UInt16, code: UInt16, transactionID: UInt32, params: [UInt32] = []) {
        self.type = type
        self.code = code
        self.transactionID = transactionID
        self.length = UInt32(PTP_USB_CONTAINER_HEADER_SIZE + params.count * 4)
        
        var d = Data(capacity: Int(self.length))
        var lenLE = self.length.littleEndian
        var typeLE = type.littleEndian
        var codeLE = code.littleEndian
        var txLE = transactionID.littleEndian
        
        withUnsafeBytes(of: &lenLE) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: &typeLE) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: &codeLE) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: &txLE) { d.append(contentsOf: $0) }
        
        for p in params {
            var paramLE = p.littleEndian
            withUnsafeBytes(of: &paramLE) { d.append(contentsOf: $0) }
        }
        self.payload = d.subdata(in: PTP_USB_CONTAINER_HEADER_SIZE..<d.count)
    }
    
    init?(headerData: Data, fullData: Data) {
        guard headerData.count >= PTP_USB_CONTAINER_HEADER_SIZE else { return nil }
        self.length = headerData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).littleEndian }
        self.type = headerData.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self).littleEndian }
        self.code = headerData.withUnsafeBytes { $0.load(fromByteOffset: 6, as: UInt16.self).littleEndian }
        self.transactionID = headerData.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self).littleEndian }
        
        if fullData.count > PTP_USB_CONTAINER_HEADER_SIZE {
            self.payload = fullData.subdata(in: PTP_USB_CONTAINER_HEADER_SIZE..<fullData.count)
        } else {
            self.payload = Data()
        }
    }
    
    func serialize() -> Data {
        var d = Data(capacity: Int(length))
        var lenLE = length.littleEndian
        var typeLE = type.littleEndian
        var codeLE = code.littleEndian
        var txLE = transactionID.littleEndian
        
        withUnsafeBytes(of: &lenLE) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: &typeLE) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: &codeLE) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: &txLE) { d.append(contentsOf: $0) }
        d.append(payload)
        return d
    }
}

// MARK: - Safe PTP Payload Parser

struct PTPPayloadReader {
    let data: Data
    var offset: Int = 0
    
    init(data: Data) {
        self.data = data
        self.offset = 0
    }
    
    mutating func readUInt16() -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        let val = data.subdata(in: offset..<offset+2).withUnsafeBytes {
            $0.load(as: UInt16.self).littleEndian
        }
        offset += 2
        return val
    }
    
    mutating func readUInt32() -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let val = data.subdata(in: offset..<offset+4).withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        }
        offset += 4
        return val
    }
    
    mutating func readString() -> String {
        guard offset < data.count else { return "" }
        let charCount = Int(data[offset])
        offset += 1
        guard charCount > 0 else { return "" }
        
        let byteCount = (charCount - 1) * 2 // exclude trailing null
        let totalBytes = charCount * 2
        guard offset + totalBytes <= data.count else {
            offset = data.count
            return ""
        }
        
        let strData = data.subdata(in: offset..<offset+byteCount)
        offset += totalBytes
        return String(data: strData, encoding: .utf16LittleEndian) ?? ""
    }
    
    mutating func readUInt16Array() -> [UInt16] {
        guard let count = readUInt32() else { return [] }
        guard offset + Int(count) * 2 <= data.count else { return [] }
        var result: [UInt16] = []
        result.reserveCapacity(Int(count))
        for _ in 0..<count {
            if let val = readUInt16() {
                result.append(val)
            }
        }
        return result
    }
    
    mutating func readUInt32Array() -> [UInt32] {
        guard let count = readUInt32() else { return [] }
        guard offset + Int(count) * 4 <= data.count else { return [] }
        var result: [UInt32] = []
        result.reserveCapacity(Int(count))
        for _ in 0..<count {
            if let val = readUInt32() {
                result.append(val)
            }
        }
        return result
    }
}

// MARK: - MTP Device Information Model

struct MTPDeviceInfo {
    let standardVersion: UInt16
    let vendorExtensionID: UInt32
    let vendorExtensionVersion: UInt16
    let vendorExtensionDesc: String
    let functionalMode: UInt16
    let operationsSupported: [UInt16]
    let eventsSupported: [UInt16]
    let devicePropertiesSupported: [UInt16]
    let captureFormats: [UInt16]
    let imageFormats: [UInt16]
    let manufacturer: String
    let model: String
    let deviceVersion: String
    let serialNumber: String
}

// MARK: - USB Transport Driver

final class MTPUSBTransport {
    private let intf: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceStruct500>>
    private let plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>
    private let service: io_service_t
    
    let bulkInPipe: UInt8
    let bulkOutPipe: UInt8
    let interruptInPipe: UInt8?
    let bulkInMaxPacketSize: UInt16
    let bulkOutMaxPacketSize: UInt16
    
    private(set) var isOpen: Bool = false
    
    init?(service: io_service_t) {
        self.service = service
        var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        
        let plugRes = IOCreatePlugInInterfaceForService(
            service,
            createIOUSBInterfaceUserClientTypeID(),
            createIOCFPlugInInterfaceID(),
            &plugInInterface,
            &score
        )
        guard plugRes == KERN_SUCCESS, let plugPtr = plugInInterface, let plug = plugPtr.pointee else {
            return nil
        }
        self.plugIn = plugPtr
        
        var interfacePointer: UnsafeMutableRawPointer?
        let queryRes = plug.pointee.QueryInterface(
            plugPtr,
            kIOUSBInterfaceInterfaceID500_bytes,
            &interfacePointer
        )
        guard queryRes == KERN_SUCCESS, let rawIntf = interfacePointer else {
            _ = IODestroyPlugInInterface(plugPtr)
            return nil
        }
        self.intf = rawIntf.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBInterfaceStruct500>.self)
        
        // Inspect pipes
        var inPipe: UInt8 = 0
        var outPipe: UInt8 = 0
        var intPipe: UInt8? = nil
        var inMaxPacket: UInt16 = 512
        var outMaxPacket: UInt16 = 512
        
        // Open interface to enable pipe property inspection
        let openRes = self.intf.pointee.pointee.USBInterfaceOpen(self.intf)
        if openRes != KERN_SUCCESS {
            print("[USB] USBInterfaceOpen failed with code: 0x\(String(UInt32(bitPattern: openRes), radix: 16))")
            if openRes == kIOReturnExclusiveAccessCode {
                print("[USB] EXCLUSIVE ACCESS ERROR (0xE00002C5):")
                print("      Another application or macOS service (such as Apple Photos, Image Capture,")
                print("      Android File Transfer, Google Drive, or OpenMTP) is holding the interface.")
                print("      Troubleshooting: Close conflicting applications and re-run.")
            }
            _ = self.intf.pointee.pointee.Release(self.intf)
            _ = IODestroyPlugInInterface(self.plugIn)
            return nil
        }
        self.isOpen = true
        
        var numEndpoints: UInt8 = 0
        _ = self.intf.pointee.pointee.GetNumEndpoints(self.intf, &numEndpoints)
        for pipeRef in 1...numEndpoints {
            var direction: UInt8 = 0
            var number: UInt8 = 0
            var transferType: UInt8 = 0
            var maxPacketSize: UInt16 = 0
            var interval: UInt8 = 0
            
            _ = self.intf.pointee.pointee.GetPipeProperties(
                self.intf,
                pipeRef,
                &direction,
                &number,
                &transferType,
                &maxPacketSize,
                &interval
            )
            
            let dirStr = direction == 1 ? "IN" : (direction == 0 ? "OUT" : "Unknown(\(direction))")
            let typeStr = transferType == 2 ? "Bulk" : (transferType == 3 ? "Interrupt" : "Other(\(transferType))")
            print("  [USB] Pipe #\(pipeRef): Endpoint \(number) (\(dirStr)), Type: \(typeStr), wMaxPacketSize: \(maxPacketSize)")
            
            if transferType == 2 { // Bulk
                if direction == 1 {
                    inPipe = pipeRef
                    inMaxPacket = maxPacketSize
                } else if direction == 0 {
                    outPipe = pipeRef
                    outMaxPacket = maxPacketSize
                }
            } else if transferType == 3 && direction == 1 { // Interrupt IN
                intPipe = pipeRef
            }
        }
        
        guard inPipe != 0 && outPipe != 0 else {
            print("[USB] Error: Required Bulk-IN and Bulk-OUT endpoints not found.")
            _ = self.intf.pointee.pointee.USBInterfaceClose(self.intf)
            _ = self.intf.pointee.pointee.Release(self.intf)
            _ = IODestroyPlugInInterface(self.plugIn)
            return nil
        }
        
        self.bulkInPipe = inPipe
        self.bulkOutPipe = outPipe
        self.interruptInPipe = intPipe
        self.bulkInMaxPacketSize = inMaxPacket
        self.bulkOutMaxPacketSize = outMaxPacket
    }
    
    func close() {
        if isOpen {
            _ = intf.pointee.pointee.USBInterfaceClose(intf)
            isOpen = false
            print("[USB] Interface closed.")
        }
        _ = intf.pointee.pointee.Release(intf)
        _ = IODestroyPlugInInterface(plugIn)
        IOObjectRelease(service)
        print("[USB] COM and IOKit resources cleanly released.")
    }
    
    // MARK: - USB Packet I/O
    
    func write(data: Data, timeoutMs: UInt32 = 5000) throws {
        guard isOpen else { throw NSError(domain: "MTPUSBTransport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Interface not open"]) }
        var bytes = [UInt8](data)
        let count = UInt32(bytes.count)
        let kr = intf.pointee.pointee.WritePipeTO(intf, bulkOutPipe, &bytes, count, timeoutMs, timeoutMs)
        guard kr == KERN_SUCCESS else {
            throw NSError(domain: "MTPUSBTransport", code: Int(kr), userInfo: [NSLocalizedDescriptionKey: "WritePipeTO failed with 0x\(String(UInt32(bitPattern: kr), radix: 16))"])
        }
        
        // ZLP check: if transfer length is exact multiple of wMaxPacketSize, determine if ZLP is needed
        if count > 0 && (count % UInt32(bulkOutMaxPacketSize)) == 0 {
            // Some devices require explicit ZLP when ending on packet boundary for large transfers
        }
    }
    
    func readContainer(timeoutMs: UInt32 = 5000) throws -> PTPContainer {
        guard isOpen else { throw NSError(domain: "MTPUSBTransport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Interface not open"]) }
        
        // Read initial chunk (at least 12-byte header, up to bulk max packet size)
        var buffer = [UInt8](repeating: 0, count: max(Int(bulkInMaxPacketSize), 512))
        var readBytes: UInt32 = UInt32(buffer.count)
        
        let kr = intf.pointee.pointee.ReadPipeTO(intf, bulkInPipe, &buffer, &readBytes, timeoutMs, timeoutMs)
        guard kr == KERN_SUCCESS else {
            throw NSError(domain: "MTPUSBTransport", code: Int(kr), userInfo: [NSLocalizedDescriptionKey: "ReadPipeTO failed with 0x\(String(UInt32(bitPattern: kr), radix: 16))"])
        }
        guard readBytes >= PTP_USB_CONTAINER_HEADER_SIZE else {
            throw NSError(domain: "MTPUSBTransport", code: -2, userInfo: [NSLocalizedDescriptionKey: "Truncated PTP header: received \(readBytes) bytes"])
        }
        
        var receivedData = Data(buffer[0..<Int(readBytes)])
        let expectedTotalLength = receivedData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).littleEndian }
        
        // Ingest remaining chunks until entire container length is satisfied
        while receivedData.count < expectedTotalLength {
            var chunkBuffer = [UInt8](repeating: 0, count: max(Int(bulkInMaxPacketSize), 4096))
            var chunkBytes: UInt32 = UInt32(chunkBuffer.count)
            let chunkKr = intf.pointee.pointee.ReadPipeTO(intf, bulkInPipe, &chunkBuffer, &chunkBytes, timeoutMs, timeoutMs)
            guard chunkKr == KERN_SUCCESS else {
                throw NSError(domain: "MTPUSBTransport", code: Int(chunkKr), userInfo: [NSLocalizedDescriptionKey: "Chunk read failed with 0x\(String(UInt32(bitPattern: chunkKr), radix: 16))"])
            }
            guard chunkBytes > 0 else { break }
            receivedData.append(contentsOf: chunkBuffer[0..<Int(chunkBytes)])
        }
        
        guard let container = PTPContainer(headerData: receivedData.subdata(in: 0..<PTP_USB_CONTAINER_HEADER_SIZE), fullData: receivedData) else {
            throw NSError(domain: "MTPUSBTransport", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to construct PTPContainer from received data"])
        }
        return container
    }
}

// MARK: - MTP Execution Pipeline

@main
struct MTPVerifyMain {
    static func main() async {
        print("==================================================")
        print(" DroidBridge Milestone 3.1.1: Native MTP POC")
        print(" Platform: macOS / Swift 6 / IOKit COM Plugin")
        print(" Target: Physical Realme RMX3092 (USB Debugging OFF)")
        print("==================================================")
        print()
        
        print("[USB] Searching for connected USB devices...")
        guard let matching = IOServiceMatching(kIOUSBInterfaceClassName) as? [String: Any] else {
            print("❌ [USB] Failed to create IOKit matching dictionary.")
            exit(1)
        }
        
        var iter: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching as CFDictionary, &iter)
        guard kr == KERN_SUCCESS else {
            print("❌ [USB] IOServiceGetMatchingServices failed with code: \(kr)")
            exit(1)
        }
        defer { IOObjectRelease(iter) }
        
        var candidateService: io_service_t = 0
        var foundDeviceName: String = ""
        var foundInterfaceNumber: Int = 0
        
        while case let service = IOIteratorNext(iter), service != 0 {
            var rawName = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(service, &rawName)
            let sName = rawName.withUnsafeBufferPointer { ptr in
                String(cString: ptr.baseAddress!)
            }
            
            let vid = (IORegistryEntryCreateCFProperty(service, "idVendor" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
            let pid = (IORegistryEntryCreateCFProperty(service, "idProduct" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
            let bIntfClass = (IORegistryEntryCreateCFProperty(service, "bInterfaceClass" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
            let bIntfSubClass = (IORegistryEntryCreateCFProperty(service, "bInterfaceSubClass" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
            let bIntfProtocol = (IORegistryEntryCreateCFProperty(service, "bInterfaceProtocol" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
            let intfNumber = (IORegistryEntryCreateCFProperty(service, "bInterfaceNumber" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
            let prodName = (IORegistryEntryCreateCFProperty(service, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String) ?? sName
            let serialNum = (IORegistryEntryCreateCFProperty(service, "USB Serial Number" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String) ?? "Unknown"
            
            let isRealmeVID = (vid == 0x22D9)
            let isMTPClass = (bIntfClass == 6 && bIntfSubClass == 1 && bIntfProtocol == 1) || (bIntfClass == 255 && bIntfSubClass == 255 && bIntfProtocol == 0)
            let isMTPName = (sName == "MTP")
            
            if isRealmeVID || isMTPClass || isMTPName {
                print("[USB] Device discovered")
                print("  Product Name:  \(prodName)")
                print("  Serial Number: \(serialNum)")
                print("  VID: 0x\(String(vid, radix: 16).uppercased()) PID: 0x\(String(pid, radix: 16).uppercased())")
                print("  Interface: #\(intfNumber) (\(sName))")
                print("  Descriptor: Class: 0x\(String(bIntfClass, radix: 16)), SubClass: 0x\(String(bIntfSubClass, radix: 16)), Protocol: 0x\(String(bIntfProtocol, radix: 16))")
                
                if (isMTPClass || isMTPName) && candidateService == 0 {
                    candidateService = service
                    foundDeviceName = prodName
                    foundInterfaceNumber = intfNumber
                    print("[USB] Candidate MTP interface identified")
                    continue
                }
            }
            IOObjectRelease(service)
        }
        
        guard candidateService != 0 else {
            print()
            print("❌ [USB] No compatible Android MTP interface found.")
            print("   Please ensure:")
            print("   1. Physical Realme RMX3092 is plugged into USB.")
            print("   2. USB configuration on phone is set to 'File Transfer (MTP)'.")
            print("   3. Phone screen is UNLOCKED.")
            exit(1)
        }
        
        print()
        print("[USB] Opening USB interface for \(foundDeviceName) (Interface #\(foundInterfaceNumber))...")
        guard let transport = MTPUSBTransport(service: candidateService) else {
            print("❌ [USB] Failed to open MTP USB interface.")
            exit(1)
        }
        defer {
            transport.close()
        }
        
        print("[USB] Device successfully opened")
        print("[USB] Interface successfully opened")
        print("[USB] Bulk-IN endpoint:  Pipe #\(transport.bulkInPipe) (wMaxPacketSize: \(transport.bulkInMaxPacketSize))")
        print("[USB] Bulk-OUT endpoint: Pipe #\(transport.bulkOutPipe) (wMaxPacketSize: \(transport.bulkOutMaxPacketSize))")
        if let intPipe = transport.interruptInPipe {
            print("[USB] Interrupt-IN endpoint: Pipe #\(intPipe)")
        }
        print("[USB] USB communication ready")
        print()
        
        do {
            // STEP 1: OpenSession (0x1002)
            print("[PTP] Step 1: OpenSession...")
            let openSessionCmd = PTPContainer(
                type: PTP_CONTAINER_TYPE_COMMAND,
                code: PTP_OPCODE_OPEN_SESSION,
                transactionID: 0x00000000,
                params: [1] // SessionID = 1
            )
            try transport.write(data: openSessionCmd.serialize())
            let openSessionResp = try transport.readContainer()
            guard openSessionResp.type == PTP_CONTAINER_TYPE_RESPONSE && openSessionResp.code == PTP_RESPONSE_OK else {
                print("❌ [PTP] OpenSession failed with response code: 0x\(String(openSessionResp.code, radix: 16))")
                exit(1)
            }
            print("  ✓ [PTP] OpenSession: SUCCESS (Response: 0x\(String(openSessionResp.code, radix: 16)))")
            print()
            
            // STEP 2: GetDeviceInfo (0x1001)
            print("[PTP] Step 2: GetDeviceInfo...")
            let getDevInfoCmd = PTPContainer(
                type: PTP_CONTAINER_TYPE_COMMAND,
                code: PTP_OPCODE_GET_DEVICE_INFO,
                transactionID: 1
            )
            try transport.write(data: getDevInfoCmd.serialize())
            
            // Ingest Data Container
            let devInfoDataContainer = try transport.readContainer()
            guard devInfoDataContainer.type == PTP_CONTAINER_TYPE_DATA else {
                print("❌ [PTP] Expected Data container (2) for GetDeviceInfo, received type: \(devInfoDataContainer.type)")
                exit(1)
            }
            
            // Ingest Response Container
            let devInfoRespContainer = try transport.readContainer()
            guard devInfoRespContainer.type == PTP_CONTAINER_TYPE_RESPONSE && devInfoRespContainer.code == PTP_RESPONSE_OK else {
                print("❌ [PTP] GetDeviceInfo failed with response code: 0x\(String(devInfoRespContainer.code, radix: 16))")
                exit(1)
            }
            print("  ✓ [PTP] GetDeviceInfo: SUCCESS")
            
            // Parse Device Info
            var reader = PTPPayloadReader(data: devInfoDataContainer.payload)
            let stdVer = reader.readUInt16() ?? 0
            let vendorExtID = reader.readUInt32() ?? 0
            let vendorExtVer = reader.readUInt16() ?? 0
            let vendorExtDesc = reader.readString()
            _ = reader.readUInt16() // functionalMode
            let ops = reader.readUInt16Array()
            _ = reader.readUInt16Array() // events
            _ = reader.readUInt16Array() // devProps
            _ = reader.readUInt16Array() // captureFormats
            _ = reader.readUInt16Array() // imageFormats
            let manufacturer = reader.readString()
            let model = reader.readString()
            let devVersion = reader.readString()
            let serial = reader.readString()
            
            print("  Manufacturer:   \(manufacturer)")
            print("  Model:          \(model)")
            print("  DeviceVersion:  \(devVersion)")
            print("  SerialNumber:   \(serial)")
            print("  StandardVer:    \(Double(stdVer) / 100.0)")
            print("  VendorExtension: ID: 0x\(String(vendorExtID, radix: 16)), Ver: \(vendorExtVer), Desc: '\(vendorExtDesc)'")
            let opsHex = ops.map { "0x" + String($0, radix: 16) }.joined(separator: ", ")
            print("  Supported Operations (\(ops.count)): [\(opsHex)]")
            print()
            
            // STEP 3: GetStorageIDs (0x1004)
            print("[PTP] Step 3: GetStorageIDs...")
            let getStorageIDsCmd = PTPContainer(
                type: PTP_CONTAINER_TYPE_COMMAND,
                code: PTP_OPCODE_GET_STORAGE_IDS,
                transactionID: 2
            )
            try transport.write(data: getStorageIDsCmd.serialize())
            
            let storageDataContainer = try transport.readContainer()
            guard storageDataContainer.type == PTP_CONTAINER_TYPE_DATA else {
                print("❌ [PTP] Expected Data container for GetStorageIDs, received: \(storageDataContainer.type)")
                exit(1)
            }
            
            let storageRespContainer = try transport.readContainer()
            guard storageRespContainer.type == PTP_CONTAINER_TYPE_RESPONSE && storageRespContainer.code == PTP_RESPONSE_OK else {
                print("❌ [PTP] GetStorageIDs failed with response code: 0x\(String(storageRespContainer.code, radix: 16))")
                exit(1)
            }
            print("  ✓ [PTP] GetStorageIDs: SUCCESS")
            
            var storageReader = PTPPayloadReader(data: storageDataContainer.payload)
            let storageIDs = storageReader.readUInt32Array()
            print("  Discovered Storage Count: \(storageIDs.count)")
            for (idx, sid) in storageIDs.enumerated() {
                let hexSid = "0x" + String(sid, radix: 16)
                let typeDesc = (sid == 0x00010001) ? "Primary Internal Flash" : "Removable External Storage"
                print("  -> Storage [\(idx)]: \(hexSid) (\(typeDesc))")
            }
            print()
            
            // STEP 4: CloseSession (0x1003)
            print("[PTP] Step 4: CloseSession...")
            let closeSessionCmd = PTPContainer(
                type: PTP_CONTAINER_TYPE_COMMAND,
                code: PTP_OPCODE_CLOSE_SESSION,
                transactionID: 3,
                params: [1]
            )
            try transport.write(data: closeSessionCmd.serialize())
            let closeSessionResp = try transport.readContainer()
            guard closeSessionResp.type == PTP_CONTAINER_TYPE_RESPONSE && closeSessionResp.code == PTP_RESPONSE_OK else {
                print("❌ [PTP] CloseSession failed with code: 0x\(String(closeSessionResp.code, radix: 16))")
                exit(1)
            }
            print("  ✓ [PTP] CloseSession: SUCCESS (Response: 0x\(String(closeSessionResp.code, radix: 16)))")
            print()
            
            print("==================================================")
            print("🎉 ALL MTP VERIFICATION CRITERIA PASSED ON HARDWARE!")
            print("==================================================")
        } catch {
            print("❌ [PTP] Communication error: \(error.localizedDescription)")
            exit(1)
        }
    }
}
