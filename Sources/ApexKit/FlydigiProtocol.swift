import Foundation

/// Flydigi's settings protocol for the Apex 5 generation ("NewXInput", VID 0x37D7).
///
/// Transport: the vendor HID interface (usage page 0xFFA0). Commands go out as output
/// report 3, replies and the live input stream come back as input report 4, 31 bytes each.
/// Frame: `5A A5 <cmd> <len> <payload…> <sum>`, where `len` = payload + 2 and `sum` is the
/// 8-bit sum of `cmd`, `len` and the payload.
public enum Flydigi {
    public static let vendorID: UInt32 = 0x37D7
    public static let apex5ProductID: UInt32 = 0x2501
    public static let usagePage: UInt16 = 0xFFA0
    public static let commandReportID: UInt8 = 3
    public static let replyReportID: UInt8 = 4
    public static let frameSize = 31

    public enum Command: UInt8, Sendable {
        case getInfo = 0x01
        case getStatus = 0x10
        case setDataStreams = 0x11
        case rumble = 0x12
        case acquire = 0x1C
        /// Live input report, controller → host.
        case input = 0xEF
        /// Raw sensor data, controller → host.
        case rawData = 0xF7
    }

    public static func frame(_ command: Command, _ payload: [UInt8] = []) -> Data {
        frame(command.rawValue, payload)
    }

    public static func frame(_ command: UInt8, _ payload: [UInt8]) -> Data {
        precondition(payload.count <= frameSize - 5, "payload too long for one frame")
        let len = UInt8(payload.count + 2)
        var f: [UInt8] = [0x5A, 0xA5, command, len] + payload
        f.append(([command, len] + payload).reduce(0, &+))
        f += [UInt8](repeating: 0, count: frameSize - f.count)
        return Data(f)
    }

    /// The command a reply belongs to, or nil if this isn't a Flydigi frame.
    /// Accepts the frame with or without the leading report ID.
    public static func command(of reply: some RandomAccessCollection<UInt8>) -> UInt8? {
        let b = strip(reply)
        guard b.count >= 3, b[0] == 0x5A, b[1] == 0xA5 else { return nil }
        return b[2]
    }

    static func strip(_ r: some RandomAccessCollection<UInt8>) -> [UInt8] {
        let b = Array(r)
        return b.first == replyReportID && b.count > 1 && b[1] == 0x5A ? Array(b.dropFirst()) : b
    }

    /// Which data the controller should stream to the host. nil leaves a setting unchanged.
    public static func setDataStreams(
        controllerInput: Bool? = nil, rawData: Bool? = nil, keyboard: Bool? = nil,
        mouse: Bool? = nil, thirdPartyControl: Bool? = nil
    ) -> Data {
        let v = { (b: Bool?) -> UInt8 in b.map { $0 ? 1 : 0 } ?? 0xFF }
        return frame(.setDataStreams, [v(controllerInput), v(rawData), v(keyboard), v(mouse), v(thirdPartyControl)])
    }
}

extension Flydigi {
    /// Takes over the controller (`true`) or hands it back. While held, the controller stops its
    /// Xbox output and streams `EF` input reports instead; it lets go by itself ~15 s after the
    /// host stops refreshing. Refused unless third-party control is allowed.
    public static func acquire(_ take: Bool, name: String = "ApexStation") -> Data {
        let tag = Array(name.utf8.prefix(20))
        return frame(.acquire, [take ? 1 : 0] + tag + [UInt8](repeating: 0, count: 20 - tag.count))
    }

    /// Whether the controller granted an `acquire` request.
    public static func acquireGranted(_ reply: some RandomAccessCollection<UInt8>) -> Bool? {
        let b = strip(reply)
        guard b.count > 5, command(of: b) == Command.acquire.rawValue else { return nil }
        return b[5] == 1
    }

    /// Whether third-party apps (SDL, Steam, Apex Station's live view) may take over the
    /// controller, from a `get status` reply.
    public static func thirdPartyAllowed(_ reply: some RandomAccessCollection<UInt8>) -> Bool? {
        let b = strip(reply)
        guard b.count > 9, command(of: b) == Command.getStatus.rawValue else { return nil }
        return b[9] == 1
    }
}

/// The `get info` reply: model, connection, battery and firmware versions.
public struct DeviceInfo: Sendable, Equatable {
    public enum Connection: Sendable, Equatable { case wired, wireless, unknown(UInt8) }
    public enum Charging: Sendable, Equatable { case onBattery, charging, charged }

    public var deviceID: UInt8
    public var connection: Connection
    /// 0-100, in 20 % steps.
    public var batteryPercent: Int
    public var charging: Charging
    public var firmware: String
    public var receiverFirmware: String?
    public var sensorFirmware: String
    public var radioFirmware: String

    public var modelName: String {
        switch deviceID {
        case 128, 129, 133, 134, 135, 136: "Apex 5"
        case 149, 150: "Apex 6"
        case 130, 144, 145: "Vader 5"
        default: "Flydigi controller (\(deviceID))"
        }
    }

    public init?(reply: some RandomAccessCollection<UInt8>) {
        let b = Flydigi.strip(reply)
        guard b.count >= 29, Flydigi.command(of: b) == Flydigi.Command.getInfo.rawValue else { return nil }
        deviceID = b[5]
        connection = switch b[6] { case 1: .wired; case 2: .wireless; default: .unknown(b[6]) }
        batteryPercent = min(Int(b[11] & 0x0F) * 20, 100)
        charging = switch b[11] >> 4 { case 1: .charging; case 2: .charged; default: .onBattery }
        firmware = Self.version(b[15], b[16])
        receiverFirmware = b[17] == 0 && b[18] == 0 ? nil : Self.version(b[17], b[18])
        sensorFirmware = Self.version(b[19], b[20])
        radioFirmware = Self.version(b[27], b[28])
    }

    /// One nibble per digit: `70 45` = 7.0.4.5.
    static func version(_ hi: UInt8, _ lo: UInt8) -> String {
        [hi >> 4, hi & 0x0F, lo >> 4, lo & 0x0F].map(String.init).joined(separator: ".")
    }
}

/// The controller's own input stream (`5A A5 EF …`). Unlike the Xbox report it carries
/// the back paddles, C/Z, LM/RM and motion data.
public enum FlydigiInputReport {
    private static let byte11: [(UInt8, GamepadButtons)] = [(0x10, .a), (0x20, .b), (0x40, .back), (0x80, .x)]
    private static let byte12: [(UInt8, GamepadButtons)] = [
        (0x01, .y), (0x02, .start), (0x04, .leftBumper), (0x08, .rightBumper), (0x40, .leftStick), (0x80, .rightStick),
    ]
    private static let byte13: [(UInt8, GamepadButtons)] = [
        (0x01, .c), (0x02, .z), (0x04, .m1), (0x08, .m2), (0x10, .m3), (0x20, .m4), (0x40, .leftMacro), (0x80, .rightMacro),
    ]
    // Bit layout matches Space Station's own parser for the Apex 5. Byte 12's 0x10/0x20 are
    // LT/RT "pressed" flags; the analog values in bytes 15/16 carry the same information.
    private static let byte14: [(UInt8, GamepadButtons)] = [(0x01, .fn), (0x02, .turbo), (0x08, .guide)]
    private static let dpad: [(UInt8, GamepadButtons)] = [(0x01, .dpadUp), (0x02, .dpadRight), (0x04, .dpadDown), (0x08, .dpadLeft)]

    public static func parse(_ r: some RandomAccessCollection<UInt8>) -> GamepadState? {
        let b = Flydigi.strip(r)
        guard b.count >= 29, Flydigi.command(of: b) == Flydigi.Command.input.rawValue else { return nil }
        var s = GamepadState()
        for (table, i) in [(dpad, 11), (byte11, 11), (byte12, 12), (byte13, 13), (byte14, 14)] {
            for (mask, button) in table where b[i] & mask != 0 { s.buttons.insert(button) }
        }
        // Already XInput convention (up-positive), verified on hardware.
        s.leftStick = StickPosition(x: int16(b, 3), y: int16(b, 5))
        s.rightStick = StickPosition(x: int16(b, 7), y: int16(b, 9))
        s.leftTrigger = b[15]
        s.rightTrigger = b[16]
        s.motion = MotionSample(
            gyro: (int16(b, 17), int16(b, 19), int16(b, 21)),
            accel: (int16(b, 23), int16(b, 25), int16(b, 27))
        )
        return s
    }
}
