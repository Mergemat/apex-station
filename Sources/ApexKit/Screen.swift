import Foundation

/// The Apex 5's 160×80 screen and how its pictures get onto it.
///
/// Each frame is an LVGL binary image: a 4-byte header (true colour, 160×80) then RGB565 pixels,
/// high byte first. The screen has its own chip (a Freqchip part), which Space Station updates
/// the way it updates firmware: one command over the settings interface (`ScreenChip.switchCommand`)
/// makes the controller drop off USB and come back as that chip's serial port, and the frames
/// are written to its flash over that port (`ScreenChip`). When it's done the chip restarts the
/// controller with the new animation.
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
}

/// The screen chip's update protocol, from Space Station's FirmwareConsole (OtaNewUpdater). Every
/// command waits for its reply: `[result, opcode, length (2 bytes), payload]`, little-endian, with
/// result 0 for success. A custom animation goes: `start` (which returns where pictures go in
/// flash), `version`, an `erase` for every 4 KB the frames cover, a `write` for every 55 bytes, and
/// `finish` with the length and checksum. The chip checks the checksum before it restarts.
public enum ScreenChip {
    /// The chip's serial port while it's being updated.
    public static let vendorID = 0xFFAA, productID = 0x5555
    /// Switches the controller to updating its screen chip (command 0x1F, chip 4: the screen).
    public static let switchCommand = Flydigi.frame(0x1F, [4])
    public static let sectorSize = 4096
    public static let pieceSize = 55

    public enum Op: UInt8 {
        case erase = 0x03, write = 0x05, version = 0x0A, start = 0x0B, finish = 0x0C
    }

    /// Starts a custom animation. `frameTime` is per frame in 10 ms steps; Space Station sends 0
    /// when it restores Flydigi's animation, with `restoreDefault` set.
    public static func start(frames: Int, frameTime: Int, restoreDefault: Bool) -> [UInt8] {
        // Picture type: 1 for an animation, 2 for a still.
        [Op.start.rawValue, 4, 0, frames > 1 ? 1 : 2, UInt8(frames), UInt8(clamping: frameTime), restoreDefault ? 1 : 0]
    }

    public static let version: [UInt8] = [Op.version.rawValue, 6, 0]

    public static func erase(at address: UInt32) -> [UInt8] {
        [Op.erase.rawValue, 6, 0] + address.littleEndianBytes
    }

    /// One piece of up to 55 bytes. The length field says 55 even for a shorter last piece, as
    /// Space Station sends it.
    public static func write(_ piece: some Collection<UInt8>, at address: UInt32) -> [UInt8] {
        [Op.write.rawValue, 64, 0] + address.littleEndianBytes + [UInt8(pieceSize), 0] + piece
    }

    public static func finish(_ data: [UInt8]) -> [UInt8] {
        [Op.finish.rawValue, 8, 0] + UInt32(data.count).littleEndianBytes + UInt32(bitPattern: checksum(data)).littleEndianBytes
    }

    /// The next reply with opcode `op` in `buffer`, and how many bytes it used up to and including
    /// it. Replies sometimes repeat or arrive garbled, so anything that doesn't look like one is
    /// skipped. Nil until a whole reply is in.
    public static func reply(_ op: Op, in buffer: [UInt8]) -> (result: UInt8, payload: [UInt8], used: Int)? {
        var k = 0
        while k + 4 <= buffer.count {
            let length = Int(buffer[k + 2]) | Int(buffer[k + 3]) << 8
            if buffer[k + 1] == op.rawValue, length <= 16 {
                guard k + 4 + length <= buffer.count else { return nil }
                return (buffer[k], Array(buffer[(k + 4)..<(k + 4 + length)]), k + 4 + length)
            }
            k += 1
        }
        return nil
    }

    /// Flydigi's CRC (AppOtasCrcCal): the usual CRC-32 table, but shifted left and indexed by the
    /// second byte, with C#'s 32-bit signed arithmetic. It has to match theirs, quirks and all.
    public static func checksum(_ data: [UInt8]) -> Int32 {
        var crc: Int32 = 0
        for byte in data {
            let index = Int((crc / 256) ^ Int32(byte)) & 0xFF
            crc = (crc &<< 8) ^ Int32(bitPattern: table[index])
        }
        return crc
    }

    private static let table: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: self >> ($0 * 8)) } }
}
