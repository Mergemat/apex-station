import Foundation

/// The Apex 5's 160×80 screen and how Space Station uploads an animation to it.
///
/// Each frame is an LVGL binary image: a 4-byte header (true colour, 160×80) then RGB565 pixels,
/// high byte first. Uploads go over the cable's Xbox interface (interface 0, out endpoint 2), not
/// the settings interface: start → 26-byte chunks → end per frame, then one finish, in Space
/// Station's "XInput" packets (`A5 <cmd> …`, sum of the bytes after `A5`). Replies come back in
/// the interface's input reports. The controller shows the new animation after it restarts.
public enum Screen {
    public static let width = 160
    public static let height = 80
    /// Space Station's limit for the Apex 5.
    public static let maxFrames = 150
    public static let frameSize = 4 + width * height * 2
    /// LVGL header: colour format 4 (true colour), width 160, height 80.
    public static let header: [UInt8] = [0x04, 0x80, 0x02, 0x0A]

    /// Encodes one frame from 160×80 RGBA pixels (row by row, 4 bytes each; alpha ignored).
    public static func frame(rgba: [UInt8]) -> [UInt8] {
        precondition(rgba.count == width * height * 4)
        var out = header
        out.reserveCapacity(frameSize)
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let r = UInt16(rgba[i]) >> 3, g = UInt16(rgba[i + 1]) >> 2, b = UInt16(rgba[i + 2]) >> 3
            let px = r << 11 | g << 5 | b
            out.append(UInt8(px >> 8))
            out.append(UInt8(px & 0xFF))
        }
        return out
    }

    /// Splits a file of frames (like Space Station's default animations) into frames.
    public static func frames(in data: [UInt8]) -> [[UInt8]] {
        guard data.count % frameSize == 0 else { return [] }
        return stride(from: 0, to: data.count, by: frameSize).map { Array(data[$0..<($0 + frameSize)]) }
    }

    public struct Packet: Sendable, Equatable {
        /// The whole packet, `A5` first.
        public var bytes: [UInt8]
        public var command: UInt8
        /// For chunks, the offset the controller echoes back.
        public var offset: Int?
        /// Ending a frame waits for the controller to write it to flash.
        public var timeout: Duration
    }

    static let start: UInt8 = 0xD0, chunk: UInt8 = 0xD1, end: UInt8 = 0xD2, finish: UInt8 = 0xD3
    static let chunkSize = 26

    /// Every packet for uploading `frames`, in order. `period` is the time per frame in 100 ms
    /// units (Space Station sends 0 when restoring the stock animation).
    public static func uploadPackets(frames: [[UInt8]], period: Int) -> [Packet] {
        let count = frames.count
        let sizeHigh = UInt8(frameSize >> 8), sizeLow = UInt8(frameSize & 0xFF)
        func padded(_ b: [UInt8], to n: Int) -> [UInt8] { b + [UInt8](repeating: 0, count: n - b.count) }
        var packets: [Packet] = []
        for (j, frame) in frames.enumerated() {
            // Picture id 1; type 1 for an animation, 0 for a still; frames counted from 1.
            var s: [UInt8] = [0xA5, start, 9, 1, count > 1 ? 1 : 0, UInt8(count), UInt8(j + 1),
                              UInt8(clamping: period), sizeHigh, sizeLow]
            s.append(sum(s[1...]))
            packets.append(Packet(bytes: padded(s, to: 15), command: start, timeout: .milliseconds(500)))
            for offset in stride(from: 0, to: frameSize, by: chunkSize) {
                let piece = Array(frame[offset..<min(offset + chunkSize, frameSize)])
                var c: [UInt8] = [0xA5, chunk, UInt8(offset >> 8), UInt8(offset & 0xFF)] + padded(piece, to: chunkSize)
                c.append(sum(c[1...]))
                packets.append(Packet(bytes: c, command: chunk, offset: offset, timeout: .seconds(1)))
            }
            var e: [UInt8] = [0xA5, end, 7, 1, UInt8(j + 1), sizeHigh, sizeLow, 0]
            e.append(sum(e[1...]))
            packets.append(Packet(bytes: padded(e, to: 15), command: end, timeout: .seconds(30)))
        }
        var f: [UInt8] = [0xA5, finish, 7, 1, UInt8(count), sizeHigh, sizeLow, 0]
        f.append(sum(f[1...]))
        packets.append(Packet(bytes: padded(f, to: 15), command: finish, timeout: .milliseconds(500)))
        return packets
    }

    /// Whether `reply` (an input report from the Xbox interface) acknowledges `packet`: `5A A5`
    /// at 14, the command at 16, status 0 at 18, and for chunks the offset at 19-20. The firmware
    /// answers the finish with an end reply.
    public static func acknowledges(_ reply: [UInt8], _ packet: Packet) -> Bool {
        guard isReply(reply), reply[18] == 0 else { return false }
        let command = reply[16]
        guard command == packet.command || (packet.command == finish && command == end) else { return false }
        guard let offset = packet.offset else { return true }
        return reply[19] == UInt8(offset >> 8) && reply[20] == UInt8(offset & 0xFF)
    }

    /// A screen reply rather than a gamepad report.
    public static func isReply(_ r: [UInt8]) -> Bool {
        r.count > 20 && r[14] == 0x5A && r[15] == 0xA5 && !(r[0] == 0x00 && r[1] == 0x14)
    }

    private static func sum(_ bytes: some Sequence<UInt8>) -> UInt8 { bytes.reduce(0, &+) }
}
