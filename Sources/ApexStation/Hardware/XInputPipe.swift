import ApexKit
import Foundation
import IOKit
import IOUSBHost

/// The Apex 5's standard Xbox 360 interface on the cable (USB interface 0): what games get,
/// after the controller's own remaps, gyro-to-stick and turbo. Reading it doesn't take the
/// controller over, so the app uses it to show the controller live whenever the window is
/// open. It reports about 1000 times a second, and goes quiet while something has taken the
/// controller over.
/// The interface is opened only while wanted, so Steam can claim it otherwise. Screen uploads
/// go through it too: packets out on endpoint 2, replies inside the input reports.
final class XInputPipe: @unchecked Sendable {
    let live = LiveInput()
    let eventStream: AsyncStream<Bool>

    private let events: AsyncStream<Bool>.Continuation
    private let lock = NSLock()
    private var wanted = false
    private var started = false
    /// The open interface, so letting go can abort the blocking read and uploads can write.
    private var current: (interface: IOUSBHostInterface, input: IOUSBHostPipe, output: IOUSBHostPipe?)?
    /// An upload packet waiting for its reply.
    private var waiter: (matches: ([UInt8]) -> Bool, done: DispatchSemaphore, reply: [UInt8]?)?

    init() {
        (eventStream, events) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(8))
    }

    /// Opens the interface (and keeps trying while the controller is away) or lets it go.
    func setWanted(_ on: Bool) {
        let (start, reading) = lock.withLock { () -> (Bool, IOUSBHostPipe?) in
            wanted = on
            defer { started = true }
            return (!started, current?.input)
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
            let output = try? pipe.interface.copyPipe(withAddress: 0x02)
            lock.withLock { current = (pipe.interface, pipe.pipe, output) }
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
            if Screen.isReply(bytes) {
                deliver(bytes)
            } else if let state = XInputReport.parse(bytes) {
                live.update(state)
            }
        }
    }

    var isOpen: Bool { lock.withLock { current != nil } }

    /// Sends one upload packet and waits for the reply that `matches`. Blocks, so call it off
    /// the main thread. Nil if the interface isn't open, the write failed or no reply came.
    func exchange(_ bytes: [UInt8], timeout: TimeInterval, matches: @escaping ([UInt8]) -> Bool) -> [UInt8]? {
        guard let (interface, output) = lock.withLock({ current.flatMap { c in c.output.map { (c.interface, $0) } } }),
              let buffer = try? interface.ioData(withCapacity: bytes.count) else { return nil }
        buffer.replaceBytes(in: NSRange(location: 0, length: bytes.count), withBytes: bytes)
        let done = DispatchSemaphore(value: 0)
        lock.withLock { waiter = (matches, done, nil) }
        defer { lock.withLock { waiter = nil } }
        var sent = 0
        // Interrupt pipes take no timeout; the controller takes a packet as soon as it's sent.
        guard (try? output.__sendIORequest(with: buffer, bytesTransferred: &sent, completionTimeout: 0)) != nil else { return nil }
        guard done.wait(timeout: .now() + timeout) == .success else { return nil }
        return lock.withLock { waiter?.reply }
    }

    private func deliver(_ reply: [UInt8]) {
        let done = lock.withLock { () -> DispatchSemaphore? in
            guard let w = waiter, w.reply == nil, w.matches(reply) else { return nil }
            waiter?.reply = reply
            return w.done
        }
        if let done { done.signal() } else {
            Log.usb.notice("screen reply \(reply.prefix(24).map { String(format: "%02x", $0) }.joined(separator: " "), privacy: .public)")
        }
    }
}
