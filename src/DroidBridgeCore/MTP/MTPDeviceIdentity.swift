import Foundation

/// Defines canonical hardware identity rules and correlation logic between ADB and MTP representations.
public enum MTPDeviceIdentity {
    /// Constructs a standardized `DeviceDescriptor` from a verified MTP USB interface.
    public static func makeDescriptor(from interfaceInfo: MTPUSBInterfaceInfo) -> DeviceDescriptor {
        let serial = interfaceInfo.serialNumber
        let deviceID = serial.isEmpty ? "USB-MTP-\(interfaceInfo.entryID)" : serial
        let model = interfaceInfo.productName.isEmpty ? "Android Device" : interfaceInfo.productName
        let displayName: String
        if !serial.isEmpty {
            displayName = "\(model) (\(serial))"
        } else {
            displayName = "\(model) (MTP)"
        }
        
        return DeviceDescriptor(
            id: deviceID,
            name: displayName,
            model: model,
            connectionType: .usbMTP,
            isSimulated: false,
            status: .available
        )
    }
}

/// Correlates discovered devices across different transports (ADB, MTP, and Mocks) into a unified list.
/// Implements the Canonical Hardware Identity rules:
/// 1. Exact matching USB serial number and ADB serial number represents the same physical device.
/// 2. In coexistence (USB debugging ON), ADB is preferred for active file operations, avoiding duplicates.
/// 3. In MTP-only mode (USB debugging OFF), the MTP descriptor is surfaced with .usbMTP.
/// 4. Devices with different serials are strictly preserved as separate entries.
/// 5. Never merges devices based on model, VID, or PID alone.
public struct DeviceCorrelationManager: Sendable {
    public static func correlate(
        adbDevices: [DeviceDescriptor],
        mtpDevices: [DeviceDescriptor],
        mockDevices: [DeviceDescriptor] = []
    ) -> [DeviceDescriptor] {
        var unified: [DeviceDescriptor] = []
        var matchedMTPSerials = Set<String>()
        
        // 1. Process ADB devices
        for adb in adbDevices {
            let adbSerial = adb.id.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check for exact matching serial in discovered MTP devices
            if !adbSerial.isEmpty, let matchedMTP = mtpDevices.first(where: {
                let mtpSerial = $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
                return !mtpSerial.isEmpty && mtpSerial == adbSerial
            }) {
                matchedMTPSerials.insert(matchedMTP.id)
                // Same physical hardware: Retain ADB descriptor as primary transport
                unified.append(adb)
            } else {
                unified.append(adb)
            }
        }
        
        // 2. Add remaining MTP devices whose serial did not match an active ADB device
        for mtp in mtpDevices {
            if !matchedMTPSerials.contains(mtp.id) {
                unified.append(mtp)
            }
        }
        
        // 3. Add simulated mock devices (guaranteed distinct simulated GUIDs)
        unified.append(contentsOf: mockDevices)
        
        return unified
    }
}
