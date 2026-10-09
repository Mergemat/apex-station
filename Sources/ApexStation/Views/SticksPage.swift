import ApexKit
import SwiftUI

struct SticksPage: View {
    @Environment(ControllerService.self) private var service

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                StickPlot(title: "Left stick", position: service.state.leftStick, live: service.live)
                StickPlot(title: "Right stick", position: service.state.rightStick, live: service.live)
            }
            if let s = service.settings { StickSettings(settings: s) }
        }
        .onAppear { service.liveViewAppeared() }
        .onDisappear { service.liveViewDisappeared() }
    }
}

/// A live plot of one stick that keeps a fading trail, so circling the stick shows its range.
private struct StickPlot: View {
    let title: String
    let position: StickPosition
    let live: Bool
    @ViewState private var trail: [CGPoint] = []

    var body: some View {
        Card(title: title) {
            Canvas { ctx, size in
                let side = min(size.width, size.height)
                let r = side / 2 - 6
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let rim = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.fill(rim, with: .color(Color.black.opacity(0.25)))
                ctx.stroke(rim, with: .color(Theme.stroke), lineWidth: 1)
                for f in [0.5] {
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * f, y: c.y - r * f, width: r * f * 2, height: r * f * 2)),
                               with: .color(Theme.stroke), lineWidth: 0.5)
                }
                var cross = Path()
                cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
                cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
                ctx.stroke(cross, with: .color(Theme.stroke), lineWidth: 0.5)
                for (i, p) in trail.enumerated() {
                    let a = Double(i) / Double(max(1, trail.count))
                    let q = CGPoint(x: c.x + p.x * r, y: c.y - p.y * r)
                    ctx.fill(Path(ellipseIn: CGRect(x: q.x - 1.5, y: q.y - 1.5, width: 3, height: 3)), with: .color(Theme.accent.opacity(0.15 + a * 0.5)))
                }
                let p = point
                let q = CGPoint(x: c.x + p.x * r, y: c.y - p.y * r)
                var g = ctx
                g.addFilter(.blur(radius: 6))
                g.fill(Path(ellipseIn: CGRect(x: q.x - 9, y: q.y - 9, width: 18, height: 18)), with: .color(Theme.glow.opacity(live ? 0.8 : 0)))
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 6, y: q.y - 6, width: 12, height: 12)), with: .color(live ? Theme.glow : Theme.idle))
            }
            .frame(height: 230)
            HStack {
                Text(String(format: "X %+.3f", point.x)).monospacedDigit()
                Spacer()
                Text(String(format: "Y %+.3f", point.y)).monospacedDigit()
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.secondary)
        }
        .onChange(of: position) { _, _ in
            trail.append(point)
            if trail.count > 240 { trail.removeFirst(trail.count - 240) }
        }
    }

    private var point: CGPoint { CGPoint(x: Double(position.x) / 32767, y: Double(position.y) / 32767) }
}

private struct StickSettings: View {
    @Environment(ControllerService.self) private var service
    let settings: DeviceSettings

    var body: some View {
        Card(title: "Stick behaviour") {
            VStack(spacing: 18) {
                SettingRow(title: "Precision", detail: "Resolution the sticks report at.") {
                    ChipPicker(options: [DeviceSettings.Precision.bits8, .bits10, .bits12], selection: settings.precision,
                               label: { "\($0.bits)-bit" }) { p in Task { await service.setPrecision(p) } }
                }
                Divider().overlay(Theme.stroke)
                SettingRow(title: "Center sensitivity", detail: "How strongly the sticks react around the centre.") {
                    ChipPicker(options: DeviceSettings.Sensitivity.allCases, selection: settings.sensitivity,
                               label: sensitivityLabel) { s in Task { await service.setSensitivity(s) } }
                }
                Divider().overlay(Theme.stroke)
                toggle(.stickSmoothing, "Joystick debounce",
                       "Off reacts to the tiniest movements but jitters more at rest.")
                toggle(.stickRebound, "Rebounce algorithm",
                       "Filters out the backwards bounce when you let go of a stick.")
                toggle(.stickAutoCalibration, "Auto-calibration", "Keeps the stick centre accurate over time.")
            }
        }
    }

    @ViewBuilder
    private func toggle(_ s: DeviceSettings.Switch, _ title: String, _ detail: String) -> some View {
        if settings.available.contains(s) {
            SettingRow(title: title, detail: detail) {
                GlowToggle(isOn: Binding(get: { settings.enabled.contains(s) },
                                         set: { on in Task { await service.set(s, on) } }))
            }
        }
    }

    private func sensitivityLabel(_ s: DeviceSettings.Sensitivity) -> String {
        switch s {
        case .highest: "Max"
        case .high: "High"
        case .middleHigh: "Mid+"
        case .middle: "Mid"
        case .lowMiddle: "Mid−"
        case .low: "Low"
        case .lowest: "Min"
        }
    }
}
