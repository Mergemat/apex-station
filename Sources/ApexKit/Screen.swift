import Foundation

/// The Apex 5's 160×80 screen and how Space Station uploads an animation to it.
///
/// Each frame is an LVGL binary image: a 4-byte header (true colour, 160×80) then RGB565 pixels,
/// high byte first. Space Station sends every frame as start → 58-byte chunks → end, then one
/// finish, in its older `A5 <cmd>` packets, 96 bytes for this controller. That's more than the
/// cable's settings interface carries (32 bytes) and the cable's Xbox interface doesn't take
/// commands, so uploads go through Flydigi's 2.4 GHz receiver, which Space Station addresses
/// them to. There is no frame-time field for this controller; it plays at its own speed. The
/// new animation shows after the controller restarts.
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
        /// What goes after the report ID.
        public var bytes: [UInt8]
        public var command: UInt8
        /// For chunks, the offset the controller echoes back.
        public var offset: Int?
        /// Ending a frame waits for the controller to write it to flash.
        public var timeout: Duration
    }

    static let start: UInt8 = 0xD0, chunk: UInt8 = 0xD1, end: UInt8 = 0xD2, finish: UInt8 = 0xD3
    static let chunkSize = 58

    /// Every packet for uploading `frames`, in order.
    public static func uploadPackets(frames: [[UInt8]]) -> [Packet] {
        let count = frames.count
        let sizeHigh = UInt8(frameSize >> 8), sizeLow = UInt8(frameSize & 0xFF)
        var packets: [Packet] = []
        for (j, frame) in frames.enumerated() {
            // Picture id 1; type 1 for an animation, 0 for a still; the index is sent as j + 2.
            var s: [UInt8] = [0xA5, start, 9, 1, count > 1 ? 2 : 1, UInt8(count), UInt8(j + 2), 0, sizeHigh, sizeLow]
            s.append(sum(s[1...]))
            packets.append(Packet(bytes: s + [0, 0, 0], command: start, timeout: .milliseconds(500)))
            for offset in stride(from: 0, to: frameSize, by: chunkSize) {
                var c = [UInt8](repeating: 0, count: 95)
                c[0] = 0xA5
                c[1] = chunk
                c[2] = UInt8(offset >> 8)
                c[3] = UInt8(offset & 0xFF)
                let piece = frame[offset..<min(offset + chunkSize, frameSize)]
                c.replaceSubrange(4..<(4 + piece.count), with: piece)
                c[94] = sum(c[1..<94])
                packets.append(Packet(bytes: c, command: chunk, offset: offset, timeout: .seconds(1)))
            }
            var e: [UInt8] = [0xA5, end, 7, 1, UInt8(j + 1), sizeHigh, sizeLow, 0]
            e.append(sum(e[1...]))
            packets.append(Packet(bytes: e + [0, 0, 0, 0, 0], command: end, timeout: .seconds(30)))
        }
        // The finish checksum covers fewer bytes than the others; it matches Space Station.
        var f: [UInt8] = [0xA5, finish, 7, 1, UInt8(count), sizeHigh, sizeLow, 0]
        f.append(sum(f[1..<6]))
        packets.append(Packet(bytes: f + [0, 0, 0, 0, 0], command: finish, timeout: .milliseconds(500)))
        return packets
    }

    /// Whether `reply` (without the report ID) acknowledges `packet`, by Space Station's rules: the
    /// command at byte 4 and a zero status at byte 6 (byte 7 for start), with chunk replies
    /// echoing the offset at 7-8.
    public static func acknowledges(_ reply: [UInt8], _ packet: Packet) -> Bool {
        guard reply.count > 8, reply[4] == packet.command else { return false }
        if packet.command == start { return reply[7] == 0 }
        guard reply[6] == 0 else { return false }
        guard let offset = packet.offset else { return true }
        return reply[7] == UInt8(offset >> 8) && reply[8] == UInt8(offset & 0xFF)
    }

    private static func sum(_ bytes: some Sequence<UInt8>) -> UInt8 { bytes.reduce(0, &+) }
}
