import ApexKit
import SwiftUI

/// The input test: a log of every button going down and up, and bars for the analog inputs the
/// drawing can't show precisely. Like Space Station's advanced test.
struct TestPanel: View {
    @Environment(ControllerService.self) private var service

    var body: some View {
        HoldsController()
        if !service.live {
            Note(liveHint)
            if service.connected, service.fullControllerEnabled == false {
                Button("Turn on Full controller") { Task { await service.setFullController(true) } }
                    .buttonStyle(.plain).font(Theme.buttonFont).foregroundStyle(Theme.glow)
            }
        }
        let s = service.state
        VStack(alignment: .leading, spacing: 8) {
            Caption("Triggers")
            Meter(name: "LT", value: Double(s.leftTrigger) / 255, text: "\(s.leftTrigger)")
            Meter(name: "RT", value: Double(s.rightTrigger) / 255, text: "\(s.rightTrigger)")
        }
        if let m = s.motion {
            VStack(alignment: .leading, spacing: 8) {
                Caption("Gyro °/s")
                // 2000 °/s full scale; the bars show ±500.
                ForEach(Array(zip(["X", "Y", "Z"], [m.gyro.x, m.gyro.y, m.gyro.z])), id: \.0) { axis, v in
                    let dps = Double(v) * 2000 / 32768
                    Meter(name: axis, value: dps / 500, text: String(format: "%.0f", dps), centred: true)
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Caption("Log")
                Spacer()
                Text(reports).font(Theme.monoFont).foregroundStyle(Theme.label)
                Button("Clear") { service.clearInputLog() }
                    .buttonStyle(.plain).font(Theme.linkFont).foregroundStyle(Theme.secondary)
                    .padding(.leading, 6)
            }
            log
        }
    }

    /// How steadily reports arrive: rate, average and worst gap.
    private var reports: String {
        guard let t = service.reportTiming else { return "" }
        return String(format: "%d Hz · %.1f ms · worst %.1f", service.reportRate, t.average, t.longest)
    }

    private var liveHint: String {
        if !service.connected && !service.bluetooth { return "Connect the controller to test it." }
        if service.fullControllerEnabled == false { return "The test reads the controller's own input, which needs Full controller." }
        return "Starting…"
    }

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
        .font(Theme.monoFont)
        .lineLimit(1)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.25), in: .rect(cornerRadius: 10))
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
            Text(name).font(Theme.linkFont).foregroundStyle(Theme.secondary).frame(width: 22, alignment: .leading)
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
            Text(text).font(Theme.monoFont).foregroundStyle(Theme.label).frame(width: 44, alignment: .trailing)
        }
    }
}
