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
                VStack(alignment: .leading, spacing: 22) {
                    if !service.connected, control != .test { Note(service.cableNote("this")) }
                    content
                }
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
        case .screen: "Screen"
        case .test: "Input test"
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
        case .screen: "Display"
        case .test: "Controller"
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
        case .screen:
            ScreenPanel()
        case .test:
            TestPanel()
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
    /// Shown while the user picks a key that isn't set yet.
    @ViewState private var composingKey = false

    private enum ActsAs: Hashable { case button, macro, key }

    private var profile: Profile? { service.editingProfile }

    var body: some View {
        if let profile {
            let mapping = profile.mapping(for: key)
            let macro = profile.macros.first { $0.key == key }
            let hasKey = service.keyboardMouseMap[key] != nil
            let mode: ActsAs = macro != nil || composingMacro ? .macro : hasKey || composingKey ? .key : .button
            VStack(alignment: .leading, spacing: 10) {
                Caption("Acts as")
                ChipPicker(options: [ActsAs.button, .macro, .key], selection: mode, label: actsAsLabel) { wanted in
                    composingMacro = wanted == .macro
                    composingKey = wanted == .key
                    if wanted != .macro, macro != nil { Task { await service.removeMacro(on: key) } }
                    if wanted != .key, hasKey { service.editKeyboardMouse { $0[key] = nil } }
                }
                if mode == .button {
                    PressToAssign(key: key, current: mapping)
                }
            }
            switch mode {
            case .macro:
                let others = profile.macros.filter { $0.key != key }.count
                MacroEditor(key: key, saved: macro, slotsLeft: Profile.maxMacros - others) { composingMacro = false }
                    .id("\(profile.slot)-\(key)")
            case .key:
                KeyAssign(key: key)
            case .button:
                TurboSection(key: key, turbo: profile.turbo(for: key))
            }
            if mode != .key {
                Text("Saved to profile \(profile.slot + 1) on the controller, so it works everywhere: wired, wireless and Switch mode.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.label).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            if service.connected { Note("Reading the controller's profiles…") }
        }
    }

    private func actsAsLabel(_ m: ActsAs) -> String {
        switch m {
        case .button: "Button"
        case .macro: "Macro"
        case .key: "Key"
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
        let position = left ? service.state.leftStick : service.state.rightStick
        StickPlot(position: position, live: service.live,
                  deadZone: CGFloat(max(config?.deadZone ?? 0, 0)) / 100, edge: CGFloat(100 - max(config?.edge ?? 0, 0)) / 100)
        if let config { StickShape(config: config, left: left, position: position, live: service.live) }
        StickActsAs(left: left)
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

/// Response curve and shape for one stick, stored in the active profile.
private struct StickShape: View {
    @Environment(ControllerService.self) private var service
    let config: StickConfig
    let left: Bool
    let position: StickPosition
    let live: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption("Response")
            ChipPicker(options: StickConfig.Curve.allCases, selection: config.curve, label: curveLabel) { c in
                // Like Space Station, a preset starts clean: no dead zone or edge.
                guard c != .custom else { return }
                save(StickConfig(curve: c, circular: config.circular))
            }
            CurveEditor(config: config, position: position, live: live) { save($0) }
                .frame(height: 230)
        }
        VStack(alignment: .leading, spacing: 10) {
            Caption("Shape")
            ChipPicker(options: [false, true], selection: config.circular, label: { $0 ? "Circle" : "Square" }) { c in
                var new = config
                new.circular = c
                save(new)
            }
        }
    }

    private func save(_ new: StickConfig) {
        Task { await service.setStick(new, left: left) }
    }

    private func curveLabel(_ c: StickConfig.Curve) -> String {
        switch c {
        case .standard: "Default"
        case .quick: "Instant"
        case .slow: "Delay"
        case .custom: "Custom"
        }
    }
}

/// The stick's response curve: travel across, output up. Drag the first point right for a dead
/// zone or up for an anti-dead zone, the last point left to reach full output early or down to
/// cap it, and the two middle points to bend the curve. The filled line is what the controller
/// actually follows (its nine stored samples); the dot is the stick right now.
struct CurveEditor: View {
    let config: StickConfig
    let position: StickPosition
    let live: Bool
    let commit: (StickConfig) -> Void

    private enum Handle { case start, bend1, bend2, end }
    @ViewState private var draft: StickConfig?
    @ViewState private var dragging: Handle?

    private var shown: StickConfig { draft ?? config }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let box = CGRect(origin: .zero, size: geo.size).insetBy(dx: 10, dy: 10)
                Canvas { ctx, _ in draw(&ctx, in: box) }
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag(to: $0.location, from: $0.startLocation, in: box) }
                        .onEnded { _ in
                            if let draft, draft != config { commit(draft) }
                            dragging = nil
                        })
            }
            .background(Color.black.opacity(0.25), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
            Text(readout).font(.system(size: 11.5)).foregroundStyle(Theme.label)
        }
        .onChange(of: config) { _, _ in if dragging == nil { draft = nil } }
    }

    private var readout: String {
        let c = shown
        let dead = c.deadZone > 0 ? "Dead zone \(c.deadZone)%" : c.deadZone < 0 ? "Anti-dead zone \(-c.deadZone)%" : "No dead zone"
        let edge = c.edge > 0 ? "full output at \(100 - c.edge)%" : c.edge < 0 ? "output capped at \(100 + c.edge)%" : "full output at the rim"
        return "\(dead) · \(edge). Drag the points to change it."
    }

    // MARK: Drawing

    private func at(_ x: Double, _ y: Double, _ box: CGRect) -> CGPoint {
        CGPoint(x: box.minX + box.width * x / 100, y: box.maxY - box.height * y / 100)
    }

    private func draw(_ ctx: inout GraphicsContext, in box: CGRect) {
        var grid = Path()
        for f in [25.0, 50, 75] {
            grid.move(to: at(f, 0, box)); grid.addLine(to: at(f, 100, box))
            grid.move(to: at(0, f, box)); grid.addLine(to: at(100, f, box))
        }
        ctx.stroke(grid, with: .color(Theme.stroke), lineWidth: 0.5)
        var diagonal = Path()
        diagonal.move(to: at(0, 0, box)); diagonal.addLine(to: at(100, 100, box))
        ctx.stroke(diagonal, with: .color(.white.opacity(0.08)), style: .init(lineWidth: 1, dash: [3, 4]))

        // What the controller follows: its nine samples, no output below zero.
        let samples = shown.samples
        var curve = Path()
        for (i, y) in samples.enumerated() {
            let p = at(100 * Double(i) / 8, Double(max(0, y)), box)
            i == 0 ? curve.move(to: p) : curve.addLine(to: p)
        }
        var fill = curve
        fill.addLine(to: at(100, 0, box)); fill.addLine(to: at(0, 0, box)); fill.closeSubpath()
        ctx.fill(fill, with: .linearGradient(Gradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)]),
                                             startPoint: CGPoint(x: box.midX, y: box.minY), endPoint: CGPoint(x: box.midX, y: box.maxY)))
        ctx.stroke(curve, with: .color(Theme.glow), style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // The line the points define, and the points themselves.
        let line = shown.polyline
        var guide = Path()
        guide.addLines(line.map { at($0.x, $0.y, box) })
        ctx.stroke(guide, with: .color(.white.opacity(0.25)), style: .init(lineWidth: 1, dash: [2, 3]))
        for (handle, p) in zip([Handle.start, .bend1, .bend2, .end], line) {
            let q = at(p.x, p.y, box), r: CGFloat = dragging == handle ? 7 : 5.5
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)), with: .color(Theme.accent))
            ctx.stroke(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        }

        // The stick now: how far it's pushed, and what that outputs.
        if live {
            let travel = min(100, hypot(Double(position.x), Double(position.y)) / 32767 * 100)
            let i = min(7, Int(travel / 12.5)), t = (travel - Double(i) * 12.5) / 12.5
            let out = max(0, Double(samples[i]) + (Double(samples[i + 1]) - Double(samples[i])) * t)
            let q = at(travel, out, box)
            var g = ctx
            g.addFilter(.blur(radius: 5))
            g.fill(Path(ellipseIn: CGRect(x: q.x - 8, y: q.y - 8, width: 16, height: 16)), with: .color(Theme.glow.opacity(0.8)))
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)), with: .color(.white))
        }
    }

    // MARK: Dragging

    private func drag(to location: CGPoint, from start: CGPoint, in box: CGRect) {
        let x = min(100, max(0, (location.x - box.minX) / box.width * 100))
        let y = min(100, max(0, (box.maxY - location.y) / box.height * 100))
        if dragging == nil {
            // Grab the point nearest to where the drag began.
            let line = shown.polyline
            let handles: [Handle] = [.start, .bend1, .bend2, .end]
            let nearest = zip(handles, line).min { a, b in
                hypot(at(a.1.x, a.1.y, box).x - start.x, at(a.1.x, a.1.y, box).y - start.y) <
                    hypot(at(b.1.x, b.1.y, box).x - start.x, at(b.1.x, b.1.y, box).y - start.y)
            }
            guard let nearest, hypot(at(nearest.1.x, nearest.1.y, box).x - start.x, at(nearest.1.x, nearest.1.y, box).y - start.y) < 22 else { return }
            dragging = nearest.0
            draft = config
        }
        guard var c = draft, let handle = dragging else { return }
        c.curve = .custom
        switch handle {
        case .start:
            // Along the bottom is a dead zone, up the left side an anti-dead zone.
            c.deadZone = x >= y ? Int(x.rounded()) : -Int(y.rounded())
            c.deadZone = min(max(c.deadZone, -60), 60)
            if c.deadZone > 0, c.edge > 0 { c.deadZone = min(c.deadZone, 95 - c.edge) }
        case .end:
            // Along the top reaches full output early, down the right side caps it.
            let dx = 100 - x, dy = 100 - y
            c.edge = dx >= dy ? Int(dx.rounded()) : -Int(dy.rounded())
            c.edge = min(max(c.edge, -60), 60)
            if c.edge > 0, c.deadZone > 0 { c.edge = min(c.edge, 95 - c.deadZone) }
        case .bend1, .bend2:
            let line = c.polyline, s = line[0], e = line[3]
            let px = e.x > s.x ? Int(((x - s.x) / (e.x - s.x) * 127).rounded()) : 0
            let py = e.y > s.y ? Int(((y - s.y) / (e.y - s.y) * 127).rounded()) : 0
            var p = StickConfig.Point(x: min(127, max(0, px)), y: min(127, max(0, py)))
            if handle == .bend1 {
                p.x = min(p.x, c.point2.x)
                c.point1 = p
            } else {
                p.x = max(p.x, c.point1.x)
                c.point2 = p
            }
        }
        draft = c
    }
}

/// A live plot of one stick with a fading trail, so circling it shows its range. The dead zone
/// and full-output edge are drawn as rings. The circularity test (like Space Station's) records
/// how far the stick reaches in every direction while you spin it along the rim.
private struct StickPlot: View {
    let position: StickPosition
    let live: Bool
    var deadZone: CGFloat = 0
    var edge: CGFloat = 1
    @ViewState private var trail: [CGPoint] = []
    /// Furthest reach in each 5° direction during the test; nil when not testing.
    @ViewState private var reach: [Double]?

    private static let bins = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { ctx, size in draw(&ctx, size) }
                .frame(height: 200)
            HStack(spacing: 10) {
                Button {
                    reach = reach == nil ? Array(repeating: 0, count: Self.bins) : nil
                } label: {
                    Label(reach == nil ? "Test circularity" : "Stop test", systemImage: reach == nil ? "circle.dashed" : "stop.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .glass(.capsule, interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(!live)
                Text(testReadout).font(.system(size: 11.5)).foregroundStyle(Theme.label).monospacedDigit()
            }
        }
        .onChange(of: position) { _, _ in
            trail.append(point)
            if trail.count > 240 { trail.removeFirst(trail.count - 240) }
            record()
        }
    }

    private var testReadout: String {
        guard let reach else { return live ? "" : "Needs live input." }
        let seen = reach.filter { $0 > 0.5 }
        guard seen.count >= Self.bins / 2 else { return "Spin the stick slowly along the rim." }
        let error = seen.map { abs($0 - 1) }.reduce(0, +) / Double(seen.count) * 100
        let offset = hypot(point.x, point.y) * 100
        return String(format: "Avg error %.1f%% · %d%% covered · resting %.1f%% off centre", error, seen.count * 100 / Self.bins, offset)
    }

    private func record() {
        guard var r = reach else { return }
        let p = point, d = hypot(p.x, p.y)
        guard d > 0.5 else { return }
        let bin = Int(((atan2(p.y, p.x) + .pi) / (2 * .pi) * Double(Self.bins)).rounded(.down)) % Self.bins
        if d > r[bin] { r[bin] = d; reach = r }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
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
        if let reach {
            // The outline the stick actually reached, against the rim.
            var shape = Path()
            for (i, d) in reach.enumerated() where d > 0.5 {
                let a = (Double(i) + 0.5) / Double(Self.bins) * 2 * .pi - .pi
                let q = CGPoint(x: c.x + cos(a) * d * r, y: c.y - sin(a) * d * r)
                shape.isEmpty ? shape.move(to: q) : shape.addLine(to: q)
            }
            ctx.stroke(shape, with: .color(Theme.glow), style: .init(lineWidth: 1.5, lineJoin: .round))
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

    private var point: CGPoint { CGPoint(x: Double(position.x) / 32767, y: Double(position.y) / 32767) }
}

// MARK: - Sliders

/// A labelled slider that saves when the user lets go (not on every pixel of a drag).
struct ValueSlider: View {
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
                    ValueSlider(title: "Stick dead zone offset", range: 0...50, value: g.deadZone) { v in save(g) { $0.deadZone = v } }
                    Text("Starts the stick past the game's own dead zone, so small tilts register.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.label)
                }
                ValueSlider(title: "Sensitivity", range: 1...100, value: g.sensitivity) { v in save(g) { $0.sensitivity = v } }
                if g.target == .mouse {
                    Text("Turning the controller moves the pointer, done by Apex Station like Space Station does on Windows.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.label).fixedSize(horizontal: false, vertical: true)
                    KeyboardMouseStatus()
                }
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
            SettingRow(title: "Vibration light effect", detail: "The lights flash along when the grips vibrate.") {
                GlowToggle(isOn: Binding(get: { l.gripSync }, set: { on in Task { await service.editLighting { $0.setGripSync(on) } } }))
            }
            if l.mode != .off {
                ValueSlider(title: "Brightness", range: 0...100, unit: "%", value: l.brightness) { v in Task { await service.editLighting { $0.setBrightness(v) } } }
                if l.mode != .steady {
                    ValueSlider(title: "Cycle time", range: 1...100, value: l.speed) { v in Task { await service.editLighting { $0.setSpeed(v) } } }
                }
            }
        } else {
            if service.connected { Text("Reading the lighting…").foregroundStyle(Theme.secondary) }
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
