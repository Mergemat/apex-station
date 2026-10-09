import Foundation

/// Buttons, sticks and gyro acting as keyboard and mouse, like Space Station's keyboard/mouse
/// mapping. It isn't stored on the controller (Space Station keeps it on the PC too): the app
/// reads the controller and types or moves the mouse itself.
public struct KeyboardMouseMap: Codable, Sendable, Equatable {
    public enum MouseButton: String, Codable, Sendable, CaseIterable { case left, right, middle }

    public enum Output: Codable, Sendable, Hashable {
        /// A macOS virtual key code and how to show it.
        case key(code: UInt16, label: String)
        case mouse(MouseButton)
        /// One wheel step per press.
        case scroll(up: Bool)

        public var label: String {
            switch self {
            case .key(_, let label): label
            case .mouse(.left): "Left click"
            case .mouse(.right): "Right click"
            case .mouse(.middle): "Middle click"
            case .scroll(true): "Scroll up"
            case .scroll(false): "Scroll down"
            }
        }
    }

    public enum StickMode: Codable, Sendable, Equatable {
        /// Stays a stick.
        case stick
        /// Four keys; diagonals press two.
        case keys(up: Output, left: Output, down: Output, right: Output)
        /// Moves the pointer; sensitivity 1-100.
        case mouse(sensitivity: Int)

        public static let wasd = StickMode.keys(up: .key(code: 13, label: "W"), left: .key(code: 0, label: "A"),
                                                down: .key(code: 1, label: "S"), right: .key(code: 2, label: "D"))
        public static let arrows = StickMode.keys(up: .key(code: 126, label: "↑"), left: .key(code: 123, label: "←"),
                                                  down: .key(code: 125, label: "↓"), right: .key(code: 124, label: "→"))
    }

    /// Keyed by `FlydigiKey` raw value.
    public var buttons: [UInt8: Output] = [:]
    public var leftStick: StickMode = .stick
    public var rightStick: StickMode = .stick

    public init() {}

    public subscript(key: FlydigiKey) -> Output? {
        get { buttons[key.rawValue] }
        set { buttons[key.rawValue] = newValue }
    }

    public var isEmpty: Bool { buttons.isEmpty && leftStick == .stick && rightStick == .stick }
}

/// What the app should send to macOS.
public enum KeyboardMouseEvent: Sendable, Equatable {
    case keyDown(UInt16)
    case keyUp(UInt16)
    case mouseDown(KeyboardMouseMap.MouseButton)
    case mouseUp(KeyboardMouseMap.MouseButton)
    case scroll(Int)
    /// Pointer movement in points, y down.
    case move(dx: Double, dy: Double)
}

/// Turns controller states into keyboard and mouse events.
public struct KeyboardMouseEngine: Sendable {
    /// Gyro steering the pointer: sensitivity 1-100 and an optional button that turns it on.
    public struct GyroMouse: Sendable, Equatable {
        public var sensitivity: Int
        public var key: FlydigiKey?
        public var hold: Bool
        public init(sensitivity: Int, key: FlydigiKey?, hold: Bool) {
            self.sensitivity = sensitivity
            self.key = key
            self.hold = hold
        }
    }

    public var map: KeyboardMouseMap
    private var down: Set<KeyboardMouseMap.Output> = []
    private var gyroOn = false
    private var gyroKeyWasDown = false

    /// Stick travel below this is ignored.
    static let deadZone = 0.15
    /// Full stick at sensitivity 50 moves the pointer this many points a second.
    static let stickSpeed = 2000.0
    /// At sensitivity 50, a degree of turn moves the pointer this many points.
    static let gyroPointsPerDegree = 20.0

    public init(map: KeyboardMouseMap) { self.map = map }

    /// Events for the controller now being in `state`, `dt` seconds after the last call.
    public mutating func step(_ state: GamepadState, dt: Double, gyro: GyroMouse? = nil) -> [KeyboardMouseEvent] {
        var wanted: Set<KeyboardMouseMap.Output> = []
        let mapped = map.buttons.keys.compactMap(FlydigiKey.init(rawValue:))
        for key in FlydigiKey.pressed(in: state, among: mapped) {
            if let out = map[key] { wanted.insert(out) }
        }
        var dx = 0.0, dy = 0.0
        for (mode, stick) in [(map.leftStick, state.leftStick), (map.rightStick, state.rightStick)] {
            let x = Double(stick.x) / 32767, y = Double(stick.y) / 32767
            switch mode {
            case .stick: break
            case let .keys(up, left, down, right):
                if y > Self.deadZone * 2 { wanted.insert(up) }
                if y < -Self.deadZone * 2 { wanted.insert(down) }
                if x < -Self.deadZone * 2 { wanted.insert(left) }
                if x > Self.deadZone * 2 { wanted.insert(right) }
            case .mouse(let sensitivity):
                let m = min(1, hypot(x, y))
                guard m > Self.deadZone else { break }
                let speed = Self.stickSpeed * Double(sensitivity) / 50 * pow((m - Self.deadZone) / (1 - Self.deadZone), 1.6)
                dx += x / m * speed * dt
                dy -= y / m * speed * dt
            }
        }
        if let gyro, let motion = state.motion {
            if let key = gyro.key {
                let isDown = FlydigiKey.pressed(in: state, among: [key]).contains(key)
                if gyro.hold { gyroOn = isDown } else if isDown, !gyroKeyWasDown { gyroOn.toggle() }
                gyroKeyWasDown = isDown
            } else {
                gyroOn = true
            }
            // Space Station's mapping: yaw (gyro Z) across, pitch (gyro X) up and down, ignoring
            // the sensor's resting noise. Raw units are 2000 °/s full scale.
            if gyroOn, abs(Int(motion.gyro.x)) >= 8 || abs(Int(motion.gyro.z)) >= 8 {
                let scale = 0.06103702 * dt * Self.gyroPointsPerDegree * Double(gyro.sensitivity) / 50
                dx -= Double(motion.gyro.z) * scale
                dy -= Double(motion.gyro.x) * scale
            }
        }
        var events: [KeyboardMouseEvent] = []
        for out in down.subtracting(wanted) { events += release(out) }
        for out in wanted.subtracting(down) { events += press(out) }
        down = wanted
        if dx != 0 || dy != 0 { events.append(.move(dx: dx, dy: dy)) }
        return events
    }

    /// Lets go of everything held, for when the mapping stops.
    public mutating func releaseAll() -> [KeyboardMouseEvent] {
        defer { down = [] }
        return down.flatMap(release)
    }

    private func press(_ out: KeyboardMouseMap.Output) -> [KeyboardMouseEvent] {
        switch out {
        case .key(let code, _): [.keyDown(code)]
        case .mouse(let b): [.mouseDown(b)]
        case .scroll(let up): [.scroll(up ? 1 : -1)]
        }
    }

    private func release(_ out: KeyboardMouseMap.Output) -> [KeyboardMouseEvent] {
        switch out {
        case .key(let code, _): [.keyUp(code)]
        case .mouse(let b): [.mouseUp(b)]
        case .scroll: []
        }
    }
}
