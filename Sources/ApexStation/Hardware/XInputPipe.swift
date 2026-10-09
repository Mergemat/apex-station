import ApexKit
import Foundation
import IOKit
import IOUSBHost

/// The Apex 5's standard Xbox 360 interface on the cable (USB interface 0): what games get,
/// after the controller's own remaps, gyro-to-stick and turbo. Reading it doesn't take the
/// controller over, so the app uses it to show the controller live whenever the window is
/// open. It reports about 1000 times a second, and goes quiet while something has taken the
/// controller over.
/// The interface is opened only while wanted, so Steam can claim it otherwise.
final class XInputPipe: @unchecked Sendable {
    let live = LiveInput()
    let eventStream: AsyncStream<Bool>

    private let events: AsyncStream<Bool>.Continuation
    private let lock = NSLock()
    private var wanted = false
    private var started = false
    /// The pipe being read, so letting go can abort the blocking read.
    private var current: IOUSBHostPipe?

    init() {
        (eventStream, events) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(8))
    }

    /// Opens the interface (and keeps trying while the controller is away) or lets it go.
    func setWanted(_ on: Bool) {
        let (start, reading) = lock.withLock { () -> (Bool, IOUSBHostPipe?) in
            wanted = on
            defer { started = true }
            return (!started, current)
        }
        if !on { try? reading?.__abort(with: .synchronous) }
        guard start else { return }
        let thread = Thread { [self] in run() }
        thread.name = "apex.xinput"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private var isWanted: Bool { lock.withLock { wanted } }

    private func run() {
        while true {
            guard isWanted, let pipe = open() else {
                Thread.sleep(forTimeInterval: 1)
                continue
            }
            lock.withLock { current = pipe.pipe }
            events.yield(true)
            read(pipe.pipe, buffer: pipe.buffer)
            lock.withLock { current = nil }
            pipe.interface.destroy()
            events.yield(false)
        }
    }

    private func findInterface() -> io_service_t {
        let match = IOServiceMatching("IOUSBHostInterface") as NSMutableDictionary
        match["IOPropertyMatch"] = ["idVendor": Int(Flydigi.vendorID), "idProduct": Int(Flydigi.apex5ProductID), "bInterfaceNumber": 0]
        return IOServiceGetMatchingService(kIOMainPortDefault, match)
    }

    private func stillThere() -> Bool {
        let service = findInterface()
        defer { if service != 0 { IOObjectRelease(service) } }
        return service != 0
    }

    private func open() -> (interface: IOUSBHostInterface, pipe: IOUSBHostPipe, buffer: NSMutableData)? {
        let service = findInterface()
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let interface = try? IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil) else { return nil }
        // Transfers need a buffer the framework allocates.
        guard let pipe = try? interface.copyPipe(withAddress: 0x81), let buffer = try? interface.ioData(withCapacity: 64) else {
            interface.destroy()
            return nil
        }
        Log.usb.notice("xinput interface open")
        return (interface, pipe, buffer)
    }

    /// Reads until the interface goes away or isn't wanted any more.
    private func read(_ pipe: IOUSBHostPipe, buffer: NSMutableData) {
        var failures = 0
        while isWanted {
            var count = 0
            do {
                // Interrupt pipes take no timeout: this waits for the next report, and letting go
                // aborts it.
                try pipe.__sendIORequest(with: buffer, bytesTransferred: &count, completionTimeout: 0)
                failures = 0
            } catch {
                failures += 1
                guard isWanted, stillThere(), failures < 20 else {
                    Log.usb.notice("xinput interface closed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            let bytes = [UInt8](UnsafeRawBufferPointer(start: buffer.bytes, count: count))
            if let state = XInputReport.parse(bytes) { live.update(state) }
        }
    }

    var isOpen: Bool { lock.withLock { current != nil } }
}
