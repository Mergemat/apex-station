import Foundation

/// A profile's lighting record (format 3.0): a 20-byte header (version, click feedback, loop
/// start/end, cycle time, brightness, LEDs per frame, mode, grip sync, reserved) followed by
/// animation frames of `ledCount` RGB triples. The Apex 5 has 12 LEDs and 10 frames (380 bytes).
public struct Lighting: Sendable, Equatable {
    public enum Mode: UInt8, Sendable, CaseIterable {
        case flow = 1, breathing = 2, gradient = 3, feedback = 4, steady = 5, off = 6, standard = 7
    }

    public struct Color: Sendable, Equatable, Hashable {
        public var r: UInt8, g: UInt8, b: UInt8
        public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }
    }

    public let slot: Int
    public private(set) var bytes: [UInt8]

    public init?(slot: Int, bytes: [UInt8]) {
        guard bytes.count > 20, bytes[1] == 3, bytes[7] > 0 else { return nil }
        self.slot = slot
        self.bytes = bytes
    }

    public var mode: Mode { Mode(rawValue: bytes[8]) ?? .standard }
    /// 0-100.
    public var brightness: Int { Int(bytes[6]) }
    /// Cycle time of animated modes.
    public var speed: Int { Int(bytes[5]) }
    public var ledCount: Int { Int(bytes[7]) }
    public var frameCount: Int { (bytes.count - 20) / (ledCount * 3) }
    /// The colour of the first LED in the first frame: what steady and breathing show.
    public var color: Color { Color(r: bytes[20], g: bytes[21], b: bytes[22]) }

    public mutating func setBrightness(_ v: Int) { bytes[6] = UInt8(clamping: max(0, min(100, v))) }
    public mutating func setSpeed(_ v: Int) { bytes[5] = UInt8(clamping: max(1, min(100, v))) }

    /// One colour on every LED, still or breathing.
    public mutating func setColor(_ c: Color, mode: Mode) {
        bytes[8] = mode.rawValue
        bytes[3] = 0
        bytes[4] = 0
        for i in stride(from: 20, to: bytes.count - 2, by: 3) {
            bytes[i] = c.r
            bytes[i + 1] = c.g
            bytes[i + 2] = c.b
        }
    }

    public mutating func setOff() { bytes[8] = Mode.off.rawValue }

    /// Back to Flydigi's own animation, using the frames recorded from a factory profile.
    public mutating func setStandard(frames: [UInt8], loopEnd: UInt8) {
        bytes[8] = Mode.standard.rawValue
        bytes[3] = 0
        bytes[4] = loopEnd
        let n = min(frames.count, bytes.count - 20)
        bytes.replaceSubrange(20..<(20 + n), with: frames.prefix(n))
    }
}

extension Flydigi {
    /// Requests the lighting record of profile `slot`; the controller answers with `A7` chunks.
    public static func readLighting(_ slot: Int) -> Data { frame(.readLighting, [UInt8(slot), ProfileAssembler.chunkSize]) }

    public static func writeLighting(from old: Lighting, to new: Lighting) -> [Data] {
        precondition(old.slot == new.slot)
        return writeRecord(slot: new.slot, old: old.bytes, new: new.bytes, start: .writeLightingStart, chunk: .writeLightingChunk)
    }
}
