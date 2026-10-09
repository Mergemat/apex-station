import ApexKit
import Foundation

/// One button going down or up, for the input test.
struct InputLogLine: Identifiable, Sendable {
    let id: Int
    /// Seconds since the log started.
    let time: Double
    let name: String
    let down: Bool
    /// How long it was held, on release (ms).
    let held: Int?
    /// What the profile makes it act as, if anything.
    let actsAs: String?
}

/// Turns the timed button changes from `LiveInput` into log lines, newest first.
struct InputLog {
    private(set) var lines: [InputLogLine] = []
    private var digital: UInt32 = 0
    private var start: UInt64?
    private var downAt: [UInt32: UInt64] = [:]
    private var nextID = 0

    static let maxLines = 300

    /// Bit in `LiveInput.digital` → the key it is.
    private static let keys: [(UInt32, FlydigiKey)] = [
        (GamepadButtons.a.rawValue, .a), (GamepadButtons.b.rawValue, .b), (GamepadButtons.x.rawValue, .x), (GamepadButtons.y.rawValue, .y),
        (GamepadButtons.leftBumper.rawValue, .lb), (GamepadButtons.rightBumper.rawValue, .rb),
        (LiveInput.leftTriggerBit, .lt), (LiveInput.rightTriggerBit, .rt),
        (GamepadButtons.back.rawValue, .view), (GamepadButtons.start.rawValue, .menu), (GamepadButtons.guide.rawValue, .home),
        (GamepadButtons.leftStick.rawValue, .l3), (GamepadButtons.rightStick.rawValue, .r3),
        (GamepadButtons.dpadUp.rawValue, .up), (GamepadButtons.dpadDown.rawValue, .down),
        (GamepadButtons.dpadLeft.rawValue, .left), (GamepadButtons.dpadRight.rawValue, .right),
        (GamepadButtons.m1.rawValue, .m1), (GamepadButtons.m2.rawValue, .m2), (GamepadButtons.m3.rawValue, .m3), (GamepadButtons.m4.rawValue, .m4),
        (GamepadButtons.leftMacro.rawValue, .lm), (GamepadButtons.rightMacro.rawValue, .rm),
        (GamepadButtons.c.rawValue, .c), (GamepadButtons.z.rawValue, .z),
        (GamepadButtons.turbo.rawValue, .turbo), (GamepadButtons.fn.rawValue, .fn),
    ]

    mutating func add(_ changes: [(at: UInt64, digital: UInt32)], actsAs: (FlydigiKey) -> String?) {
        for change in changes {
            let start = self.start ?? change.at
            self.start = start
            let flipped = digital ^ change.digital
            for (bit, key) in Self.keys where flipped & bit != 0 {
                let down = change.digital & bit != 0
                var held: Int?
                if down {
                    downAt[bit] = change.at
                } else if let at = downAt.removeValue(forKey: bit) {
                    held = Int((change.at - at) / 1_000_000)
                }
                lines.insert(InputLogLine(id: nextID, time: Double(change.at - start) / 1e9, name: key.shortName,
                                          down: down, held: held, actsAs: down ? actsAs(key) : nil), at: 0)
                nextID += 1
            }
            digital = change.digital
        }
        if lines.count > Self.maxLines { lines.removeLast(lines.count - Self.maxLines) }
    }

    mutating func clear() {
        lines = []
        start = nil
        downAt = [:]
    }
}
