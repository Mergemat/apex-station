import ApexKit
import SwiftUI

/// The panel that slides in next to the controller for whatever the user clicked.
struct Inspector: View {
    @Environment(ControllerService.self) private var service
    let control: ControllerControl
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Caption(subtitle)
                    Text(title).font(.system(size: 26, weight: .semibold))
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .glass(.circle, interactive: true)
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) { content }
            }
            .scrollIndicators(.never)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(.rect(cornerRadius: 28))
    }

    private var title: String {
        switch control {
        case .key(let k): k.name
        case .leftStick: "Left stick"
        case .rightStick: "Right stick"
        }
    }

    private var subtitle: String {
        switch control {
        case .key(let k) where [.m1, .m2, .m3, .m4].contains(k): "Back paddle"
        case .key(let k) where [.lt, .rt].contains(k): "Trigger"
        case .key(let k) where [.lb, .rb, .lm, .rm].contains(k): "Shoulder"
        case .key(let k) where [.up, .down, .left, .right].contains(k): "D-pad"
        case .key(.turbo), .key(.fn): "Controller key"
        case .key: "Button"
        case .leftStick, .rightStick: "Stick"
        }
    }

    @ViewBuilder private var content: some View {
        switch control {
        case .key(.turbo):
            Note("Turbo is a controller shortcut: hold it and press another button to give that button turbo. The controller handles it itself, so it can't be remapped.")
        case .key(.fn):
            Note("Fn is a controller shortcut: with Fast Swap on, Fn plus A, B, X or Y switches between the four profiles. The controller handles it itself, so it can't be remapped.")
        case .key(let key):
            ButtonPanel(key: key)
        case .leftStick:
            StickPanel(left: true)
        case .rightStick:
            StickPanel(left: false)
        }
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Buttons

/// What a button does in the active profile: which button it acts as, and turbo.
private struct ButtonPanel: View {
    @Environment(ControllerService.self) private var service
    let key: FlydigiKey

    private var profile: Profile? { service.editingProfile }

    var body: some View {
        if let profile {
            let mapping = profile.mapping(for: key)
            VStack(alignment: .leading, spacing: 10) {
                Caption("Acts as")
                TargetGrid(key: key, current: mapping) { target in
                    Task { await service.remap(key, to: target == key ? .standard : .button(target)) }
                }
                if case .macro = mapping { Note("Runs a macro. Macros are coming soon.") }
                if case .keyboardOrMouse = mapping { Note("Sends a keyboard or mouse input set up in Space Station.") }
            }
            TurboSection(key: key, turbo: profile.turbo(for: key))
            Text("Saved to profile \(profile.slot + 1) on the controller, so it works everywhere: wired, wireless and Switch mode.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.label).fixedSize(horizontal: false, vertical: true)
        } else {
            Note(service.connected ? "Reading the controller's profiles…" : "Connect your Apex 5 to change its buttons.")
        }
    }
}

/// Every Apex 5 button as a target; the button's own entry means "default".
struct TargetGrid: View {
    let key: FlydigiKey
    let current: KeyMapping
    let pick: (FlydigiKey) -> Void

    private let targets: [FlydigiKey] = [
        .a, .b, .x, .y, .lb, .rb, .lt, .rt, .up, .down, .left, .right, .l3, .r3, .view, .menu, .home,
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach([key] + targets.filter { $0 != key }, id: \.self) { target in
                let isOwn = target == key
                let selected = isOwn ? current == .standard : current == .button(target)
                Button { pick(target) } label: {
                    VStack(spacing: 2) {
                        Text(shortName(target)).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        if isOwn { Text("DEFAULT").font(.system(size: 7, weight: .bold)).tracking(0.8).opacity(0.7) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .foregroundStyle(selected ? .white : Theme.secondary)
                    .background(selected ? Theme.accent : Color.white.opacity(0.06), in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.glow.opacity(0.6) : Theme.stroke))
                    .bloom(selected, radius: 8)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: current)
    }

    private func shortName(_ k: FlydigiKey) -> String {
        switch k {
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        default: k.name
        }
    }
}

private struct TurboSection: View {
    @Environment(ControllerService.self) private var service
    let key: FlydigiKey
    let turbo: (mode: TurboMode, speed: UInt8)?
    @ViewState private var speed: Double = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption("Turbo")
            ChipPicker(options: [TurboMode.off, .hold, .toggle], selection: turbo?.mode ?? .off, label: label) { mode in
                Task { await service.setTurbo(key, mode == .off ? nil : (mode, UInt8(speed))) }
            }
            if let turbo {
                HStack {
                    Text("Speed").font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                    Slider(value: Binding(get: { speed }, set: { speed = $0.rounded() }), in: 1...30) { editing in
                        if !editing { Task { await service.setTurbo(key, (turbo.mode, UInt8(speed))) } }
                    }
                    Text("\(Int(speed))/s").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondary).frame(width: 36)
                }
            }
        }
        .onAppear { speed = Double(turbo?.speed ?? 10) }
        .onChange(of: turbo?.speed) { _, s in if let s { speed = Double(s) } }
    }

    private func label(_ m: TurboMode) -> String {
        switch m {
        case .off: "Off"
        case .hold: "While held"
        case .toggle: "Toggle"
        }
    }
}

// MARK: - Sticks

private struct StickPanel: View {
    @Environment(ControllerService.self) private var service
    let left: Bool

    var body: some View {
        let config = service.editingProfile?.stick(left: left)
        StickPlot(position: left ? service.state.leftStick : service.state.rightStick, live: service.live,
                  deadZone: CGFloat(config?.deadZone ?? 0) / 127, edge: CGFloat(config?.edge ?? 127) / 127)
            .frame(height: 200)
        if let config { StickShape(config: config, left: left) }
        if let profile = service.editingProfile {
            let key: FlydigiKey = left ? .l3 : .r3
            VStack(alignment: .leading, spacing: 10) {
                Caption("Click (\(key.name)) acts as")
                TargetGrid(key: key, current: profile.mapping(for: key)) { target in
                    Task { await service.remap(key, to: target == key ? .standard : .button(target)) }
                }
            }
        }
        if let s = service.settings {
            VStack(alignment: .leading, spacing: 10) {
                Caption("Precision · both sticks")
                ChipPicker(options: [DeviceSettings.Precision.bits8, .bits10, .bits12], selection: s.precision, label: { "\($0.bits)-bit" }) { p in
                    Task { await service.setPrecision(p) }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Caption("Center sensitivity · both sticks")
                ChipPicker(options: [DeviceSettings.Sensitivity.high, .middle, .low], selection: s.sensitivity, label: sensitivityLabel) { v in
                    Task { await service.setSensitivity(v) }
                }
            }
            toggle(s, .stickSmoothing, "Joystick debounce", "Off reacts to the tiniest movements but jitters more at rest.")
            toggle(s, .stickRebound, "Rebounce algorithm", "Filters the backwards bounce when you let go of a stick.")
            toggle(s, .stickAutoCalibration, "Auto-calibration", "Keeps the centre accurate over time.")
        }
    }

    @ViewBuilder
    private func toggle(_ s: DeviceSettings, _ sw: DeviceSettings.Switch, _ title: String, _ detail: String) -> some View {
        if s.available.contains(sw) {
            SettingRow(title: title, detail: detail) {
                GlowToggle(isOn: Binding(get: { s.enabled.contains(sw) }, set: { on in Task { await service.set(sw, on) } }))
            }
        }
    }

    private func sensitivityLabel(_ s: DeviceSettings.Sensitivity) -> String {
        switch s {
        case .highest, .high, .middleHigh: "Fast"
        case .middle: "Medium"
        default: "Slow"
        }
    }
}

/// Dead zone, range, curve and shape for one stick, stored in the active profile.
private struct StickShape: View {
    @Environment(ControllerService.self) private var service
    let config: StickConfig
    let left: Bool
    @ViewState private var deadZone: Double = 0
    @ViewState private var edge: Double = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption("Dead zone")
            slider(value: $deadZone, range: 0...40, unit: "%") { save { $0.deadZone = percentToRaw(deadZone) } }
            Caption("Full output at")
            slider(value: $edge, range: 70...100, unit: "%") { save { $0.edge = percentToRaw(edge) } }
        }
        VStack(alignment: .leading, spacing: 10) {
            Caption("Response curve")
            ChipPicker(options: [StickConfig.Curve.standard, .quick, .slow], selection: config.curve, label: curveLabel) { c in
                save { $0.curve = c }
            }
            Caption("Shape")
            ChipPicker(options: [false, true], selection: config.circular, label: { $0 ? "Circle" : "Square" }) { c in
                save { $0.circular = c }
            }
        }
        .onAppear(perform: load)
        .onChange(of: config) { _, _ in load() }
    }

    private func load() {
        deadZone = (Double(config.deadZone) * 100 / 127).rounded()
        edge = (Double(config.edge) * 100 / 127).rounded()
    }

    private func percentToRaw(_ percent: Double) -> Int { Int((percent * 127 / 100).rounded()) }

    private func save(_ change: (inout StickConfig) -> Void) {
        var c = config
        change(&c)
        Task { await service.setStick(c, left: left) }
    }

    private func slider(value: Binding<Double>, range: ClosedRange<Double>, unit: String, commit: @escaping () -> Void) -> some View {
        HStack {
            // No step: macOS would draw a tick per step. Values are rounded instead.
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() }), in: range) { editing in
                if !editing { commit() }
            }
            Text("\(Int(value.wrappedValue))\(unit)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondary).frame(width: 40)
        }
    }

    private func curveLabel(_ c: StickConfig.Curve) -> String {
        switch c {
        case .standard: "Default"
        case .quick: "Quick"
        case .slow: "Slow"
        case .custom: "Custom"
        }
    }
}

/// A live plot of one stick with a fading trail, so circling it shows its range. The dead zone
/// and full-output edge are drawn as rings.
private struct StickPlot: View {
    let position: StickPosition
    let live: Bool
    var deadZone: CGFloat = 0
    var edge: CGFloat = 1
    @ViewState private var trail: [CGPoint] = []

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - 6
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let rim = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.fill(rim, with: .color(.black.opacity(0.25)))
            ctx.stroke(rim, with: .color(Theme.stroke), lineWidth: 1)
            var cross = Path()
            cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
            ctx.stroke(cross, with: .color(Theme.stroke), lineWidth: 0.5)
            if deadZone > 0 {
                let d = r * deadZone
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - d, y: c.y - d, width: d * 2, height: d * 2)), with: .color(Theme.accent.opacity(0.18)))
            }
            if edge < 1 {
                let e = r * edge
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - e, y: c.y - e, width: e * 2, height: e * 2)),
                           with: .color(Theme.accent.opacity(0.6)), style: .init(lineWidth: 1, dash: [4, 4]))
            }
            for (i, p) in trail.enumerated() {
                let a = Double(i) / Double(max(1, trail.count))
                let q = CGPoint(x: c.x + p.x * r, y: c.y - p.y * r)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 1.5, y: q.y - 1.5, width: 3, height: 3)), with: .color(Theme.accent.opacity(0.15 + a * 0.5)))
            }
            let q = CGPoint(x: c.x + point.x * r, y: c.y - point.y * r)
            var g = ctx
            g.addFilter(.blur(radius: 6))
            g.fill(Path(ellipseIn: CGRect(x: q.x - 9, y: q.y - 9, width: 18, height: 18)), with: .color(Theme.glow.opacity(live ? 0.8 : 0)))
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - 6, y: q.y - 6, width: 12, height: 12)), with: .color(live ? Theme.glow : Theme.idle))
        }
        .onChange(of: position) { _, _ in
            trail.append(point)
            if trail.count > 240 { trail.removeFirst(trail.count - 240) }
        }
    }

    private var point: CGPoint { CGPoint(x: Double(position.x) / 32767, y: Double(position.y) / 32767) }
}
