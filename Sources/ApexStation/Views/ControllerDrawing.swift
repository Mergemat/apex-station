import ApexKit
import AppKit
import CoreText
import SwiftUI

struct ControllerDrawing: View {
    let state: GamepadState
    let live: Bool
    /// When set, remapped buttons get a small "→ target" tag.
    var profile: Profile? = nil
    var selected: ControllerControl? = nil
    var hovered: ControllerControl? = nil

    private static let space = CGSize(width: 500, height: 520)

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / Self.space.width, size.height / Self.space.height)
            ctx.translateBy(x: (size.width - Self.space.width * s) / 2, y: (size.height - Self.space.height * s) / 2)
            ctx.scaleBy(x: s, y: s)
            draw(&ctx)
        }
        .accessibilityLabel("Live view of the controller")
    }

    private var b: GamepadButtons { live ? state.buttons : [] }
    private typealias L = ControllerLayout

    /// Maps a point in the view to the control under it.
    static func control(at point: CGPoint, in size: CGSize) -> ControllerControl? {
        let s = min(size.width / space.width, size.height / space.height)
        let p = CGPoint(x: (point.x - (size.width - space.width * s) / 2) / s, y: (point.y - (size.height - space.height * s) / 2) / s)
        // Small controls first, so the d-pad wins over the shell behind it.
        return ControllerLayout.regions.sorted { $0.value.boundingRect.width * $0.value.boundingRect.height < $1.value.boundingRect.width * $1.value.boundingRect.height }
            .first { $0.value.contains(p) || $0.value.strokedPath(.init(lineWidth: 6)).contains(p) }?.key
    }

    private func draw(_ ctx: inout GraphicsContext) {
        // Shoulder row above the body: triggers fill with how far they're pulled.
        trigger(&ctx, L.lt, "LT", live ? state.leftTrigger : 0)
        trigger(&ctx, L.rt, "RT", live ? state.rightTrigger : 0)
        key(&ctx, L.lm, "LM", b.contains(.leftMacro))
        key(&ctx, L.rm, "RM", b.contains(.rightMacro))

        // The bumpers sit behind the body; only their tops show.
        bumper(&ctx, L.bumperLeft, on: b.contains(.leftBumper))
        bumper(&ctx, L.bumperRight, on: b.contains(.rightBumper))
        shell(&ctx)
        ctx.fill(L.faceplate, with: .color(.black.opacity(0.18)))
        lightBar(&ctx)
        screen(&ctx)

        // Button faces, lit when pressed; the line art goes over them.
        let buttons: [(ControllerControl, Bool)] = [
            (.key(.a), b.contains(.a)), (.key(.b), b.contains(.b)), (.key(.x), b.contains(.x)), (.key(.y), b.contains(.y)),
            (.key(.view), b.contains(.back)), (.key(.menu), b.contains(.start)), (.key(.home), b.contains(.guide)),
            (.key(.up), b.contains(.dpadUp)), (.key(.down), b.contains(.dpadDown)),
            (.key(.left), b.contains(.dpadLeft)), (.key(.right), b.contains(.dpadRight)),
        ]
        let regions = L.regions
        let arms: [ControllerControl] = [.key(.up), .key(.down), .key(.left), .key(.right)]
        // The cross as one piece, so its middle matches the arms.
        ctx.fill(L.dpadCross, with: .color(.white.opacity(0.06)))
        for (control, on) in buttons {
            guard let p = regions[control] else { continue }
            if on { glow(&ctx, p) } else if control != .key(.home) && !arms.contains(control) { ctx.fill(p, with: .color(.white.opacity(0.06))) }
        }
        stick(&ctx, left: true, live ? state.leftStick : .init(), b.contains(.leftStick))
        stick(&ctx, left: false, live ? state.rightStick : .init(), b.contains(.rightStick))
        ctx.fill(L.lines, with: .color(.white.opacity(0.32)))
        // Pressed controls get bright lines.
        for (control, on) in buttons where on {
            guard let p = regions[control] else { continue }
            var lit = ctx
            lit.clip(to: p)
            lit.fill(L.lines, with: .color(.white))
        }
        label(&ctx, "LB", at: ControllerArt.lbLabel, size: 8, color: b.contains(.leftBumper) ? .white : .white.opacity(0.8))
        label(&ctx, "RB", at: ControllerArt.rbLabel, size: 8, color: b.contains(.rightBumper) ? .white : .white.opacity(0.8))

        // Back: paddles under the grip they sit on, Turbo and Fn in the middle.
        caption(&ctx, "BACK", CGPoint(x: 250, y: 452))
        for (shape, name, on) in [(L.m2, "M2", b.contains(.m2)), (L.m4, "M4", b.contains(.m4)),
                                  (L.m1, "M1", b.contains(.m1)), (L.m3, "M3", b.contains(.m3))] {
            key(&ctx, shape, name, on)
        }
        key(&ctx, Path(roundedRect: L.turbo, cornerRadius: L.turbo.height / 2), "TURBO", b.contains(.turbo), small: true)
        key(&ctx, Path(roundedRect: L.fn, cornerRadius: L.fn.height / 2), "FN", b.contains(.fn), small: true)

        overlays(&ctx)
    }

    // MARK: - Interaction overlays

    /// Hover and selection rings, and "→ target" tags on remapped buttons.
    private func overlays(_ ctx: inout GraphicsContext) {
        let regions = L.regions
        if let hovered, hovered != selected, let p = regions[hovered] {
            ctx.stroke(p, with: .color(.white.opacity(0.55)), lineWidth: 1.6)
        }
        if let selected, let p = regions[selected] {
            var g = ctx
            g.addFilter(.blur(radius: 6))
            g.stroke(p, with: .color(Theme.glow), lineWidth: 5)
            ctx.stroke(p, with: .color(.white), lineWidth: 2)
        }
        guard let profile else { return }
        for (key, mapping) in profile.remapped {
            guard let p = regions[ControllerControl(key)] else { continue }
            let text: String = switch mapping {
            case .button(let k): "→ " + k.name
            case .macro: "MACRO"
            case .keyboardOrMouse: "KEY"
            default: "•"
            }
            tag(&ctx, text, near: p.boundingRect)
        }
    }

    /// A small pill just outside a control's top-right corner.
    private func tag(_ ctx: inout GraphicsContext, _ text: String, near r: CGRect) {
        let width = CGFloat(text.count) * 6 + 12
        let pill = CGRect(x: r.maxX - width / 2, y: r.minY - 11, width: width, height: 15)
        let shape = Path(roundedRect: pill, cornerRadius: 7.5)
        var g = ctx
        g.addFilter(.blur(radius: 5))
        g.fill(shape, with: .color(Theme.accent.opacity(0.6)))
        ctx.fill(shape, with: .color(Theme.accent))
        label(&ctx, text, at: CGPoint(x: pill.midX, y: pill.midY), size: 8, color: .white)
    }

    // MARK: - Body

    private func shell(_ ctx: inout GraphicsContext) {
        let body = L.body, top = body.boundingRect.minY, bottom = body.boundingRect.maxY
        var shadow = ctx
        shadow.addFilter(.blur(radius: 24))
        shadow.translateBy(x: 0, y: 16)
        shadow.fill(body, with: .color(.black.opacity(0.4)))
        ctx.fill(body, with: .linearGradient(Gradient(colors: [.white.opacity(0.15), .white.opacity(0.05)]),
                                             startPoint: CGPoint(x: 250, y: top), endPoint: CGPoint(x: 250, y: bottom)))
    }

    private func bumper(_ ctx: inout GraphicsContext, _ shape: Path, on: Bool) {
        let r = shape.boundingRect
        if on {
            glow(&ctx, shape)
        } else {
            ctx.fill(shape, with: .linearGradient(Gradient(colors: [.white.opacity(0.24), .white.opacity(0.11)]),
                                                  startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        }
    }

    /// The light bar along the arch between the grips: glows while the controller is live.
    private func lightBar(_ ctx: inout GraphicsContext) {
        guard live else { return }
        var g = ctx
        g.addFilter(.blur(radius: 6))
        g.stroke(L.arch, with: .color(Theme.accent), lineWidth: 5)
        ctx.fill(L.arch, with: .color(Theme.glow))
    }

    /// The controller's own screen, showing which profile is active.
    private func screen(_ ctx: inout GraphicsContext) {
        let screen = Path(roundedRect: L.screen, cornerRadius: 3)
        ctx.fill(screen, with: .linearGradient(Gradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.16), Color(red: 0.02, green: 0.03, blue: 0.07)]),
                                               startPoint: CGPoint(x: 0, y: L.screen.minY), endPoint: CGPoint(x: 0, y: L.screen.maxY)))
        ctx.stroke(screen, with: .color(.white.opacity(0.18)), lineWidth: 0.8)
        if let profile {
            label(&ctx, "P\(profile.slot + 1)", at: CGPoint(x: L.screen.midX, y: L.screen.midY), size: 11, weight: .bold,
                  color: Theme.glow.opacity(0.9))
        }
    }

    // MARK: - Controls

    /// A lit control: blue glow and gradient.
    private func glow(_ ctx: inout GraphicsContext, _ p: Path) {
        var g = ctx
        g.addFilter(.blur(radius: 9))
        g.fill(p, with: .color(Theme.accent.opacity(0.9)))
        ctx.fill(p, with: .linearGradient(Gradient(colors: [Theme.glow, Theme.accent]),
                                          startPoint: p.boundingRect.origin, endPoint: CGPoint(x: p.boundingRect.maxX, y: p.boundingRect.maxY)))
    }

    private func key(_ ctx: inout GraphicsContext, _ p: Path, _ text: String, _ on: Bool, small: Bool = false) {
        if on { glow(&ctx, p) } else { ctx.fill(p, with: .color(.white.opacity(0.08))) }
        ctx.stroke(p, with: .color(.white.opacity(on ? 0.55 : 0.22)), lineWidth: 0.9)
        label(&ctx, text, at: CGPoint(x: p.boundingRect.midX, y: p.boundingRect.midY), size: small ? 7.5 : 11,
              color: on ? .white : .white.opacity(0.6))
    }

    /// A trigger fills from the bottom up as it's pulled.
    private func trigger(_ ctx: inout GraphicsContext, _ p: Path, _ text: String, _ value: UInt8) {
        let r = p.boundingRect
        ctx.fill(p, with: .color(.white.opacity(0.08)))
        let f = CGFloat(value) / 255
        if f > 0 {
            var inner = ctx
            inner.clip(to: p)
            let level = Path(CGRect(x: r.minX, y: r.maxY - r.height * f, width: r.width, height: r.height * f))
            var g = inner
            g.addFilter(.blur(radius: 6))
            g.fill(level, with: .color(Theme.accent))
            inner.fill(level, with: .linearGradient(Gradient(colors: [Theme.accent, Theme.glow]),
                                                    startPoint: CGPoint(x: r.midX, y: r.maxY), endPoint: CGPoint(x: r.midX, y: r.minY)))
        }
        ctx.stroke(p, with: .color(.white.opacity(f > 0 ? 0.5 : 0.22)), lineWidth: 0.9)
        label(&ctx, text, at: CGPoint(x: r.midX, y: r.midY + 3), size: 11, color: f > 0.4 ? .white : .white.opacity(0.65))
    }

    /// A stick: its well, and the cap (with the drawing's ribs) moved where the stick is pushed.
    private func stick(_ ctx: inout GraphicsContext, left: Bool, _ pos: StickPosition, _ clicked: Bool) {
        let c = left ? L.leftStick : L.rightStick
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - L.stickRadius, y: c.y - L.stickRadius, width: L.stickRadius * 2, height: L.stickRadius * 2)),
                 with: .color(.black.opacity(0.28)))
        let travel = L.stickRadius - L.capRadius - 2
        // Up-positive Y; screen Y grows downwards.
        let dx = CGFloat(pos.x) / 32767 * travel, dy = -CGFloat(pos.y) / 32767 * travel
        let moved = abs(Int(pos.x)) > 3000 || abs(Int(pos.y)) > 3000
        let cap = Path(ellipseIn: CGRect(x: c.x + dx - L.capRadius, y: c.y + dy - L.capRadius, width: L.capRadius * 2, height: L.capRadius * 2))
        if clicked { glow(&ctx, cap) } else { ctx.fill(cap, with: .color(Color(red: 0.16, green: 0.18, blue: 0.24))) }
        let lines = (left ? L.leftCap : L.rightCap).applying(CGAffineTransform(translationX: dx, y: dy))
        ctx.fill(lines, with: .color(.white.opacity(clicked ? 0.95 : moved ? 0.7 : 0.4)))
        if moved && !clicked { ctx.stroke(cap, with: .color(Theme.glow.opacity(0.85)), lineWidth: 1.5) }
    }

    private func caption(_ ctx: inout GraphicsContext, _ text: String, _ at: CGPoint) {
        label(&ctx, text, at: at, size: 9, weight: .semibold, tracking: 2.4, color: Theme.label)
    }

    // MARK: - Labels

    /// Draws `text` with its visible letters exactly centred on `p`. The letters are drawn from
    /// their vector outlines and centred by those outlines, so side bearings, descender space and
    /// tracking can't push them off centre at any size.
    private func label(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat,
                       weight: Font.Weight = .bold, tracking: CGFloat = 0, color: Color) {
        let glyphs = LabelGlyphs.path(text, size: size, weight: weight, tracking: tracking)
        let box = glyphs.boundingRect
        ctx.fill(glyphs.applying(.init(translationX: p.x - box.midX, y: p.y - box.midY)), with: .color(color))
    }
}

/// Text turned into outlines (y down, origin on the baseline), cached because the canvas
/// redraws every frame.
@MainActor
private enum LabelGlyphs {
    private static var cache: [String: Path] = [:]

    static func path(_ text: String, size: CGFloat, weight: Font.Weight, tracking: CGFloat) -> Path {
        let key = "\(text)|\(size)|\(weight)|\(tracking)"
        if let hit = cache[key] { return hit }
        let ns: NSFont.Weight = switch weight {
        case .heavy: .heavy
        case .semibold: .semibold
        case .medium: .medium
        case .regular: .regular
        default: .bold
        }
        let base = NSFont.systemFont(ofSize: size, weight: ns)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: tracking]))
        let outline = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (g, pos) in zip(glyphs, positions) {
                guard let glyph = CTFontCreatePathForGlyph(runFont, g, nil) else { continue }
                // CoreText is y-up; flip into the canvas's y-down space.
                outline.addPath(glyph, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: pos.x, ty: -pos.y))
            }
        }
        let result = Path(outline)
        cache[key] = result
        return result
    }

}

/// Something on the controller the user can click to configure.
enum ControllerControl: Hashable {
    case key(FlydigiKey)
    case leftStick
    case rightStick
    case lighting
    case vibration
    case gyro
    case screen
    case test

    /// Sticks are selected as a whole; their click (L3/R3) is configured from the stick panel.
    init(_ key: FlydigiKey) {
        switch key {
        case .l3: self = .leftStick
        case .r3: self = .rightStick
        default: self = .key(key)
        }
    }
}


@MainActor
enum ControllerLayout {
    static let bodyTop: CGFloat = 74

    // The parts above and below the body, shaped like the parts themselves (right side; the
    // left mirrors it): a trigger tab with a rounded top, a slanted LM/RM key, angular paddles.
    static let rt: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 352, y: 56))
        p.addLine(to: CGPoint(x: 353, y: 26))
        p.addQuadCurve(to: CGPoint(x: 380, y: 6), control: CGPoint(x: 354, y: 6))
        p.addQuadCurve(to: CGPoint(x: 410, y: 52), control: CGPoint(x: 408, y: 8))
        p.addQuadCurve(to: CGPoint(x: 404, y: 56), control: CGPoint(x: 411, y: 56))
        p.closeSubpath()
        return p
    }()
    static let rm = rounded([CGPoint(x: 302, y: 20), CGPoint(x: 342, y: 20), CGPoint(x: 334, y: 50), CGPoint(x: 294, y: 50)], 5)
    static let m1 = rounded([CGPoint(x: 370, y: 446), CGPoint(x: 424, y: 444), CGPoint(x: 460, y: 460),
                             CGPoint(x: 446, y: 474), CGPoint(x: 360, y: 472)], 6)
    static let m3 = rounded([CGPoint(x: 362, y: 480), CGPoint(x: 430, y: 482), CGPoint(x: 444, y: 488),
                             CGPoint(x: 460, y: 498), CGPoint(x: 450, y: 512), CGPoint(x: 364, y: 512)], 6)
    static let lt = mirrored(rt), lm = mirrored(rm), m2 = mirrored(m1), m4 = mirrored(m3)
    static let turbo = CGRect(x: 196, y: 476, width: 50, height: 22)
    static let fn = CGRect(x: 254, y: 476, width: 50, height: 22)

    static let body = Path(polygon: ControllerArt.body)
    /// The parts of the bumpers that show above the body.
    static let bumperLeft = Path(Path(polygon: ControllerArt.bumperLeft).cgPath.subtracting(body.cgPath))
    static let bumperRight = Path(Path(polygon: ControllerArt.bumperRight).cgPath.subtracting(body.cgPath))
    static let faceplate = Path(polygon: ControllerArt.faceplate)
    static let screen = ControllerArt.screen
    static let leftStick = ControllerArt.leftStick.center, rightStick = ControllerArt.rightStick.center
    static let stickRadius = ControllerArt.leftStick.radius, capRadius = ControllerArt.leftCap.radius
    static let a = ControllerArt.a.center, b = ControllerArt.b.center, x = ControllerArt.x.center, y = ControllerArt.y.center
    static let faceRadius = ControllerArt.a.radius
    static let dpad = ControllerArt.dpadCenter

    static let lines: Path = ControllerArt.lines.reduce(into: Path()) { $0.addPath(Path(svg: $1)) }
    static let arch: Path = ControllerArt.arch.reduce(into: Path()) { $0.addPath(Path(svg: $1)) }
    static let leftCap: Path = ControllerArt.leftCapLines.reduce(into: Path()) { $0.addPath(Path(svg: $1)) }
    static let rightCap: Path = ControllerArt.rightCapLines.reduce(into: Path()) { $0.addPath(Path(svg: $1)) }

    /// One arm of the d-pad's cross, out to the plate's inner rim.
    static func dpadArm(_ k: FlydigiKey) -> Path {
        let w = ControllerArt.dpadArmWidth, reach: CGFloat = 60, c = dpad
        let r: CGRect = switch k {
        case .up: CGRect(x: c.x - w / 2, y: c.y - reach, width: w, height: reach - w / 2)
        case .down: CGRect(x: c.x - w / 2, y: c.y + w / 2, width: w, height: reach - w / 2)
        case .left: CGRect(x: c.x - reach, y: c.y - w / 2, width: reach - w / 2, height: w)
        default: CGRect(x: c.x + w / 2, y: c.y - w / 2, width: reach - w / 2, height: w)
        }
        return Path(Path(r).cgPath.intersection(Path(polygon: ControllerArt.dpadInner).cgPath))
    }

    /// The whole cross: the four arms and the middle.
    static let dpadCross: Path = {
        let w = ControllerArt.dpadArmWidth
        var cross = Path(CGRect(x: dpad.x - w / 2, y: dpad.y - w / 2, width: w, height: w)).cgPath
        for k in [FlydigiKey.up, .down, .left, .right] { cross = cross.union(dpadArm(k).cgPath) }
        return Path(cross)
    }()

    /// A polygon with its corners rounded by `radius`.
    static func rounded(_ pts: [CGPoint], _ radius: CGFloat) -> Path {
        var p = Path()
        let n = pts.count
        let start = CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2)
        p.move(to: start)
        for i in 0..<n {
            p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % n], radius: radius)
        }
        p.closeSubpath()
        return p
    }

    /// The same shape on the other side of the drawing.
    static func mirrored(_ p: Path) -> Path {
        p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 500, ty: 0))
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    static let regions: [ControllerControl: Path] = {
        var r: [ControllerControl: Path] = [
            .key(.lt): lt, .key(.rt): rt, .key(.lm): lm, .key(.rm): rm,
            .leftStick: circle(leftStick, stickRadius), .rightStick: circle(rightStick, stickRadius),
            .key(.a): circle(a, faceRadius), .key(.b): circle(b, faceRadius),
            .key(.x): circle(x, faceRadius), .key(.y): circle(y, faceRadius),
            .key(.view): Path(polygon: ControllerArt.view), .key(.menu): Path(polygon: ControllerArt.menu),
            .key(.home): Path(polygon: ControllerArt.home),
            .key(.m1): m1, .key(.m2): m2, .key(.m3): m3, .key(.m4): m4,
            .key(.turbo): Path(roundedRect: turbo, cornerRadius: 11), .key(.fn): Path(roundedRect: fn, cornerRadius: 11),
            .key(.lb): bumperLeft, .key(.rb): bumperRight,
            .screen: Path(roundedRect: screen, cornerRadius: 3),
        ]
        for k in [FlydigiKey.up, .down, .left, .right] { r[.key(k)] = dpadArm(k) }
        r[.lighting] = arch.strokedPath(.init(lineWidth: 12, lineCap: .round))
        return r
    }()
}
