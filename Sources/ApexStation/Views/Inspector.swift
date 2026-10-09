import ApexKit
import AppKit
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
        case .lighting: "Lighting"
        case .vibration: "Vibration"
        case .gyro: "Gyro"
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
        case .lighting, .vibration, .gyro: "Profile \((service.activeProfile ?? 0) + 1)"
        }
    }

    @ViewBuilder private var content: some View {
        switch control {
        case .key(.turbo):
            Note("Turbo is a controller shortcut: hold it and press another button to give that button turbo. The controller handles it itself, so it can't be remapped.")
        case .key(.fn):
            Note("Fn is a controller shortcut: with Fast Swap on, Fn plus A, B, X or Y switches between the four profiles. The controller handles it itself, so it can't be remapped.")
        case .key(let key) where key == .lt || key == .rt:
            ButtonPanel(key: key)
            TriggerPanel(left: key == .lt)
        case .key(let key):
            ButtonPanel(key: key)
        case .leftStick:
            StickPanel(left: true)
        case .rightStick:
            StickPanel(left: false)
        case .lighting:
            LightingPanel()
        case .vibration:
            VibrationPanel()
        case .gyro:
            GyroPanel()
        }
    }
}

struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Buttons

/// What a button does in the active profile: another button or a macro, and turbo.
private struct ButtonPanel: View {
    @Environment(ControllerService.self) private var service
    let key: FlydigiKey
    /// Shown while the user sets up a macro that isn't saved yet (`-composeMacro YES` opens it, for screenshots).
    @ViewState private var composingMacro = UserDefaults.standard.bool(forKey: "composeMacro")

    private var profile: Profile? { service.editingProfile }

    var body: some View {
        if let profile {
            let mapping = profile.mapping(for: key)
            let macro = profile.macros.first { $0.key == key }
            let showsMacro = macro != nil || composingMacro
            VStack(alignment: .leading, spacing: 10) {
                Caption("Acts as")
                ChipPicker(options: [false, true], selection: showsMacro, label: { $0 ? "Macro" : "Button" }) { wantsMacro in
                    if wantsMacro { composingMacro = true } else {
                        composingMacro = false
                        if macro != nil { Task { await service.removeMacro(on: key) } }
                    }
                }
                if !showsMacro {
                    PressToAssign(key: key, current: mapping)
                }
            }
            if showsMacro {
                let others = profile.macros.filter { $0.key != key }.count
                MacroEditor(key: key, saved: macro, slotsLeft: Profile.maxMacros - others) { composingMacro = false }
                    .id("\(profile.slot)-\(key)")
            } else {
                TurboSection(key: key, turbo: profile.turbo(for: key))
            }
            Text("Saved to profile \(profile.slot + 1) on the controller, so it works everywhere: wired, wireless and Switch mode.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.label).fixedSize(horizontal: false, vertical: true)
        } else {
            Note(service.connected ? "Reading the controller's profiles…" : "Connect your Apex 5 to change its buttons.")
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
                PressToAssign(key: key, current: profile.mapping(for: key))
            }
        }
        if let s = service.settings {
            VStack(alignment: .leading, spacing: 10) {
                Caption("Precision (bits) · both sticks")
                ChipPicker(options: [DeviceSettings.Precision.bits8, .bits9, .bits10, .bits11, .bits12], selection: s.precision, label: { "\($0.bits)" }) { p in
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

// MARK: - Sliders

/// A labelled slider that saves when the user lets go (not on every pixel of a drag).
private struct ValueSlider: View {
    let title: String
    let range: ClosedRange<Double>
    var unit = ""
    let value: Int
    let commit: (Int) -> Void
    @ViewState private var current: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption(title)
            HStack {
                // No step: macOS would draw a tick per step. Values are rounded instead.
                Slider(value: Binding(get: { current }, set: { current = $0.rounded() }), in: range) { editing in
                    if !editing { commit(Int(current)) }
                }
                Text("\(Int(current))\(unit)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondary).frame(width: 44, alignment: .trailing)
            }
        }
        .onAppear { current = Double(value) }
        .onChange(of: value) { _, v in current = Double(v) }
    }
}

// MARK: - Triggers

private struct TriggerPanel: View {
    @Environment(ControllerService.self) private var service
    let left: Bool

    private enum Mode: String, CaseIterable { case normal = "Normal", racing = "Racing", recoil = "Recoil", sniper = "Sniper", lock = "Lock", vibration = "Rumble" }

    var body: some View {
        if let t = service.editingProfile?.trigger(left: left) {
            VStack(alignment: .leading, spacing: 14) {
                ValueSlider(title: "Starts at", range: 0...200, unit: "", value: t.start) { v in save(t) { $0.start = v } }
                ValueSlider(title: "Full press at", range: 55...255, unit: "", value: t.end) { v in save(t) { $0.end = v } }
            }
            VStack(alignment: .leading, spacing: 10) {
                Caption("Force feedback")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        let on = mode(t.effect) == m
                        Button { save(t) { $0.effect = effect(for: m) } } label: {
                            Text(m.rawValue).font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .foregroundStyle(on ? .white : Theme.secondary)
                                .background(on ? Theme.accent : Color.white.opacity(0.06), in: .rect(cornerRadius: 9))
                                .bloom(on, radius: 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(describe(mode(t.effect))).font(.system(size: 11.5)).foregroundStyle(Theme.label).fixedSize(horizontal: false, vertical: true)
            }
            effectSliders(t)
        }
    }

    @ViewBuilder private func effectSliders(_ t: TriggerConfig) -> some View {
        switch t.effect {
        case .normal:
            EmptyView()
        case let .racing(start, damping):
            ValueSlider(title: "Resistance starts at", range: 0...192, value: start) { v in save(t) { $0.effect = .racing(start: v, damping: damping) } }
            ValueSlider(title: "Resistance", range: 1...255, value: damping) { v in save(t) { $0.effect = .racing(start: start, damping: v) } }
        case let .recoil(start, startForce, strength, frequency):
            ValueSlider(title: "Starts at", range: 0...192, value: start) { v in save(t) { $0.effect = .recoil(start: v, startForce: startForce, strength: strength, frequency: frequency) } }
            ValueSlider(title: "Strength", range: 1...255, value: strength) { v in save(t) { $0.effect = .recoil(start: start, startForce: startForce, strength: v, frequency: frequency) } }
            ValueSlider(title: "Rate", range: 1...255, value: frequency) { v in save(t) { $0.effect = .recoil(start: start, startForce: startForce, strength: strength, frequency: v) } }
        case let .sniper(start, stroke, resistance):
            ValueSlider(title: "Break point", range: 0...192, value: start) { v in save(t) { $0.effect = .sniper(start: v, stroke: stroke, resistance: resistance) } }
            ValueSlider(title: "Travel", range: 1...255, value: stroke) { v in save(t) { $0.effect = .sniper(start: start, stroke: v, resistance: resistance) } }
            ValueSlider(title: "Resistance", range: 1...255, value: resistance) { v in save(t) { $0.effect = .sniper(start: start, stroke: stroke, resistance: v) } }
        case let .lock(position):
            ValueSlider(title: "Stops at", range: 20...200, value: position) { v in save(t) { $0.effect = .lock(position: v) } }
        case let .vibration(threshold, scale, start, frequency):
            ValueSlider(title: "Strength", range: 0...200, value: scale) { v in save(t) { $0.effect = .vibration(threshold: threshold, scale: v, start: start, frequency: frequency) } }
            ValueSlider(title: "Ignore rumble below", range: 1...255, value: threshold) { v in save(t) { $0.effect = .vibration(threshold: v, scale: scale, start: start, frequency: frequency) } }
            ValueSlider(title: "Frequency", range: 1...255, value: frequency) { v in save(t) { $0.effect = .vibration(threshold: threshold, scale: scale, start: start, frequency: v) } }
        }
    }

    private func save(_ t: TriggerConfig, _ change: (inout TriggerConfig) -> Void) {
        var c = t
        change(&c)
        Task { await service.setTrigger(c, left: left) }
    }

    private func mode(_ e: TriggerEffect) -> Mode {
        switch e {
        case .normal: .normal
        case .racing: .racing
        case .recoil: .recoil
        case .sniper: .sniper
        case .lock: .lock
        case .vibration: .vibration
        }
    }

    private func effect(for m: Mode) -> TriggerEffect {
        switch m {
        case .normal: .normal
        case .racing: .racingDefault
        case .recoil: .recoilDefault
        case .sniper: .sniperDefault
        case .lock: .lockDefault
        case .vibration: .vibrationDefault
        }
    }

    private func describe(_ m: Mode) -> String {
        switch m {
        case .normal: "A plain trigger."
        case .racing: "Pushes back like a pedal, from a point you choose."
        case .recoil: "Buzzes rapidly past a point, like automatic fire."
        case .sniper: "Clicks through at a break point, like a heavy trigger."
        case .lock: "Stops the trigger partway, for faster presses."
        case .vibration: "The trigger shakes along with the game's rumble."
        }
    }
}

// MARK: - Vibration

private struct VibrationPanel: View {
    @Environment(ControllerService.self) private var service

    var body: some View {
        if let v = service.editingProfile?.vibration {
            SettingRow(title: "Rumble", detail: "Grip motors in games.") {
                GlowToggle(isOn: Binding(get: { v.enabled }, set: { on in save(v) { $0.enabled = on } }))
            }
            if v.enabled {
                ValueSlider(title: "Left motor (strong)", range: 0...100, unit: "%", value: v.left) { x in save(v) { $0.left = x } }
                ValueSlider(title: "Right motor (fine)", range: 0...100, unit: "%", value: v.right) { x in save(v) { $0.right = x } }
            }
            Button { Task { await service.testRumble() } } label: {
                Label("Test rumble", systemImage: "waveform").font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .glass(.capsule, tint: Theme.accent.opacity(0.35), interactive: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func save(_ v: VibrationConfig, _ change: (inout VibrationConfig) -> Void) {
        var c = v
        change(&c)
        Task { await service.setVibration(c) }
    }
}

// MARK: - Gyro

private struct GyroPanel: View {
    @Environment(ControllerService.self) private var service

    var body: some View {
        if let g = service.editingProfile?.gyro {
            VStack(alignment: .leading, spacing: 10) {
                Caption("Tilt moves")
                ChipPicker(options: GyroConfig.Target.allCases, selection: g.target, label: targetLabel) { t in save(g) { $0.target = t } }
            }
            if g.target != .off {
                if g.target != .mouse {
                    VStack(alignment: .leading, spacing: 10) {
                        Caption("Turned on by")
                        KeyPicker(selection: g.key) { k in save(g) { $0.key = k } }
                        ChipPicker(options: GyroConfig.Activation.allCases, selection: g.activation, label: { $0 == .hold ? "While held" : "Toggle" }) { a in
                            save(g) { $0.activation = a }
                        }
                    }
                    ValueSlider(title: "Dead zone", range: 0...50, value: g.deadZone) { v in save(g) { $0.deadZone = v } }
                }
                ValueSlider(title: "Sensitivity", range: 1...100, value: g.sensitivity) { v in save(g) { $0.sensitivity = v } }
                SettingRow(title: "Racing tilt", detail: "Steer by tilting instead of aiming.") {
                    GlowToggle(isOn: Binding(get: { g.racing }, set: { on in save(g) { $0.racing = on } }))
                }
                Text("Gyro lowers the controller's report rate while it's on.").font(.system(size: 11.5)).foregroundStyle(Theme.label)
            }
        }
    }

    private func save(_ g: GyroConfig, _ change: (inout GyroConfig) -> Void) {
        var c = g
        change(&c)
        Task { await service.setGyro(c) }
    }

    private func targetLabel(_ t: GyroConfig.Target) -> String {
        switch t {
        case .off: "Off"
        case .leftStick: "Left stick"
        case .rightStick: "Right stick"
        case .mouse: "Mouse"
        }
    }
}

// MARK: - Lighting

private struct LightingPanel: View {
    @Environment(ControllerService.self) private var service
    @ViewState private var picked = Color.blue

    private static let swatches: [Lighting.Color] = [
        .init(r: 0x3E, g: 0x85, b: 0xF6), .init(r: 0, g: 0xF0, b: 0xFF), .init(r: 0x9B, g: 0x5C, b: 0xFF), .init(r: 0xFF, g: 0x2D, b: 0x95),
        .init(r: 0xFF, g: 0x3B, b: 0x30), .init(r: 0xFF, g: 0x95, b: 0x00), .init(r: 0x34, g: 0xC7, b: 0x59), .init(r: 0xFF, g: 0xFF, b: 0xFF),
    ]

    var body: some View {
        if let l = service.editingLighting {
            VStack(alignment: .leading, spacing: 10) {
                Caption("Mode")
                ChipPicker(options: [Lighting.Mode.standard, .steady, .breathing, .off], selection: l.mode, label: modeLabel) { m in
                    Task {
                        await service.editLighting { light in
                            switch m {
                            case .standard: light.setStandard(frames: Lighting.factoryFrames, loopEnd: 9)
                            case .off: light.setOff()
                            default: light.setColor(l.mode == .standard ? Self.swatches[0] : l.color, mode: m)
                            }
                        }
                    }
                }
            }
            if l.mode == .steady || l.mode == .breathing {
                VStack(alignment: .leading, spacing: 10) {
                    Caption("Colour")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                        ForEach(Self.swatches, id: \.self) { c in
                            let on = c == l.color
                            Button { setColor(c, l) } label: {
                                Circle().fill(Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255))
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: on ? 2 : 0))
                                    .shadow(color: Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255).opacity(on ? 0.8 : 0), radius: 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ColorPicker("Custom colour", selection: Binding(get: { picked }, set: { new in
                        picked = new
                        if let c = NSColor(new).usingColorSpace(.sRGB) {
                            setColor(.init(r: UInt8(c.redComponent * 255), g: UInt8(c.greenComponent * 255), b: UInt8(c.blueComponent * 255)), l)
                        }
                    }), supportsOpacity: false)
                    .font(.system(size: 12.5))
                }
            }
            if l.mode != .off {
                ValueSlider(title: "Brightness", range: 0...100, unit: "%", value: l.brightness) { v in Task { await service.editLighting { $0.setBrightness(v) } } }
                if l.mode != .steady {
                    ValueSlider(title: "Cycle time", range: 1...100, value: l.speed) { v in Task { await service.editLighting { $0.setSpeed(v) } } }
                }
            }
        } else {
            Text(service.connected ? "Reading the lighting…" : "Connect your Apex 5 to change its lighting.").foregroundStyle(Theme.secondary)
        }
    }

    private func setColor(_ c: Lighting.Color, _ l: Lighting) {
        Task { await service.editLighting { $0.setColor(c, mode: l.mode == .breathing ? .breathing : .steady) } }
    }

    private func modeLabel(_ m: Lighting.Mode) -> String {
        switch m {
        case .standard: "Default"
        case .steady: "Steady"
        case .breathing: "Breathing"
        case .off: "Off"
        default: "\(m)"
        }
    }
}

/// Picks one button (for things like "gyro turns on with…").
private struct KeyPicker: View {
    let selection: FlydigiKey?
    let pick: (FlydigiKey) -> Void
    private let keys: [FlydigiKey] = [.lt, .rt, .lb, .rb, .l3, .r3, .a, .b, .x, .y, .lm, .rm, .m1, .m2, .m3, .m4]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(keys, id: \.self) { k in
                let on = k == selection
                Button { pick(k) } label: {
                    Text(k.name).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(on ? .white : Theme.secondary)
                        .background(on ? Theme.accent : Color.white.opacity(0.06), in: .rect(cornerRadius: 9))
                        .bloom(on, radius: 8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension FlydigiKey {
    /// A compact label for chips: arrows for the d-pad.
    var shortName: String {
        switch self {
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        default: name
        }
    }
}
