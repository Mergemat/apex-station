import ApexKit
import Foundation
import IOKit.hid

/// The Apex 5 in PC Bluetooth mode, where it is a plain Xbox Wireless Controller (see
/// `XboxBluetoothReport`). Gives the live view its input and can rumble; settings need the cable.
final class BluetoothPad: @unchecked Sendable {
    enum Event: Sendable {
        case connected
        case disconnected
    }

    let live = LiveInput()
    let eventStream: AsyncStream<Event>

    private let events: AsyncStream<Event>.Continuation
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    // Guarded by `lock`.
    private let lock = NSLock()
    private var device: IOHIDDevice?
    private var state = GamepadState()
    private var batteryPercent: Int?

    init() {
        (eventStream, events) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .bufferingNewest(16))
    }

    /// Battery level, once the controller has reported it.
    var battery: Int? { lock.withLock { batteryPercent } }

    func start() {
        let thread = Thread { [self] in runLoop() }
        thread.name = "apex.bluetooth.hid"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func rumble(strong: UInt8, weak: UInt8, duration: Duration) {
        guard let device = lock.withLock({ self.device }) else { return }
        let report = XboxBluetoothReport.rumble(strong: strong, weak: weak, duration: duration)
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
    }

    private func runLoop() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: XboxBluetoothReport.vendorID,
            kIOHIDProductIDKey: XboxBluetoothReport.productID,
            kIOHIDTransportKey: kIOHIDTransportBluetoothValue,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<BluetoothPad>.fromOpaque(ctx!).takeUnretainedValue().matched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            Unmanaged<BluetoothPad>.fromOpaque(ctx!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        CFRunLoopRun()
    }

    private func matched(_ device: IOHIDDevice) {
        let isNew = lock.withLock { () -> Bool in
            guard self.device == nil else { return false }
            self.device = device
            state = GamepadState()
            return true
        }
        guard isNew else { return }
        Log.settings.notice("bluetooth controller matched")
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, { ctx, _, _, _, _, report, length in
            let bytes = [UInt8](UnsafeBufferPointer(start: report, count: length))
            Unmanaged<BluetoothPad>.fromOpaque(ctx!).takeUnretainedValue().handle(bytes)
        }, Unmanaged.passUnretained(self).toOpaque())
        events.yield(.connected)
    }

    private func removed(_ device: IOHIDDevice) {
        let wasOurs = lock.withLock { () -> Bool in
            guard self.device === device else { return false }
            self.device = nil
            batteryPercent = nil
            return true
        }
        if wasOurs { events.yield(.disconnected) }
    }

    private func handle(_ report: [UInt8]) {
        if let percent = XboxBluetoothReport.battery(report) {
            lock.withLock { batteryPercent = percent }
            return
        }
        let new = lock.withLock { () -> GamepadState? in
            XboxBluetoothReport.apply(report, to: &state) ? state : nil
        }
        if let new { live.update(new) }
    }
}
