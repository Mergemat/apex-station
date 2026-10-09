import ApexKit
import SwiftUI

/// Everything the controller reports, live: buttons, sticks, triggers, motion and how steadily
/// reports arrive, plus a rumble test. Like Space Station's advanced test.
struct TestPanel: View {
    @Environment(ControllerService.self) private var service

    var body: some View {
        let s = service.state
        if !service.live {
            Note(liveHint)
            if service.connected, service.fullControllerEnabled == false {
                Button("Turn on Full controller") { Task { await service.setFullController(true) } }
                    .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.glow)
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            Caption("Reports")
            HStack(spacing: 8) {
                stat("\(service.reportRate)", "Hz")
                stat(service.reportTiming.map { String(format: "%.2f", $0.average) } ?? "–", "ms avg")
                stat(service.reportTiming.map { String(format: "%.1f", $0.longest) } ?? "–", "ms worst")
            }
            Text(connection).font(.system(size: 11.5)).foregroundStyle(Theme.label)
        }
        VStack(alignment: .leading, spacing: 10) {
            Caption("Buttons")
            ButtonGrid(buttons: s.buttons, leftTrigger: s.leftTrigger, rightTrigger: s.rightTrigger,
                       showsExtras: service.connected)
        }
        VStack(alignment: .leading, spacing: 10) {
            Caption("Sticks")
            HStack(spacing: 12) {
                MiniStick(name: "Left", position: s.leftStick)
                MiniStick(name: "Right", position: s.rightStick)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Caption("Triggers")
            Meter(name: "LT", value: Double(s.leftTrigger) / 255, text: "\(s.leftTrigger)")
            Meter(name: "RT", value: Double(s.rightTrigger) / 255, text: "\(s.rightTrigger)")
        }
        if let m = s.motion {
            VStack(alignment: .leading, spacing: 8) {
                Caption("Gyro (°/s)")
                ForEach(Array(zip(["X", "Y", "Z"], [m.gyro.x, m.gyro.y, m.gyro.z])), id: \.0) { axis, v in
                    // 2000 °/s full scale.
                    let dps = Double(v) * 2000 / 32768
                    Meter(name: axis, value: dps / 500, text: String(format: "%.0f", dps), centred: true)
                }
                Caption("Accelerometer (g)")
                ForEach(Array(zip(["X", "Y", "Z"], [m.accel.x, m.accel.y, m.accel.z])), id: \.0) { axis, v in
                    // 512 per g, as Space Station reads it (about 1 on Z at rest).
                    let g = Double(v) / 512
                    Meter(name: axis, value: g / 2, text: String(format: "%.2f", g), centred: true)
                }
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            Caption("Rumble")
            HStack(spacing: 8) {
                rumbleButton("Left", left: 255, right: 0)
                rumbleButton("Right", left: 0, right: 255)
                rumbleButton("Both", left: 255, right: 255)
            }
        }
    }

    private var liveHint: String {
        if !service.connected && !service.bluetooth { return "Connect the controller to test it." }
        if service.fullControllerEnabled == false { return "The test reads the controller's own input, which needs Full controller." }
        return "Starting…"
    }

    private var connection: String {
        if !service.connected && service.bluetooth { return "Bluetooth. Paddles and gyro aren't reported in this mode." }
        if service.info?.connection == .wireless { return "2.4 GHz receiver." }
        return service.connected ? "Cable." : ""
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(unit).font(.system(size: 10.5)).foregroundStyle(Theme.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
    }

    private func rumbleButton(_ title: String, left: UInt8, right: UInt8) -> some View {
        Button { Task { await service.rumble(left: left, right: right) } } label: {
            Text(title).font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .glass(.capsule, interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(!service.connected && !service.bluetooth)
    }
}

/// Every button as a chip that lights while held.
private struct ButtonGrid: View {
    let buttons: GamepadButtons
    let leftTrigger: UInt8
    let rightTrigger: UInt8
    /// Paddles, C/Z, LM/RM, Turbo and Fn only come through the cable or receiver.
    let showsExtras: Bool

    private var items: [(String, Bool)] {
        var list: [(String, Bool)] = [
            ("A", buttons.contains(.a)), ("B", buttons.contains(.b)), ("X", buttons.contains(.x)), ("Y", buttons.contains(.y)),
            ("LB", buttons.contains(.leftBumper)), ("RB", buttons.contains(.rightBumper)),
            ("LT", leftTrigger >= 128), ("RT", rightTrigger >= 128),
            ("View", buttons.contains(.back)), ("Menu", buttons.contains(.start)), ("Home", buttons.contains(.guide)),
            ("L3", buttons.contains(.leftStick)), ("R3", buttons.contains(.rightStick)),
            ("↑", buttons.contains(.dpadUp)), ("↓", buttons.contains(.dpadDown)),
            ("←", buttons.contains(.dpadLeft)), ("→", buttons.contains(.dpadRight)),
        ]
        if showsExtras {
            list += [
                ("M1", buttons.contains(.m1)), ("M2", buttons.contains(.m2)), ("M3", buttons.contains(.m3)), ("M4", buttons.contains(.m4)),
                ("LM", buttons.contains(.leftMacro)), ("RM", buttons.contains(.rightMacro)),
                ("C", buttons.contains(.c)), ("Z", buttons.contains(.z)),
                ("Turbo", buttons.contains(.turbo)), ("Fn", buttons.contains(.fn)),
            ]
        }
        return list
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.0) { name, on in
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1).fixedSize()
                    .frame(minWidth: 30)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(on ? Theme.accent : Color.white.opacity(0.05), in: .rect(cornerRadius: 8))
                    .foregroundStyle(on ? .white : Theme.secondary)
                    .bloom(on, radius: 6)
            }
        }
    }
}

/// A small square plot of one stick with its raw values.
private struct MiniStick: View {
    let name: String
    let position: StickPosition

    var body: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in
                let r = min(size.width, size.height) / 2 - 2
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let rim = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.fill(rim, with: .color(.black.opacity(0.25)))
                ctx.stroke(rim, with: .color(Theme.stroke), lineWidth: 1)
                var cross = Path()
                cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
                cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
                ctx.stroke(cross, with: .color(Theme.stroke), lineWidth: 0.5)
                let q = CGPoint(x: c.x + Double(position.x) / 32767 * r, y: c.y - Double(position.y) / 32767 * r)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 5, y: q.y - 5, width: 10, height: 10)), with: .color(Theme.glow))
            }
            .aspectRatio(1, contentMode: .fit)
            Text("\(name)  \(position.x), \(position.y)")
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.label)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A labelled bar, filled from the left or, for signed values, from the middle.
private struct Meter: View {
    let name: String
    /// 0...1, or -1...1 when centred.
    let value: Double
    let text: String
    var centred = false

    var body: some View {
        HStack(spacing: 8) {
            Text(name).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.secondary).frame(width: 22, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width, v = min(1, max(centred ? -1 : 0, value))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    if centred {
                        Capsule().fill(Theme.accent)
                            .frame(width: max(3, abs(v) * w / 2))
                            .offset(x: v >= 0 ? w / 2 : w / 2 - abs(v) * w / 2)
                    } else {
                        Capsule().fill(Theme.accent).frame(width: max(0, v * w))
                    }
                }
            }
            .frame(height: 8)
            Text(text).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.label).frame(width: 44, alignment: .trailing)
        }
    }
}
