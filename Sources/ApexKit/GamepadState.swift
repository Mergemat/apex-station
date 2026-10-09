/// Buttons the Apex 5 can report. The Xbox-standard ones come from the XInput
/// report; the extras (paddles, C/Z, LM/RM) only exist in Flydigi's own input stream.
public struct GamepadButtons: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let a = Self(rawValue: 1 << 0)
    public static let b = Self(rawValue: 1 << 1)
    public static let x = Self(rawValue: 1 << 2)
    public static let y = Self(rawValue: 1 << 3)
    public static let leftBumper = Self(rawValue: 1 << 4)
    public static let rightBumper = Self(rawValue: 1 << 5)
    public static let back = Self(rawValue: 1 << 6)
    public static let start = Self(rawValue: 1 << 7)
    public static let leftStick = Self(rawValue: 1 << 8)
    public static let rightStick = Self(rawValue: 1 << 9)
    public static let guide = Self(rawValue: 1 << 10)
    public static let dpadUp = Self(rawValue: 1 << 11)
    public static let dpadDown = Self(rawValue: 1 << 12)
    public static let dpadLeft = Self(rawValue: 1 << 13)
    public static let dpadRight = Self(rawValue: 1 << 14)
    public static let m1 = Self(rawValue: 1 << 15)
    public static let m2 = Self(rawValue: 1 << 16)
    public static let m3 = Self(rawValue: 1 << 17)
    public static let m4 = Self(rawValue: 1 << 18)
    public static let c = Self(rawValue: 1 << 19)
    public static let z = Self(rawValue: 1 << 20)
    public static let leftMacro = Self(rawValue: 1 << 21)
    public static let rightMacro = Self(rawValue: 1 << 22)
    public static let circle = Self(rawValue: 1 << 23)
}

/// A stick position in XInput convention: centre 0, right and up positive.
public struct StickPosition: Sendable, Equatable {
    public var x: Int16
    public var y: Int16
    public init(x: Int16 = 0, y: Int16 = 0) { self.x = x; self.y = y }
}

public struct MotionSample: Sendable, Equatable {
    public var gyro: (x: Int16, y: Int16, z: Int16)
    public var accel: (x: Int16, y: Int16, z: Int16)
    public init(gyro: (Int16, Int16, Int16) = (0, 0, 0), accel: (Int16, Int16, Int16) = (0, 0, 0)) {
        self.gyro = gyro
        self.accel = accel
    }
    public static func == (l: Self, r: Self) -> Bool {
        l.gyro == r.gyro && l.accel == r.accel
    }
}

public struct GamepadState: Sendable, Equatable {
    public var buttons: GamepadButtons = []
    public var leftStick = StickPosition()
    public var rightStick = StickPosition()
    public var leftTrigger: UInt8 = 0
    public var rightTrigger: UInt8 = 0
    public var motion: MotionSample?
    public init() {}
}
