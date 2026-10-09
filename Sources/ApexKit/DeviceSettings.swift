import Foundation

/// Settings stored on the controller itself, read with command `0x03` and changed with
/// `0x13` (switches), `0x14` (report rate), `0x15` (stick precision), `0x16` (stick
/// sensitivity) and `0x17` (sleep time).
public struct DeviceSettings: Sendable, Equatable {
    /// On/off settings. The raw value is the `0x13` sub-command and the bit in the status reply.
    public enum Switch: UInt8, Sendable, CaseIterable {
        case quickProfileSwitch = 1
        case xboxHomeButton = 2
        case motionSmoothing = 3
        case mappingSwitch = 4
        case stickSmoothing = 5
        case stickAutoCalibration = 6
        case stickRebound = 7
        case screenStatusBarAlwaysOn = 8
        /// The screen plays its animation. Space Station calls it "offScreen" but its Animation
        /// switch shows it as is: set means the animation is on.
        case screenAnimation = 9
        case audio = 10
    }

    public enum Precision: UInt8, Sendable, CaseIterable {
        case bits8 = 1, bits10 = 2, bits12 = 3, bits9 = 4, bits11 = 5, bits14 = 6, bits16 = 7
        public var bits: Int {
            switch self {
            case .bits8: 8
            case .bits9: 9
            case .bits10: 10
            case .bits11: 11
            case .bits12: 12
            case .bits14: 14
            case .bits16: 16
            }
        }
    }

    public enum Sensitivity: UInt8, Sendable, CaseIterable {
        case highest = 14, high, middleHigh, middle, lowMiddle, low, lowest
    }

    public enum ReportRate: UInt8, Sendable, CaseIterable {
        case hz1000 = 1, hz500 = 2, hz250 = 4, hz125 = 8
        public var hertz: Int { 1000 / Int(rawValue) }
    }

    /// Minutes; 0 = never.
    public static let sleepOptions = [1, 5, 15, 60, 180, 0]

    /// Switches this controller has.
    public var available: Set<Switch>
    /// Switches that are on.
    public var enabled: Set<Switch>
    /// Minutes of inactivity before sleeping; 0 = never.
    public var sleepMinutes: Int
    /// nil = not set (the cable always runs at the maximum rate).
    public var reportRate: ReportRate?
    public var precision: Precision?
    public var sensitivity: Sensitivity?

    public init?(reply: some RandomAccessCollection<UInt8>) {
        let b = Flydigi.strip(reply)
        guard b.count >= 13, Flydigi.command(of: b) == 0x03 else { return nil }
        // Bytes 5/6: availability/state of switches 1-8 (bit n-1). Bytes 7/8: switches 9-10.
        func set(_ low: UInt8, _ high: UInt8) -> Set<Switch> {
            Set(Switch.allCases.filter { s in
                let n = Int(s.rawValue) - 1
                return n < 8 ? low & (1 << n) != 0 : high & (1 << (n - 8)) != 0
            })
        }
        available = set(b[5], b[7])
        enabled = set(b[6], b[8])
        sleepMinutes = Int(b[9])
        reportRate = ReportRate(rawValue: b[10])
        precision = Precision(rawValue: b[11])
        sensitivity = Sensitivity(rawValue: b[12])
    }
}

extension Flydigi {
    public static func readSettings() -> Data { frame(0x03, []) }

    public static func set(_ s: DeviceSettings.Switch, _ on: Bool) -> Data { frame(0x13, [s.rawValue, on ? 1 : 0]) }

    public static func setSleep(minutes: Int) -> Data { frame(0x17, [UInt8(clamping: minutes)]) }

    public static func setReportRate(_ r: DeviceSettings.ReportRate) -> Data { frame(0x14, [r.rawValue]) }

    public static func setPrecision(_ p: DeviceSettings.Precision) -> Data { frame(0x15, [p.rawValue]) }

    public static func setSensitivity(_ s: DeviceSettings.Sensitivity) -> Data { frame(0x16, [s.rawValue]) }
}
