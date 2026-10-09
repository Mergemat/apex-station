import Foundation

/// Buttons as Flydigi numbers them in profiles and remapping.
public enum FlydigiKey: UInt8, Sendable, CaseIterable, Hashable {
    case up = 0, right = 1, down = 2, left = 3
    case a = 4, b = 5, view = 6, x = 7, y = 8, menu = 9
    case lb = 10, rb = 11, lt = 12, rt = 13, l3 = 14, r3 = 15
    case c = 16, z = 17
    case m1 = 18, m2 = 19, m3 = 20, m4 = 21, lm = 22, rm = 23
    case fn = 24, turbo = 25, home = 27

    public var name: String {
        switch self {
        case .up: "D-pad up"
        case .right: "D-pad right"
        case .down: "D-pad down"
        case .left: "D-pad left"
        case .a: "A"
        case .b: "B"
        case .view: "View"
        case .x: "X"
        case .y: "Y"
        case .menu: "Menu"
        case .lb: "LB"
        case .rb: "RB"
        case .lt: "LT"
        case .rt: "RT"
        case .l3: "L3"
        case .r3: "R3"
        case .c: "C"
        case .z: "Z"
        case .m1: "M1"
        case .m2: "M2"
        case .m3: "M3"
        case .m4: "M4"
        case .lm: "LM"
        case .rm: "RM"
        case .fn: "Fn"
        case .turbo: "Turbo"
        case .home: "Home"
        }
    }

    /// The Apex 5's buttons, in the order the app lists them.
    public static let apex5: [FlydigiKey] = [
        .a, .b, .x, .y, .up, .down, .left, .right, .lb, .rb, .lt, .rt, .l3, .r3, .view, .menu, .home,
        .m1, .m2, .m3, .m4, .lm, .rm,
    ]
}

/// What a button does in a profile.
public enum KeyMapping: Sendable, Equatable {
    /// Its own function.
    case standard
    /// Acts as another button.
    case button(FlydigiKey)
    case macro
    case keyboardOrMouse
    /// A target the app doesn't know (raw value kept so writing it back is lossless).
    case unknown(UInt8)
}

public enum TurboMode: UInt8, Sendable, Equatable {
    case off = 0, hold = 1, toggle = 2
}

/// One of the controller's four on-board profiles: an 840-byte record (format 3.1).
///
/// Layout (from Space Station's parser): 0-1 format version, 2 package count, 3-12 legacy LED,
/// 13-108 buttons (32 × 3 bytes), 109-122 sticks, 123-136 triggers, 137-144 gyro,
/// 145-153 vibration, 154-182 trigger motors, 185-224 adaptive triggers, 225-226 data version,
/// 230-767 macros, 770-789 name (UTF-16LE), 790-839 format 3.1 extras.
public struct Profile: Sendable, Equatable {
    public let slot: Int
    public private(set) var bytes: [UInt8]

    public static let size = 840
    static let keysOffset = 13

    public init?(slot: Int, bytes: [UInt8]) {
        guard bytes.count >= Self.size, bytes[1] == 3 else { return nil }
        self.slot = slot
        self.bytes = bytes
    }

    public var formatVersion: String { "\(bytes[1]).\(bytes[0])" }

    public var name: String {
        let raw = Data(bytes[770..<790])
        let s = String(data: raw, encoding: .utf16LittleEndian) ?? ""
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}\u{FFFF}"))
    }

    public func mapping(for key: FlydigiKey) -> KeyMapping {
        let target = bytes[Self.keysOffset + Int(key.rawValue) * 3]
        switch target {
        case 0xFF: return .standard
        case 32: return .macro
        case 254: return .keyboardOrMouse
        default:
            guard let k = FlydigiKey(rawValue: target) else { return .unknown(target) }
            return k == key ? .standard : .button(k)
        }
    }

    public func turbo(for key: FlydigiKey) -> (mode: TurboMode, speed: UInt8)? {
        let i = Self.keysOffset + Int(key.rawValue) * 3
        guard bytes[i + 2] > 0 else { return nil }
        return (TurboMode(rawValue: bytes[i + 1]) ?? .off, bytes[i + 2])
    }

    /// Makes `key` act as `mapping`, encoded the way Space Station writes it.
    public mutating func setMapping(_ mapping: KeyMapping, for key: FlydigiKey) {
        let i = Self.keysOffset + Int(key.rawValue) * 3
        let target: UInt8 = switch mapping {
        case .standard: 0xFF
        case .button(let k): k == key ? 0xFF : k.rawValue
        case .macro: 32
        case .keyboardOrMouse: 254
        case .unknown(let raw): raw
        }
        bytes[i] = target
        // A plain remap clears turbo; turbo is set separately.
        bytes[i + 1] = 0
        bytes[i + 2] = 0
    }

    /// Turbo for `key`: nil turns it off. Speed is the presses per second the controller fires.
    public mutating func setTurbo(_ turbo: (mode: TurboMode, speed: UInt8)?, for key: FlydigiKey) {
        let i = Self.keysOffset + Int(key.rawValue) * 3
        guard let turbo, turbo.mode != .off, turbo.speed > 0 else {
            bytes[i + 1] = 0
            bytes[i + 2] = 0
            return
        }
        // A turbo entry always names a target; keep the current one, or the key itself.
        if bytes[i] == 0xFF { bytes[i] = key.rawValue }
        bytes[i + 1] = turbo.mode.rawValue
        bytes[i + 2] = turbo.speed
    }

    /// Buttons that do something other than their own function.
    public var remapped: [(key: FlydigiKey, mapping: KeyMapping)] {
        FlydigiKey.allCases.compactMap { k in
            let m = mapping(for: k)
            return m == .standard ? nil : (k, m)
        }
    }
}

/// Reassembles a profile from the controller's numbered `A3` reply chunks.
public struct ProfileAssembler: Sendable {
    public static let chunkSize: UInt8 = 20
    private var chunks: [Int: [UInt8]] = [:]
    private var total = 0

    public init() {}

    /// Feeds one reply; returns the slot and full record once every chunk has arrived.
    public mutating func add(_ reply: some RandomAccessCollection<UInt8>) -> (slot: Int, bytes: [UInt8])? {
        let f = Flydigi.strip(reply)
        guard f.count >= 6 + Int(Self.chunkSize), Flydigi.command(of: f) == Flydigi.Command.readProfile.rawValue else { return nil }
        total = Int(f[3])
        chunks[Int(f[4])] = Array(f[6..<(6 + Int(Self.chunkSize))])
        guard total > 0, chunks.count == total else { return nil }
        let bytes = (0..<total).flatMap { chunks[$0] ?? [] }
        return (Int(f[5]), bytes)
    }
}

extension Flydigi {
    /// Asks which profile is active and for each profile's version id (`FFFF` = factory default).
    public static func readProfileVersions() -> Data { frame(.readProfileVersions) }

    /// Makes `slot` (0-3) the active profile, like the controller's own Fast Swap.
    public static func applyProfile(_ slot: Int) -> Data { frame(.applyProfile, [UInt8(slot)]) }

    /// Requests profile `slot` (0-3); the controller answers with numbered `A3` chunks.
    public static func readProfile(_ slot: Int) -> Data { frame(.readProfile, [UInt8(slot), ProfileAssembler.chunkSize]) }

    /// The frames that turn profile `old` into `new` on the controller: for each run of changed
    /// 20-byte chunks, a start frame (`A4`: slot, first chunk, chunk count, chunk size) followed by
    /// the chunks themselves (`A5`: index within the run, 20 bytes). Unchanged chunks aren't sent,
    /// like Space Station does.
    public static func writeProfile(from old: Profile, to new: Profile) -> [Data] {
        precondition(old.slot == new.slot)
        let size = Int(ProfileAssembler.chunkSize)
        let count = Profile.size / size
        let chunk = { (p: Profile, i: Int) in Array(p.bytes[(i * size)..<((i + 1) * size)]) }
        var frames: [Data] = []
        var i = 0
        while i < count {
            guard chunk(old, i) != chunk(new, i) else { i += 1; continue }
            var run: [[UInt8]] = []
            let start = i
            while i < count, chunk(old, i) != chunk(new, i) {
                run.append(chunk(new, i))
                i += 1
            }
            frames.append(frame(.writeProfileStart, [UInt8(new.slot), UInt8(start), UInt8(run.count), ProfileAssembler.chunkSize]))
            for (n, data) in run.enumerated() { frames.append(frame(.writeProfileChunk, [UInt8(n)] + data)) }
        }
        return frames
    }

    /// The active profile slot from a `readProfileVersions` reply.
    public static func activeProfile(_ reply: some RandomAccessCollection<UInt8>) -> Int? {
        let b = strip(reply)
        guard b.count > 5, command(of: b) == Command.readProfileVersions.rawValue else { return nil }
        let raw = Int(b[5])
        return raw <= 7 ? raw % 4 : 0
    }
}
