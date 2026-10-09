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

/// How a stick responds, as stored in a profile.
public struct StickConfig: Sendable, Equatable {
    public enum Curve: UInt8, Sendable, CaseIterable { case standard = 0, quick = 1, slow = 2, custom = 3 }

    public var curve: Curve
    /// Centre dead zone, 0-127 (fraction of full deflection × 127).
    public var deadZone: Int
    /// Where full output is reached, 0-127; lower values reach full output sooner.
    public var edge: Int
    /// Circle limits diagonals to the circle; rectangle (the default) lets them reach the corners.
    public var circular: Bool

    public init(curve: Curve, deadZone: Int, edge: Int, circular: Bool) {
        self.curve = curve
        self.deadZone = deadZone
        self.edge = edge
        self.circular = circular
    }
}

/// A trigger's force-feedback effect ("ForceAdapt"). Values are 0-255 unless noted.
public enum TriggerEffect: Sendable, Equatable {
    case normal
    /// Resistance from `start` onwards, like a pedal.
    case racing(start: Int, damping: Int)
    /// A rapid buzz past `start`, like an automatic weapon.
    case recoil(start: Int, startForce: Int, strength: Int, frequency: Int)
    /// A click-through break point at `start`, like a heavy trigger.
    case sniper(start: Int, stroke: Int, resistance: Int)
    /// Stops the trigger at `position` (20-200).
    case lock(position: Int)
    /// Vibrates with the game's rumble once past `start`.
    case vibration(threshold: Int, scale: Int, start: Int, frequency: Int)

    /// Defaults the controller's own menu writes for each mode.
    public static let racingDefault = TriggerEffect.racing(start: 0, damping: 30)
    public static let recoilDefault = TriggerEffect.recoil(start: 0, startForce: 1, strength: 50, frequency: 15)
    public static let sniperDefault = TriggerEffect.sniper(start: 50, stroke: 30, resistance: 1)
    public static let lockDefault = TriggerEffect.lock(position: 80)
    public static let vibrationDefault = TriggerEffect.vibration(threshold: 10, scale: 50, start: 1, frequency: 90)
}

/// A trigger's travel range and effect, as stored in a profile.
public struct TriggerConfig: Sendable, Equatable {
    /// Travel (0-255) where the trigger starts and finishes reporting.
    public var start: Int
    public var end: Int
    public var effect: TriggerEffect

    public init(start: Int, end: Int, effect: TriggerEffect) {
        self.start = start
        self.end = end
        self.effect = effect
    }
}

/// Grip rumble, as stored in a profile.
public struct VibrationConfig: Sendable, Equatable {
    public var enabled: Bool
    /// Motor strength, 0-100.
    public var left: Int
    public var right: Int
    public init(enabled: Bool, left: Int, right: Int) {
        self.enabled = enabled
        self.left = left
        self.right = right
    }
}

/// Gyro aiming, as stored in a profile.
public struct GyroConfig: Sendable, Equatable {
    public enum Target: UInt8, Sendable, CaseIterable { case off = 0, leftStick = 1, rightStick = 2, mouse = 3 }
    public enum Activation: UInt8, Sendable, CaseIterable { case toggle = 0, hold = 1 }

    public var target: Target
    /// The button that turns gyro on; nil = always on.
    public var key: FlydigiKey?
    public var activation: Activation
    public var deadZone: Int
    /// 1-100.
    public var sensitivity: Int
    /// Racing tilt instead of shooter aiming.
    public var racing: Bool

    public init(target: Target, key: FlydigiKey?, activation: Activation, deadZone: Int, sensitivity: Int, racing: Bool) {
        self.target = target
        self.key = key
        self.activation = activation
        self.deadZone = deadZone
        self.sensitivity = sensitivity
        self.racing = racing
    }
}

/// One of the controller's four on-board profiles: an 840-byte record (format 3.1).
///
/// Layout (from Space Station's parser): 0-1 format version, 2 package count, 3-12 legacy LED,
/// 13-108 buttons (32 × 3 bytes), 109-122 sticks, 123-136 triggers, 137-144 gyro,
/// 145-153 vibration, 154-182 trigger motors, 185-224 adaptive triggers, 225-226 data version,
/// 230-767 macros, 770-789 name (UTF-16LE), 790-839 format 3.1 extras.
public struct Profile: Sendable, Equatable {
    public let slot: Int
    public internal(set) var bytes: [UInt8]

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

    // Sticks: 7 bytes each at 109 (curve type, dead zone, curve point 1 x/y, point 2 x/y, edge) and,
    // in format 3.1, 12 bytes each at 790 (curve type, 9 custom-curve points, circularity, extra edge).
    private static func stickBase(_ left: Bool) -> Int { 109 + (left ? 0 : 7) }
    private static func stickExtra(_ left: Bool) -> Int { 790 + (left ? 0 : 12) }

    /// Values above 127 are stored as negatives (127 - value), as Space Station reads them.
    private static func signed(_ b: UInt8) -> Int { b > 127 ? 127 - Int(b) : Int(b) }

    public func stick(left: Bool) -> StickConfig {
        let base = Self.stickBase(left), extra = Self.stickExtra(left)
        return StickConfig(
            curve: StickConfig.Curve(rawValue: bytes[base]) ?? .standard,
            deadZone: Self.signed(bytes[base + 1]),
            edge: Self.signed(bytes[base + 6]),
            circular: bytes[extra + 10] == 1)
    }

    public mutating func setStick(_ c: StickConfig, left: Bool) {
        let base = Self.stickBase(left), extra = Self.stickExtra(left)
        // Space Station keeps the curve type in both places.
        bytes[base] = c.curve.rawValue
        bytes[extra] = c.curve.rawValue
        bytes[base + 1] = UInt8(clamping: max(0, min(127, c.deadZone)))
        bytes[base + 6] = UInt8(clamping: max(0, min(127, c.edge)))
        bytes[extra + 10] = c.circular ? 1 : 0
    }

    // Triggers: 7 bytes each at 123 (kind 0 normal / 1 ForceAdapt / 2 vibration, start, curve
    // points, end) and a 20-byte ForceAdapt block each at 185 (type, bind type/filter/scale,
    // 5 bind params, mixed border, 10 params). Layout and presets from the Apex 4 port's notes,
    // recorded from the controller's own trigger menu.
    private static func triggerBase(_ left: Bool) -> Int { 123 + (left ? 0 : 7) }
    private static func triggerBlock(_ left: Bool) -> Int { 185 + (left ? 0 : 20) }

    public func trigger(left: Bool) -> TriggerConfig {
        let base = Self.triggerBase(left), blk = Self.triggerBlock(left)
        let p = { Int(bytes[blk + 10 + $0]) }
        let effect: TriggerEffect = switch bytes[blk] {
        case 1: .racing(start: p(0), damping: p(1))
        case 2: .recoil(start: p(0), startForce: p(1), strength: p(2), frequency: p(3))
        case 3: .sniper(start: p(0), stroke: p(1), resistance: p(2))
        case 4: .lock(position: p(0))
        case 5: .vibration(threshold: Int(bytes[blk + 2]), scale: Int(bytes[blk + 3]), start: p(0), frequency: p(3))
        default: .normal
        }
        return TriggerConfig(start: Int(bytes[base + 1]), end: Int(bytes[base + 6]), effect: effect)
    }

    public mutating func setTrigger(_ t: TriggerConfig, left: Bool) {
        let base = Self.triggerBase(left), blk = Self.triggerBlock(left)
        let b = { (v: Int) in UInt8(clamping: max(0, min(255, v))) }
        bytes[base + 1] = b(t.start)
        bytes[base + 6] = b(t.end)
        // Block bytes 0-9 per mode, then params; unused params stay 0xFF like the controller writes.
        var header: [UInt8], params: [UInt8], kind: UInt8 = 1
        switch t.effect {
        case .normal:
            header = [0, 0, 0x0A, 0x32, 0x64, 1, 0xFF, 0x46, 0, 0xFF]; params = [0, 0, 0, 0, 0]; kind = 0
        case let .racing(start, damping):
            header = [1, 0, 0x0A, 0x32, 0x64, 1, 0xFF, 0x46, 0, 0xFF]
            // "Output from the start position" only makes sense once there's travel before it.
            params = [b(start), b(max(1, damping)), start > 0 ? 1 : 0, 0, 0]
        case let .recoil(start, startForce, strength, frequency):
            header = [2, 0, 0x0A, 0x32, 0x64, 1, 0xFF, 0x46, 0, 0xFF]
            params = [b(start), b(max(1, startForce)), b(max(1, strength)), b(max(1, frequency)), 1]
        case let .sniper(start, stroke, resistance):
            header = [3, 0, 0x0A, 0x0A, 0x64, 1, 0xFF, 0x46, 0, 0xFF]
            params = [b(start), b(max(1, stroke)), b(max(1, resistance)), 0, 1]
        case let .lock(position):
            header = [4, 0, 0x0A, 0x0A, 0x64, 1, 0xFF, 0x46, 0, 0xFF]
            params = [b(max(20, min(200, position))), 0xFA, 1, 0, 0]
        case let .vibration(threshold, scale, start, frequency):
            // Synced with grip rumble: bind type 2, filter = threshold, then `start 1 1 frequency 0`.
            header = [5, 2, b(threshold), b(scale), b(max(1, start)), 1, 1, b(max(1, frequency)), 0, 0xFF]
            params = [b(max(1, start)), 1, 1, b(max(1, frequency)), 0]
            kind = 2
        }
        bytes[base] = kind
        bytes.replaceSubrange(blk..<(blk + 20), with: header + params + [UInt8](repeating: 0xFF, count: 5))
    }

    // Vibration: 9 bytes at 145 (master 0 = on; per motor: 0 = on, min, max, strength).
    public var vibration: VibrationConfig {
        VibrationConfig(enabled: bytes[145] == 0, left: Int(bytes[149]), right: Int(bytes[153]))
    }

    public mutating func setVibration(_ v: VibrationConfig) {
        bytes[145] = v.enabled ? 0 : 0xFF
        bytes[146] = v.enabled ? 0 : 0xFF
        bytes[150] = v.enabled ? 0 : 0xFF
        bytes[149] = UInt8(clamping: max(0, min(100, v.left)))
        bytes[153] = UInt8(clamping: max(0, min(100, v.right)))
    }

    // Gyro: 8 bytes at 137 (target, activation key, activation type, dead zone, sensitivity ×2,
    // use mode, second key).
    public var gyro: GyroConfig {
        GyroConfig(
            target: GyroConfig.Target(rawValue: bytes[137]) ?? .off,
            key: bytes[138] == 0xFF ? nil : FlydigiKey(rawValue: bytes[138]),
            activation: GyroConfig.Activation(rawValue: bytes[139]) ?? .toggle,
            deadZone: Int(bytes[140]),
            sensitivity: Int(max(bytes[141], bytes[142])),
            racing: bytes[143] == 1)
    }

    public mutating func setGyro(_ g: GyroConfig) {
        bytes[137] = g.target.rawValue
        bytes[139] = g.activation.rawValue
        bytes[141] = UInt8(clamping: max(1, min(100, g.sensitivity)))
        bytes[142] = bytes[141]
        bytes[143] = g.racing ? 1 : 0
        if g.target == .mouse {
            // Space Station's encoding for mouse mode.
            bytes[138] = 0xFF
            bytes[140] = 0
            bytes[144] = 0xFF
        } else {
            bytes[138] = g.key?.rawValue ?? 0xFF
            bytes[140] = UInt8(clamping: max(0, min(100, g.deadZone)))
        }
    }

    /// The profile's name (up to 10 characters).
    public mutating func setName(_ name: String) {
        var data = [UInt8](String(name.prefix(10)).data(using: .utf16LittleEndian) ?? Data())
        data = Array(data.prefix(20))
        bytes.replaceSubrange(770..<790, with: data + [UInt8](repeating: 0, count: 20 - data.count))
    }

    /// Buttons that do something other than their own function.
    public var remapped: [(key: FlydigiKey, mapping: KeyMapping)] {
        FlydigiKey.allCases.compactMap { k in
            let m = mapping(for: k)
            return m == .standard ? nil : (k, m)
        }
    }
}

/// Reassembles a record (profile or lighting) from the controller's numbered reply chunks.
public struct ProfileAssembler: Sendable {
    public static let chunkSize: UInt8 = 20
    private let command: UInt8
    private var chunks: [Int: [UInt8]] = [:]
    private var total = 0

    /// `command` is the read command whose replies carry the chunks (`A3` profile, `A7` lighting).
    public init(command: Flydigi.Command = .readProfile) { self.command = command.rawValue }

    /// Feeds one reply; returns the slot and full record once every chunk has arrived.
    public mutating func add(_ reply: some RandomAccessCollection<UInt8>) -> (slot: Int, bytes: [UInt8])? {
        let f = Flydigi.strip(reply)
        guard f.count >= 6 + Int(Self.chunkSize), Flydigi.command(of: f) == command else { return nil }
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
        return writeRecord(slot: new.slot, old: old.bytes, new: new.bytes, start: .writeProfileStart, chunk: .writeProfileChunk)
    }

    /// Diff-writes any chunked record: for each run of changed 20-byte chunks, a start frame
    /// (slot, first chunk, chunk count, chunk size) and then the chunks (index within the run, data).
    static func writeRecord(slot: Int, old: [UInt8], new: [UInt8], start: Command, chunk: Command) -> [Data] {
        precondition(old.count == new.count)
        let size = Int(ProfileAssembler.chunkSize)
        let count = (new.count + size - 1) / size
        let piece = { (b: [UInt8], i: Int) -> [UInt8] in
            let lo = i * size, hi = min(b.count, lo + size)
            return Array(b[lo..<hi]) + [UInt8](repeating: 0xFF, count: size - (hi - lo))
        }
        var frames: [Data] = []
        var i = 0
        while i < count {
            guard piece(old, i) != piece(new, i) else { i += 1; continue }
            var run: [[UInt8]] = []
            let first = i
            while i < count, piece(old, i) != piece(new, i) {
                run.append(piece(new, i))
                i += 1
            }
            frames.append(frame(start, [UInt8(slot), UInt8(first), UInt8(run.count), ProfileAssembler.chunkSize]))
            for (n, data) in run.enumerated() { frames.append(frame(chunk, [UInt8(n)] + data)) }
        }
        return frames
    }

    /// Resets profile `slot` to the controller's factory default.
    public static func resetProfile(_ slot: Int) -> Data { frame(.resetProfile, [UInt8(slot)]) }

    /// The active profile slot from a `readProfileVersions` reply.
    public static func activeProfile(_ reply: some RandomAccessCollection<UInt8>) -> Int? {
        let b = strip(reply)
        guard b.count > 5, command(of: b) == Command.readProfileVersions.rawValue else { return nil }
        let raw = Int(b[5])
        return raw <= 7 ? raw % 4 : 0
    }
}
