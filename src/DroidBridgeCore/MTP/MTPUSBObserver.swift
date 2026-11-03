import Foundation
import IOKit
import IOKit.usb
import Synchronization

/// Abstract observer protocol for USB hardware interface arrival and termination events.
public protocol MTPUSBObserverProtocol: Sendable {
    var isObserving: Bool { get }
    func startObserving(
        onMatched: @escaping @Sendable (MTPUSBInterfaceInfo) -> Void,
        onTerminated: @escaping @Sendable (UInt64) -> Void
    ) throws
    func stopObserving()
}

/// Global C callbacks for IOKit matching notifications
private func mtpInterfaceMatchedCallback(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    guard let refcon = refcon else { return }
    let observer = Unmanaged<IOKitMTPUSBObserver>.fromOpaque(refcon).takeUnretainedValue()
    observer.processMatchedIterator(iterator)
}

private func mtpInterfaceTerminatedCallback(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    guard let refcon = refcon else { return }
    let observer = Unmanaged<IOKitMTPUSBObserver>.fromOpaque(refcon).takeUnretainedValue()
    observer.processTerminatedIterator(iterator)
}

/// Native macOS event-driven IOKit USB observer.
/// Strictly implements passive, zero-open discovery:
/// Never calls `USBDeviceOpen`, `USBDeviceOpenSeize`, `USBInterfaceOpen`, or `USBInterfaceOpenSeize`.
public final class IOKitMTPUSBObserver: MTPUSBObserverProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _isObserving: Bool = false
    private var notificationPort: IONotificationPortRef? = nil
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var onMatched: (@Sendable (MTPUSBInterfaceInfo) -> Void)? = nil
    private var onTerminated: (@Sendable (UInt64) -> Void)? = nil
    
    private let dispatchQueue = DispatchQueue(label: "com.droidbridge.mtp.usb.observer", qos: .utility)
    
    public var isObserving: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isObserving
    }
    
    public init() {}
    
    public func startObserving(
        onMatched: @escaping @Sendable (MTPUSBInterfaceInfo) -> Void,
        onTerminated: @escaping @Sendable (UInt64) -> Void
    ) throws {
        stopObserving()
        
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            throw DeviceError.ioError(message: "Failed to create IOKit notification port.")
        }
        IONotificationPortSetDispatchQueue(port, dispatchQueue)
        
        lock.lock()
        _isObserving = true
        self.notificationPort = port
        self.onMatched = onMatched
        self.onTerminated = onTerminated
        lock.unlock()
        
        // Matching dictionary for IOUSBInterface
        guard let matchingDict1 = IOServiceMatching(kIOUSBInterfaceClassName) as? [String: Any],
              let matchingDict2 = IOServiceMatching(kIOUSBInterfaceClassName) as? [String: Any] else {
            IONotificationPortDestroy(port)
            lock.lock()
            _isObserving = false
            self.notificationPort = nil
            lock.unlock()
            throw DeviceError.ioError(message: "Failed to construct IOKit matching dictionaries.")
        }
        
        var matchedIter: io_iterator_t = 0
        let krMatched = IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            matchingDict1 as CFDictionary,
            mtpInterfaceMatchedCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &matchedIter
        )
        
        guard krMatched == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            lock.lock()
            _isObserving = false
            self.notificationPort = nil
            lock.unlock()
            throw DeviceError.ioError(message: "Failed to register IOKit matched notification (kr=\(krMatched)).")
        }
        
        var terminatedIter: io_iterator_t = 0
        let krTerminated = IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            matchingDict2 as CFDictionary,
            mtpInterfaceTerminatedCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &terminatedIter
        )
        
        guard krTerminated == KERN_SUCCESS else {
            IOObjectRelease(matchedIter)
            IONotificationPortDestroy(port)
            lock.lock()
            _isObserving = false
            self.notificationPort = nil
            lock.unlock()
            throw DeviceError.ioError(message: "Failed to register IOKit terminated notification (kr=\(krTerminated)).")
        }
        
        lock.lock()
        self.matchedIterator = matchedIter
        self.terminatedIterator = terminatedIter
        lock.unlock()
        
        // CRITICAL IOKIT REQUIREMENT:
        // Drain initial iterators completely to prime/arm future notifications
        // and discover any devices connected prior to launch.
        processMatchedIterator(matchedIter)
        processTerminatedIterator(terminatedIter)
    }
    
    public func stopObserving() {
        lock.lock()
        _isObserving = false
        let iter1 = matchedIterator
        let iter2 = terminatedIterator
        let portToDestroy = notificationPort
        matchedIterator = 0
        terminatedIterator = 0
        notificationPort = nil
        onMatched = nil
        onTerminated = nil
        lock.unlock()
        
        if iter1 != 0 { IOObjectRelease(iter1) }
        if iter2 != 0 { IOObjectRelease(iter2) }
        if let p = portToDestroy {
            IONotificationPortDestroy(p)
        }
    }
    
    internal func processMatchedIterator(_ iterator: io_iterator_t) {
        guard iterator != 0 else { return }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            
            // Passive extraction only — zero open calls
            if let info = MTPUSBInterfaceInfo.extract(from: service) {
                if info.isMTPCandidate {
                    lock.lock()
                    let callback = onMatched
                    lock.unlock()
                    callback?(info)
                }
            }
        }
    }
    
    internal func processTerminatedIterator(_ iterator: io_iterator_t) {
        guard iterator != 0 else { return }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            
            var entryID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS {
                lock.lock()
                let callback = onTerminated
                lock.unlock()
                callback?(entryID)
            }
        }
    }
    
    deinit {
        stopObserving()
    }
}

/// Simulated in-memory USB observer for unit tests.
public final class MockMTPUSBObserver: MTPUSBObserverProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _isObserving: Bool = false
    private var onMatched: (@Sendable (MTPUSBInterfaceInfo) -> Void)? = nil
    private var onTerminated: (@Sendable (UInt64) -> Void)? = nil
    
    public var isObserving: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isObserving
    }
    
    public init() {}
    
    public func startObserving(
        onMatched: @escaping @Sendable (MTPUSBInterfaceInfo) -> Void,
        onTerminated: @escaping @Sendable (UInt64) -> Void
    ) throws {
        lock.lock()
        _isObserving = true
        self.onMatched = onMatched
        self.onTerminated = onTerminated
        lock.unlock()
    }
    
    public func stopObserving() {
        lock.lock()
        _isObserving = false
        onMatched = nil
        onTerminated = nil
        lock.unlock()
    }
    
    public func simulateDeviceConnected(_ info: MTPUSBInterfaceInfo) {
        lock.lock()
        let callback = onMatched
        lock.unlock()
        callback?(info)
    }
    
    public func simulateDeviceDisconnected(entryID: UInt64) {
        lock.lock()
        let callback = onTerminated
        lock.unlock()
        callback?(entryID)
    }
}
