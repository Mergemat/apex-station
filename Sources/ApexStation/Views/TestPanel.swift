import ApexKit
import SwiftUI

/// What the controller reports, as text: how steadily reports arrive, the raw stick, trigger and
/// motion values, and a log of every button going down and up with what it acts as. Like Space
/// Station's advanced test.
struct TestPanel: View {
    @Environment(ControllerService.self) private var service

    var body: some View {
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
        VStack(alignment: .leading, spacing: 8) {
            Caption("Now")
            Text(now).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.black.opacity(0.25), in: .rect(cornerRadius: 10))
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Caption("Log")
                Spacer()
                Button("Clear") { service.clearInputLog() }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            log
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

    // MARK: Log

    private var log: some View {
        VStack(alignment: .leading, spacing: 3) {
            if service.inputLog.lines.isEmpty {
                Text("Press buttons on the controller.").foregroundStyle(Theme.label)
            }
            ForEach(service.inputLog.lines.prefix(150)) { line in
                HStack(spacing: 0) {
                    Text(String(format: "%8.3f", line.time)).foregroundStyle(Theme.label).frame(width: 64, alignment: .trailing)
                    Text(line.name).fontWeight(.semibold).foregroundStyle(line.down ? .white : Theme.secondary)
                        .frame(width: 52, alignment: .leading).padding(.leading, 12)
                    Text(line.down ? "down" : "up").foregroundStyle(line.down ? Theme.glow : Theme.label).frame(width: 40, alignment: .leading)
                    if let acts = line.actsAs {
                        Text("→ \(acts)").foregroundStyle(Theme.glow)
                    } else if let held = line.held {
                        Text("\(held) ms").foregroundStyle(Theme.label)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .lineLimit(1)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.25), in: .rect(cornerRadius: 10))
    }

    // MARK: Raw values

    private var now: String {
        let s = service.state
        func stick(_ p: StickPosition) -> String { String(format: "%+6d %+6d", Int(p.x), Int(p.y)) }
        var lines = [
            "LS \(stick(s.leftStick))   RS \(stick(s.rightStick))",
            String(format: "LT %3d   RT %3d", s.leftTrigger, s.rightTrigger),
        ]
        if let m = s.motion {
            // 2000 °/s full scale; 4096 per g (about 1 g in total at rest).
            let d = 2000.0 / 32768
            lines.append(String(format: "gyro  %+6.0f %+6.0f %+6.0f °/s", Double(m.gyro.x) * d, Double(m.gyro.y) * d, Double(m.gyro.z) * d))
            lines.append(String(format: "accel %+6.2f %+6.2f %+6.2f g", Double(m.accel.x) / 4096, Double(m.accel.y) / 4096, Double(m.accel.z) / 4096))
        }
        return lines.joined(separator: "\n")
    }

    private var liveHint: String {
        if !service.connected && !service.bluetooth { return "Connect the controller to test it." }
        if service.fullControllerEnabled == false { return "The test reads the controller's own input, which needs Full controller." }
        return "Starting…"
    }

    private var connection: String {
        if !service.connected && service.bluetooth {
            return "Bluetooth: shows what the controller sends after remapping. Paddles and gyro aren't reported."
        }
        let via = service.info?.connection == .wireless ? "2.4 GHz receiver" : "Cable"
        return "\(via): remapped buttons show as the button they act as."
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
