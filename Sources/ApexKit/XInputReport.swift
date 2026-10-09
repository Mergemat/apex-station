/// The 20-byte Xbox 360 wired report the Apex 5 streams on USB interface 0:
/// `00 14 | buttons (2) | LT RT | LX LY RX RY (int16 LE) | 6 unused`.
public enum XInputReport {
    private static let buttonBits: [(UInt16, GamepadButtons)] = [
        (0x0001, .dpadUp), (0x0002, .dpadDown), (0x0004, .dpadLeft), (0x0008, .dpadRight),
        (0x0010, .start), (0x0020, .back), (0x0040, .leftStick), (0x0080, .rightStick),
        (0x0100, .leftBumper), (0x0200, .rightBumper), (0x0400, .guide),
        (0x1000, .a), (0x2000, .b), (0x4000, .x), (0x8000, .y),
    ]

    /// Returns nil for anything that is not an input report (e.g. LED status packets).
    public static func parse(_ r: some RandomAccessCollection<UInt8>) -> GamepadState? {
        let b = Array(r)
        guard b.count >= 14, b[0] == 0x00, b[1] >= 0x14 else { return nil }
        let bits = UInt16(b[2]) | UInt16(b[3]) << 8
        var s = GamepadState()
        for (mask, button) in buttonBits where bits & mask != 0 { s.buttons.insert(button) }
        s.leftTrigger = b[4]
        s.rightTrigger = b[5]
        s.leftStick = StickPosition(x: int16(b, 6), y: int16(b, 8))
        s.rightStick = StickPosition(x: int16(b, 10), y: int16(b, 12))
        return s
    }

    /// The XInput rumble packet: big (low-frequency) motor, small (high-frequency) motor.
    public static func rumble(strong: UInt8, weak: UInt8) -> [UInt8] {
        [0x00, 0x08, 0x00, strong, weak, 0x00, 0x00, 0x00]
    }
}

func int16(_ b: [UInt8], _ i: Int) -> Int16 {
    Int16(bitPattern: UInt16(b[i]) | UInt16(b[i + 1]) << 8)
}
