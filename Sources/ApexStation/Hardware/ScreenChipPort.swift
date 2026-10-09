import ApexKit
import Foundation
import IOKit
import IOKit.serial

/// The screen chip's USB serial port (FREQCHIP_COM), there only while the controller is updating
/// its screen. macOS needs no driver for it. See `ScreenChip` for the protocol.
enum ScreenChipPort {
    struct Failed: Error {
        let message: String
    }

    /// The port's path, like /dev/cu.usbmodem…, if the chip is on USB now.
    static func find() -> String? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOSerialBSDServiceValue), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { return nil }
            defer { IOObjectRelease(service) }
            func usb(_ key: String) -> Int? {
                IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? Int
            }
            guard usb("idVendor") == ScreenChip.vendorID, usb("idProduct") == ScreenChip.productID else { continue }
            if let path = IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String {
                return path
            }
        }
    }

    /// Writes `frames` to the chip, which then restarts the controller. Blocks until done;
    /// `progress` gets 0...1 (erasing is the first half, writing the second, as in Space Station).
    static func upload(_ frames: [[UInt8]], frameTime: Int, restoreDefault: Bool, port path: String,
                       progress: (Double) -> Void) throws {
        let data = frames.flatMap { $0 }
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw Failed(message: "Couldn't open the screen chip's port.") }
        defer { close(fd) }
        var t = termios()
        tcgetattr(fd, &t)
        cfmakeraw(&t)
        cfsetspeed(&t, 921_600)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        tcsetattr(fd, TCSANOW, &t)

        var buffer: [UInt8] = []
        func send(_ bytes: [UInt8]) throws {
            var sent = 0
            while sent < bytes.count {
                let n = bytes[sent...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                if n > 0 { sent += n } else if errno != EAGAIN { throw Failed(message: "The screen chip's port closed.") }
            }
        }
        /// The next successful reply with `op` whose payload `accept`s, or nil after `timeout`.
        /// The stream garbles a byte now and then, so other replies are skipped (Space Station
        /// doesn't read the result byte at all); the checksum at the end catches real problems.
        func reply(_ op: ScreenChip.Op, timeout: TimeInterval, accept: ([UInt8]) -> Bool = { _ in true }) throws -> [UInt8]? {
            let deadline = Date().addingTimeInterval(timeout)
            while true {
                while let r = ScreenChip.reply(op, in: buffer) {
                    buffer.removeFirst(r.used)
                    if r.result == 0, accept(r.payload) { return r.payload }
                }
                let left = deadline.timeIntervalSinceNow
                guard left > 0 else { return nil }
                var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                guard poll(&p, 1, Int32(min(left, 0.1) * 1000)) > 0 else { continue }
                var chunk = [UInt8](repeating: 0, count: 4096)
                let n = Darwin.read(fd, &chunk, chunk.count)
                if n > 0 { buffer += chunk[0..<n] } else if n == 0 || errno != EAGAIN { throw Failed(message: "The screen chip's port closed.") }
            }
        }
        func le(_ b: [UInt8]) -> UInt32 { b.prefix(4).enumerated().reduce(0) { $0 | UInt32($1.element) << ($1.offset * 8) } }

        try send(ScreenChip.start(frames: frames.count, frameTime: frameTime, restoreDefault: restoreDefault))
        guard let start = try reply(.start, timeout: 3), start.count >= 4 else { throw Failed(message: "The screen chip didn't answer.") }
        let base = le(start)
        Thread.sleep(forTimeInterval: 0.2)
        try send(ScreenChip.version)
        guard try reply(.version, timeout: 3) != nil else { throw Failed(message: "The screen chip didn't answer.") }

        let sectors = (data.count + ScreenChip.sectorSize - 1) / ScreenChip.sectorSize
        for i in 0..<sectors {
            let address = base + UInt32(i * ScreenChip.sectorSize)
            var done = false
            for _ in 0..<3 where !done {
                try send(ScreenChip.erase(at: address))
                done = try reply(.erase, timeout: 5) { $0.count < 4 || le($0) == address } != nil
            }
            guard done else { throw Failed(message: "The screen chip stopped answering while erasing.") }
            progress(Double(i + 1) / Double(sectors) / 2)
        }

        let pieces = (data.count + ScreenChip.pieceSize - 1) / ScreenChip.pieceSize
        for i in 0..<pieces {
            let address = base + UInt32(i * ScreenChip.pieceSize)
            let piece = data[(i * ScreenChip.pieceSize)..<min((i + 1) * ScreenChip.pieceSize, data.count)]
            // Some replies come twice; only the one for this address counts. A lost one means
            // writing the same piece again, which is harmless.
            var done = false
            for _ in 0..<6 where !done {
                try send(ScreenChip.write(piece, at: address))
                done = try reply(.write, timeout: 1) { le($0) == address } != nil
            }
            guard done else { throw Failed(message: "The screen chip stopped answering while writing.") }
            if i % 200 == 0 || i == pieces - 1 { progress(0.5 + Double(i + 1) / Double(pieces) / 2) }
        }

        buffer = []
        try send(ScreenChip.finish(data))
        guard try reply(.finish, timeout: 10) != nil else { throw Failed(message: "The screen chip didn't accept the upload.") }
    }
}
