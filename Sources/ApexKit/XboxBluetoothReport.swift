import Foundation

/// The Apex 5 in PC Bluetooth mode. It presents itself as an Xbox Wireless Controller with the
/// original Bluetooth firmware (045E:02E0) and nothing else: there is no vendor interface, so over
/// Bluetooth the controller can't be configured and paddles and gyro aren't reported. Paddles
/// arrive as whatever Xbox button they're mapped to.
public enum XboxBluetoothReport {
    public static let vendorID = 0x045E
    public static let productID = 0x02E0

    /// The ten buttons of report 1, in bit order.
    private static let buttonOrder: [GamepadButtons] = [
        .a, .b, .x, .y, .leftBumper, .rightBumper, .back, .start, .leftStick, .rightStick,
    ]
    private static let hatDirections: [GamepadButtons] = [
        .dpadUp, [.dpadUp, .dpadRight], .dpadRight, [.dpadDown, .dpadRight],
        .dpadDown, [.dpadDown, .dpadLeft], .dpadLeft, [.dpadUp, .dpadLeft],
    ]

    /// Applies one input report to `state` and returns whether it carried input.
    ///
    /// Report 1 (16 bytes with the ID): X Y Rx Ry (u16, centre 0x8000, down positive) | LT RT
    /// (10 bit) | hat (1-8 clockwise from up, 0 = centred) | buttons. Report 2 is the Xbox button
    /// on its own, so the rest of the state has to carry over.
    public static func apply(_ r: [UInt8], to state: inout GamepadState) -> Bool {
        switch r.first {
        case 1 where r.count >= 16:
            state.leftStick = StickPosition(x: axis(r, 1), y: flip(axis(r, 3)))
            state.rightStick = StickPosition(x: axis(r, 5), y: flip(axis(r, 7)))
            state.leftTrigger = trigger(r, 9)
            state.rightTrigger = trigger(r, 11)
            let guide = state.buttons.intersection(.guide)
            state.buttons = guide
            if (1...8).contains(r[13]) { state.buttons.formUnion(hatDirections[Int(r[13]) - 1]) }
            let bits = UInt16(r[14]) | UInt16(r[15]) << 8
            for (i, b) in buttonOrder.enumerated() where bits & (1 << i) != 0 { state.buttons.insert(b) }
            return true
        case 2 where r.count >= 2:
            if r[1] & 1 != 0 { state.buttons.insert(.guide) } else { state.buttons.remove(.guide) }
            return true
        default:
            return false
        }
    }

    /// Battery level in percent from report 4, which the controller sends now and then on its own.
    public static func battery(_ r: [UInt8]) -> Int? {
        guard r.count >= 2, r[0] == 4 else { return nil }
        return (Int(r[1]) * 100 + 127) / 255
    }

    /// Output report 3 (with the ID first): runs both motors at `strong` and `weak` percent
    /// (0-100) for `duration`, up to 2.5 s.
    public static func rumble(strong: UInt8, weak: UInt8, duration: Duration) -> [UInt8] {
        let ticks = min(255, max(0, Int(duration / .milliseconds(10))))
        return [3, 0x03, 0, 0, min(strong, 100), min(weak, 100), UInt8(ticks), 0, 0]
    }

    private static func axis(_ r: [UInt8], _ i: Int) -> Int16 {
        Int16(truncatingIfNeeded: Int(UInt16(r[i]) | UInt16(r[i + 1]) << 8) - 32768)
    }
    // Xbox HID is down-positive; GamepadState is up-positive. Int16.min has no positive twin.
    private static func flip(_ v: Int16) -> Int16 { v == .min ? .max : -v }
    private static func trigger(_ r: [UInt8], _ i: Int) -> UInt8 {
        UInt8((min(1023, Int(UInt16(r[i]) | UInt16(r[i + 1]) << 8)) * 255 + 511) / 1023)
    }
}
