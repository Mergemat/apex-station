import Foundation

/// A macro stored on the controller: pressing `key` plays back `steps`.
public struct Macro: Sendable, Equatable {
    public enum Mode: UInt8, Sendable, CaseIterable { case once = 1, whileHeld = 2, toggle = 3 }

    public struct Step: Sendable, Equatable {
        public var key: FlydigiKey
        public var press: Bool
        /// Milliseconds from the start of the macro.
        public var time: Int
        public init(key: FlydigiKey, press: Bool, time: Int) {
            self.key = key
            self.press = press
            self.time = time
        }
    }

    public var key: FlydigiKey
    public var mode: Mode
    public var steps: [Step]

    public init(key: FlydigiKey, mode: Mode, steps: [Step]) {
        self.key = key
        self.mode = mode
        self.steps = steps
    }
}

extension Profile {
    // Format 3.1 keeps macros in bytes 230-767: a count, an offset table of `maxMacros` entries
    // (in 4-byte units), then per macro a 4-byte header (trigger key, action count LE, mode) and
    // 4-byte actions (time since start in 10 ms units LE, key, 1 press / 0 release).
    static let macroOffset = 230
    static let macroSize = 538
    public static let maxMacros = 5
    public static let maxMacroSteps = 128
    static let macroTick = 10

    public var macros: [Macro] {
        let d = Array(bytes[Self.macroOffset..<(Self.macroOffset + Self.macroSize)])
        let count = Int(d[0])
        guard (1...Self.maxMacros).contains(count) else { return [] }
        let base = Self.maxMacros + 1
        var result: [Macro] = []
        for i in 0..<count {
            let start = base + Int(d[i + 1]) * 4
            guard start + 4 <= d.count, let key = FlydigiKey(rawValue: d[start]) else { continue }
            let actions = Int(d[start + 1]) | Int(d[start + 2]) << 8
            let mode = Macro.Mode(rawValue: d[start + 3]) ?? .once
            var steps: [Macro.Step] = []
            for j in 0..<actions {
                let o = start + 4 + j * 4
                guard o + 3 < d.count, let k = FlydigiKey(rawValue: d[o + 2]) else { break }
                steps.append(.init(key: k, press: d[o + 3] == 1, time: (Int(d[o]) | Int(d[o + 1]) << 8) * Self.macroTick))
            }
            result.append(Macro(key: key, mode: mode, steps: steps))
        }
        return result
    }

    /// Replaces the profile's macros and points each macro's button at it.
    public mutating func setMacros(_ macros: [Macro]) {
        let kept = Array(macros.prefix(Self.maxMacros)).map { m in
            Macro(key: m.key, mode: m.mode, steps: Array(m.steps.prefix(Self.maxMacroSteps)))
        }
        // Buttons that ran a macro which is gone go back to their own function.
        for old in self.macros where !kept.contains(where: { $0.key == old.key }) && mapping(for: old.key) == .macro {
            setMapping(.standard, for: old.key)
        }
        var d = [UInt8](repeating: 0, count: Self.maxMacros + 1)
        d[0] = UInt8(kept.count)
        var offset = 0
        for (i, m) in kept.enumerated() where i < kept.count - 1 {
            offset += m.steps.count + 1
            d[i + 2] = UInt8(offset)
        }
        for m in kept {
            d += [m.key.rawValue, UInt8(m.steps.count & 0xFF), UInt8(m.steps.count >> 8), m.mode.rawValue]
            for s in m.steps.sorted(by: { $0.time < $1.time }) {
                let t = max(0, s.time) / Self.macroTick
                d += [UInt8(t & 0xFF), UInt8((t >> 8) & 0xFF), s.key.rawValue, s.press ? 1 : 0]
            }
            setMapping(.macro, for: m.key)
        }
        d = Array(d.prefix(Self.macroSize))
        d += [UInt8](repeating: 0xFF, count: Self.macroSize - d.count)
        bytes.replaceSubrange(Self.macroOffset..<(Self.macroOffset + Self.macroSize), with: d)
    }
}

extension FlydigiKey {
    /// Buttons a macro can press: the ones a game sees.
    public static let macroTargets: [FlydigiKey] = [
        .a, .b, .x, .y, .lb, .rb, .lt, .rt, .up, .down, .left, .right, .l3, .r3, .view, .menu,
    ]

    /// The live-input bit for this key; triggers are read from their analog value instead.
    var liveButton: GamepadButtons? {
        switch self {
        case .a: .a
        case .b: .b
        case .x: .x
        case .y: .y
        case .lb: .leftBumper
        case .rb: .rightBumper
        case .up: .dpadUp
        case .down: .dpadDown
        case .left: .dpadLeft
        case .right: .dpadRight
        case .l3: .leftStick
        case .r3: .rightStick
        case .view: .back
        case .menu: .start
        default: nil
        }
    }
}

/// Turns live controller input into macro steps: every press and release of a button a macro can
/// send, timed from the first press.
public struct MacroRecorder: Sendable {
    public private(set) var steps: [Macro.Step] = []
    private var held: Set<FlydigiKey> = []
    private var startedAt: Int?

    public init() {}

    public var isFull: Bool { steps.count >= Profile.maxMacroSteps }

    /// Feeds one input sample taken `ms` milliseconds into the recording.
    public mutating func add(_ state: GamepadState, at ms: Int) {
        var down: Set<FlydigiKey> = []
        for key in FlydigiKey.macroTargets {
            let pressed = switch key {
            case .lt: state.leftTrigger >= 128
            case .rt: state.rightTrigger >= 128
            default: key.liveButton.map { state.buttons.contains($0) } ?? false
            }
            if pressed { down.insert(key) }
        }
        for key in FlydigiKey.macroTargets where down.contains(key) != held.contains(key) {
            guard !isFull else { return }
            let start = startedAt ?? ms
            startedAt = start
            steps.append(.init(key: key, press: down.contains(key), time: ms - start))
            if down.contains(key) { held.insert(key) } else { held.remove(key) }
        }
    }

    /// Ends the recording, releasing anything still held so the macro never leaves a button down.
    public mutating func finish(at ms: Int) -> [Macro.Step] {
        for key in FlydigiKey.macroTargets where held.contains(key) {
            steps.append(.init(key: key, press: false, time: ms - (startedAt ?? ms)))
        }
        held = []
        return steps
    }
}
