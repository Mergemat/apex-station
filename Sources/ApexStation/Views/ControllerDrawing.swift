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
    /// The outline is 500 wide and starts below the shoulder row.
    private static let bodyTop: CGFloat = 74
    /// Mirrors left-side geometry onto the right side of the 500-wide drawing.
    private static let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 500, ty: 0)

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

    /// Unit coordinates on the outline (x and y divided by its width) → drawing space.
    private func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: u * 500, y: Self.bodyTop + v * 500) }

    private func draw(_ ctx: inout GraphicsContext) {
        // Shoulder row above the body: triggers fill with how far they're pulled.
        trigger(&ctx, L.lt, "LT", live ? state.leftTrigger : 0)
        trigger(&ctx, L.rt, "RT", live ? state.rightTrigger : 0)
        key(&ctx, .capsule(L.lm), "LM", b.contains(.leftMacro))
        key(&ctx, .capsule(L.rm), "RM", b.contains(.rightMacro))

        let shell = ApexOutline.path(width: 500, origin: CGPoint(x: 0, y: Self.bodyTop))
        drawShell(&ctx, shell)
        bumper(&ctx, shell, left: true, on: b.contains(.leftBumper))
        bumper(&ctx, shell, left: false, on: b.contains(.rightBumper))
        faceplate(&ctx)
        lightBar(&ctx)

        stick(&ctx, L.leftStick, live ? state.leftStick : .init(), "L3", b.contains(.leftStick))
        stick(&ctx, L.rightStick, live ? state.rightStick : .init(), "R3", b.contains(.rightStick))
        dpad(&ctx, L.dpad)
        key(&ctx, .circle(L.a, L.faceRadius), "A", b.contains(.a))
        key(&ctx, .circle(L.b, L.faceRadius), "B", b.contains(.b))
        key(&ctx, .circle(L.x, L.faceRadius), "X", b.contains(.x))
        key(&ctx, .circle(L.y, L.faceRadius), "Y", b.contains(.y))
        smallKey(&ctx, L.view, degrees: 50, icon: "rectangle.on.rectangle", on: b.contains(.back))
        smallKey(&ctx, L.menu, degrees: -50, icon: "line.3.horizontal", on: b.contains(.start))
        home(&ctx, L.home, on: b.contains(.guide))

        // Back: paddles under the grip they sit on, Turbo and Fn in the middle.
        caption(&ctx, "BACK", CGPoint(x: 250, y: 452))
        key(&ctx, .capsule(L.m2), "M2", b.contains(.m2))
        key(&ctx, .capsule(L.m4), "M4", b.contains(.m4))
        key(&ctx, .capsule(L.m1), "M1", b.contains(.m1))
        key(&ctx, .capsule(L.m3), "M3", b.contains(.m3))
        key(&ctx, .capsule(L.turbo), "TURBO", b.contains(.turbo), small: true)
        key(&ctx, .capsule(L.fn), "FN", b.contains(.fn), small: true)

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

    private func drawShell(_ ctx: inout GraphicsContext, _ shell: Path) {
        var shadow = ctx
        shadow.addFilter(.blur(radius: 24))
        shadow.translateBy(x: 0, y: 16)
        shadow.fill(shell, with: .color(.black.opacity(0.4)))
        ctx.fill(shell, with: .linearGradient(Gradient(colors: [.white.opacity(0.15), .white.opacity(0.05)]),
                                              startPoint: at(0.5, 0), endPoint: at(0.5, 0.7)))
        ctx.stroke(shell, with: .linearGradient(Gradient(colors: [.white.opacity(0.38), .white.opacity(0.08)]),
                                                startPoint: at(0.5, 0), endPoint: at(0.5, 0.7)),
                   lineWidth: 1.2)
    }

    /// A bumper is a strip of even thickness along the outline's top edge, over the hump
    /// (12-34 % of the width, measured), so it follows the controller's curve exactly.
    /// A bumper is a separate part behind the body that sticks out above it at the shoulder.
    /// Its top is the controller's outline; its bottom is the body's own top edge, an arc from
    /// the faceplate's top corner down to the side. The faceplate sits in front of it.
    private func bumper(_ ctx: inout GraphicsContext, _ shell: Path, left: Bool, on: Bool) {
        let shape = Self.bumperShape(left: left, shell: shell)
        let r = shape.boundingRect
        if on {
            var g = ctx
            g.addFilter(.blur(radius: 9))
            g.fill(shape, with: .color(Theme.accent))
        }
        ctx.fill(shape, with: on
            ? .linearGradient(Gradient(colors: [Theme.glow, Theme.accent]), startPoint: r.origin, endPoint: CGPoint(x: r.maxX, y: r.maxY))
            : .linearGradient(Gradient(colors: [.white.opacity(0.24), .white.opacity(0.11)]),
                              startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        // Thin edge all round, brighter rim on top where light catches the shoulder.
        ctx.stroke(shape, with: .color(on ? Theme.glow.opacity(0.9) : .white.opacity(0.22)), lineWidth: 0.8)
        var rim = ctx
        rim.clip(to: shape)
        rim.stroke(shell, with: .color(.white.opacity(on ? 0.75 : 0.5)), lineWidth: 2)
        label(&ctx, left ? "LB" : "RB", at: Self.bumperLabel(left: left), size: 8, color: on ? .white : .white.opacity(0.8))
    }

    static func bumperRegion(left: Bool) -> Path {
        bumperShape(left: left, shell: ApexOutline.path(width: 500, origin: CGPoint(x: 0, y: bodyTop)))
    }

    private static let bodyEdge: [CGPoint] = [
        // Starts outside the shell at the bottom of the step where the bumper ends, so nothing of
        // the bumper runs down the side.
        (0.1000, 0.0846), (0.1334, 0.0846), (0.1570, 0.0713), (0.1740, 0.0611), (0.1910, 0.0526),
        (0.2080, 0.0441), (0.2250, 0.0374), (0.2419, 0.0323), (0.2589, 0.0272), (0.2759, 0.0229),
        (0.2929, 0.0195), (0.3098, 0.0170), (0.3268, 0.0153), (0.3438, 0.0110), (0.3600, 0.0060),
    ].map { CGPoint(x: $0.0 * 500, y: bodyTop + $0.1 * 500) }

    private static func bumperShape(left: Bool, shell: Path) -> Path {
        let e = bodyEdge
        // Everything above the body's top edge, out to where it meets the outline; the outline trims it.
        var above = Path()
        above.move(to: e[0])
        for i in 1..<e.count {
            let mid = CGPoint(x: (e[i - 1].x + e[i].x) / 2, y: (e[i - 1].y + e[i].y) / 2)
            above.addQuadCurve(to: mid, control: e[i - 1])
        }
        above.addLine(to: e[e.count - 1])
        above.addLine(to: CGPoint(x: e[e.count - 1].x, y: 0))
        above.addLine(to: CGPoint(x: 0, y: 0))
        above.addLine(to: CGPoint(x: 0, y: e[0].y))
        above.closeSubpath()
        if !left { above = above.applying(mirror) }
        return Path(shell.cgPath.intersection(above.cgPath).subtracting(faceplatePath.cgPath))
    }

    /// Where the label goes: in the thick middle of the bumper.
    private static func bumperLabel(left: Bool) -> CGPoint {
        let p = CGPoint(x: 0.205 * 500, y: bodyTop + 0.0355 * 500)
        return left ? p : p.applying(mirror)
    }

    private static let faceplatePath: Path = {
        let side: [(CGFloat, CGFloat)] = [
            (0.190, 0.0315), (0.212, 0.040), (0.2215, 0.062), (0.214, 0.089), (0.202, 0.102),
            (0.071, 0.266), (0.058, 0.278), (0.040, 0.2802),
        ]
        let left = side.map { CGPoint(x: (0.5 - $0.0) * 500, y: bodyTop + $0.1 * 500) }
        let right = side.reversed().map { CGPoint(x: (0.5 + $0.0) * 500, y: bodyTop + $0.1 * 500) }
        // Rounded corners: a closed quad-spline through the midpoints, with the points as controls.
        let ring = Array(left.reversed()) + Array(right.reversed())
        var p = Path()
        let n = ring.count
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        p.move(to: mid(ring[n - 1], ring[0]))
        for i in 0..<n { p.addQuadCurve(to: mid(ring[i], ring[(i + 1) % n]), control: ring[i]) }
        p.closeSubpath()
        return p
    }()

    private func faceplate(_ ctx: inout GraphicsContext) {
        let p = Self.faceplatePath
        ctx.fill(p, with: .color(.black.opacity(0.18)))
        ctx.stroke(p, with: .color(.white.opacity(0.12)), lineWidth: 0.8)
        // The controller's own screen, showing which profile is active.
        let screen = Path(roundedRect: L.screen, cornerRadius: 4)
        ctx.fill(screen, with: .linearGradient(Gradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.16), Color(red: 0.02, green: 0.03, blue: 0.07)]),
                                               startPoint: CGPoint(x: 0, y: screen.boundingRect.minY), endPoint: CGPoint(x: 0, y: screen.boundingRect.maxY)))
        ctx.stroke(screen, with: .color(.white.opacity(0.14)), lineWidth: 0.8)
        if let profile {
            let c = CGPoint(x: screen.boundingRect.midX, y: screen.boundingRect.midY)
            label(&ctx, "P\(profile.slot + 1)", at: c, size: 11, weight: .bold, color: Theme.glow.opacity(0.9))
        }
    }

    /// The light bar's path, measured from the photo.
    private func lightBar(_ ctx: inout GraphicsContext) {
        let bar = L.lightBar
        if live {
            var g = ctx
            g.addFilter(.blur(radius: 7))
            g.stroke(bar, with: .color(Theme.accent), style: .init(lineWidth: 7, lineCap: .round))
        }
        ctx.stroke(bar, with: .color(live ? Theme.glow : .white.opacity(0.12)), style: .init(lineWidth: 2.4, lineCap: .round))
    }

    // MARK: - Controls

    private enum Shape { case capsule(CGRect), circle(CGPoint, CGFloat), rounded(CGRect, CGFloat) }

    private func path(_ s: Shape) -> Path {
        switch s {
        case .capsule(let r): Path(roundedRect: r, cornerRadius: r.height / 2)
        case .circle(let c, let r): Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        case .rounded(let r, let radius): Path(roundedRect: r, cornerRadius: radius)
        }
    }

    /// The one look every control shares: dim glass when idle, glowing blue when pressed.
    private func fill(_ ctx: inout GraphicsContext, _ p: Path, on: Bool) {
        if on {
            var g = ctx
            g.addFilter(.blur(radius: 9))
            g.fill(p, with: .color(Theme.accent.opacity(0.9)))
            ctx.fill(p, with: .linearGradient(Gradient(colors: [Theme.glow, Theme.accent]),
                                              startPoint: p.boundingRect.origin,
                                              endPoint: CGPoint(x: p.boundingRect.maxX, y: p.boundingRect.maxY)))
        } else {
            ctx.fill(p, with: .color(.white.opacity(0.10)))
        }
        ctx.stroke(p, with: .color(.white.opacity(on ? 0.55 : 0.18)), lineWidth: 0.8)
    }

    private func key(_ ctx: inout GraphicsContext, _ s: Shape, _ label: String, _ on: Bool, small: Bool = false) {
        let p = path(s)
        fill(&ctx, p, on: on)
        self.label(&ctx, label, at: CGPoint(x: p.boundingRect.midX, y: p.boundingRect.midY), size: small ? 7.5 : 11,
                   color: on ? .white : .white.opacity(0.6))
    }

    private func smallKey(_ ctx: inout GraphicsContext, _ c: CGPoint, degrees: Double, icon: String, on: Bool) {
        let p = Path(roundedRect: CGRect(x: -16, y: -7.5, width: 32, height: 15), cornerRadius: 7.5)
            .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180).concatenating(.init(translationX: c.x, y: c.y)))
        fill(&ctx, p, on: on)
        ctx.draw(Text(Image(systemName: icon)).font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.65)), at: c)
    }

    private func trigger(_ ctx: inout GraphicsContext, _ r: CGRect, _ label: String, _ value: UInt8) {
        let p = Path(roundedRect: r, cornerRadius: r.height / 2)
        ctx.fill(p, with: .color(.white.opacity(0.07)))
        let f = CGFloat(value) / 255
        if f > 0 {
            var inner = ctx
            inner.clip(to: p)
            let level = Path(CGRect(x: r.minX, y: r.minY, width: r.width * f, height: r.height))
            var g = inner
            g.addFilter(.blur(radius: 6))
            g.fill(level, with: .color(Theme.accent))
            inner.fill(level, with: .linearGradient(Gradient(colors: [Theme.accent, Theme.glow]),
                                                    startPoint: CGPoint(x: r.minX, y: r.midY), endPoint: CGPoint(x: r.maxX, y: r.midY)))
        }
        ctx.stroke(p, with: .color(.white.opacity(f > 0 ? 0.5 : 0.18)), lineWidth: 0.8)
        self.label(&ctx, label, at: CGPoint(x: r.midX, y: r.midY), size: 11, color: f > 0.4 ? .white : .white.opacity(0.6))
    }

    private func stick(_ ctx: inout GraphicsContext, _ c: CGPoint, _ pos: StickPosition, _ label: String, _ clicked: Bool) {
        let well = path(.circle(c, 38))
        ctx.fill(well, with: .color(.black.opacity(0.28)))
        ctx.stroke(well, with: .color(.white.opacity(0.16)), lineWidth: 1)
        var cross = Path()
        cross.move(to: CGPoint(x: c.x - 30, y: c.y)); cross.addLine(to: CGPoint(x: c.x + 30, y: c.y))
        cross.move(to: CGPoint(x: c.x, y: c.y - 30)); cross.addLine(to: CGPoint(x: c.x, y: c.y + 30))
        ctx.stroke(cross, with: .color(.white.opacity(0.07)), lineWidth: 1)
        let travel: CGFloat = 15
        // Up-positive Y; screen Y grows downwards.
        let p = CGPoint(x: c.x + CGFloat(pos.x) / 32767 * travel, y: c.y - CGFloat(pos.y) / 32767 * travel)
        let moved = abs(Int(pos.x)) > 3000 || abs(Int(pos.y)) > 3000
        let cap = path(.circle(p, 22))
        fill(&ctx, cap, on: clicked)
        if moved && !clicked { ctx.stroke(cap, with: .color(Theme.glow.opacity(0.85)), lineWidth: 1.5) }
        self.label(&ctx, label, at: p, size: 9, color: clicked ? .white : .white.opacity(0.35))
    }

    /// Four separate arrow keys, so each direction reads on its own.
    private func dpad(_ ctx: inout GraphicsContext, _ c: CGPoint) {
        // Each arrow is a chevron pointing along (dx, dy), drawn as a path so it sits exactly in
        // the middle of its key (a symbol glyph carries side spacing that pushes it off centre).
        let keys: [(FlydigiKey, GamepadButtons, CGFloat, CGFloat)] = [
            (.up, .dpadUp, 0, -1), (.down, .dpadDown, 0, 1), (.left, .dpadLeft, -1, 0), (.right, .dpadRight, 1, 0),
        ]
        for (key, button, dx, dy) in keys {
            let r = L.dpadRect(key)
            let on = b.contains(button)
            fill(&ctx, path(.rounded(r, 8)), on: on)
            let c = CGPoint(x: r.midX, y: r.midY), half: CGFloat = 4.2, depth: CGFloat = 2.2
            var chevron = Path()
            chevron.move(to: CGPoint(x: c.x - dx * depth - dy * half, y: c.y - dy * depth - dx * half))
            chevron.addLine(to: CGPoint(x: c.x + dx * depth, y: c.y + dy * depth))
            chevron.addLine(to: CGPoint(x: c.x - dx * depth + dy * half, y: c.y - dy * depth + dx * half))
            ctx.stroke(chevron, with: .color(on ? .white : .white.opacity(0.65)),
                       style: .init(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }

    private func home(_ ctx: inout GraphicsContext, _ c: CGPoint, on: Bool) {
        fill(&ctx, path(.circle(c, 15)), on: on)
        var v = Path()
        v.move(to: CGPoint(x: c.x - 8, y: c.y - 5))
        v.addLine(to: CGPoint(x: c.x, y: c.y + 6))
        v.addLine(to: CGPoint(x: c.x + 8, y: c.y - 5))
        ctx.stroke(v, with: .color(on ? .white : .white.opacity(0.65)), style: .init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
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
    static func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: u * 500, y: bodyTop + v * 500) }
    /// The controller's own 160×80 display.
    static let screen = CGRect(x: 0.419 * 500, y: bodyTop + 0.156 * 500, width: 0.162 * 500, height: 0.078 * 500)

    static let lt = CGRect(x: 58, y: 18, width: 104, height: 26)
    static let rt = CGRect(x: 338, y: 18, width: 104, height: 26)
    static let lm = CGRect(x: 172, y: 18, width: 46, height: 26)
    static let rm = CGRect(x: 282, y: 18, width: 46, height: 26)
    static let leftStick = at(0.2258, 0.2063)
    static let rightStick = at(0.6727, 0.3701)
    static let stickRadius: CGFloat = 37
    static let dpad = at(0.3582, 0.3701)
    static let dpadKey: CGFloat = 28, dpadGap: CGFloat = 16
    static let a = at(0.7925, 0.2908), b = at(0.8588, 0.2246), x = at(0.7258, 0.2246), y = at(0.7925, 0.1591)
    static let faceRadius: CGFloat = 15.5
    static let view = at(0.365, 0.090), menu = at(0.635, 0.090), home = at(0.5, 0.0764)
    static let m2 = CGRect(x: 40, y: 446, width: 100, height: 26)
    static let m4 = CGRect(x: 40, y: 480, width: 100, height: 26)
    static let m1 = CGRect(x: 360, y: 446, width: 100, height: 26)
    static let m3 = CGRect(x: 360, y: 480, width: 100, height: 26)
    static let turbo = CGRect(x: 196, y: 476, width: 50, height: 22)
    static let fn = CGRect(x: 254, y: 476, width: 50, height: 22)

    /// The light bar along the bottom of the body, measured from the photo.
    static let lightBar: Path = {
        // The RGB strip above the arch between the grips, from grip to grip.
        let half: [(CGFloat, CGFloat)] = [(0.1126, 0.6686), (0.1514, 0.6156), (0.1975, 0.5620), (0.2433, 0.5161),
                                          (0.2780, 0.4995), (0.3200, 0.4935)]
        let pts = half + [(0.5, 0.4932)] + half.reversed().map { (1 - $0.0, $0.1) }
        var bar = Path()
        bar.move(to: at(pts[0].0, pts[0].1))
        for i in 1..<pts.count {
            let a = at(pts[i - 1].0, pts[i - 1].1), c = at(pts[i].0, pts[i].1)
            bar.addQuadCurve(to: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2), control: a)
        }
        bar.addLine(to: at(pts.last!.0, pts.last!.1))
        return bar
    }()

    static func dpadRect(_ k: FlydigiKey) -> CGRect {
        let off = dpadGap + dpadKey / 2
        let c: CGPoint = switch k {
        case .up: CGPoint(x: dpad.x, y: dpad.y - off)
        case .down: CGPoint(x: dpad.x, y: dpad.y + off)
        case .left: CGPoint(x: dpad.x - off, y: dpad.y)
        default: CGPoint(x: dpad.x + off, y: dpad.y)
        }
        return CGRect(x: c.x - dpadKey / 2, y: c.y - dpadKey / 2, width: dpadKey, height: dpadKey)
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private static func rotatedKey(_ c: CGPoint, _ degrees: Double) -> Path {
        Path(roundedRect: CGRect(x: -16, y: -7.5, width: 32, height: 15), cornerRadius: 7.5)
            .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180).concatenating(.init(translationX: c.x, y: c.y)))
    }

    /// Clickable shape of every control.
    static let regions: [ControllerControl: Path] = {
        var r: [ControllerControl: Path] = [
            .key(.lt): Path(roundedRect: lt, cornerRadius: 13), .key(.rt): Path(roundedRect: rt, cornerRadius: 13),
            .key(.lm): Path(roundedRect: lm, cornerRadius: 13), .key(.rm): Path(roundedRect: rm, cornerRadius: 13),
            .leftStick: circle(leftStick, stickRadius), .rightStick: circle(rightStick, stickRadius),
            .key(.a): circle(a, faceRadius), .key(.b): circle(b, faceRadius),
            .key(.x): circle(x, faceRadius), .key(.y): circle(y, faceRadius),
            .key(.view): rotatedKey(view, 50), .key(.menu): rotatedKey(menu, -50), .key(.home): circle(home, 15),
            .key(.m1): Path(roundedRect: m1, cornerRadius: 13), .key(.m2): Path(roundedRect: m2, cornerRadius: 13),
            .key(.m3): Path(roundedRect: m3, cornerRadius: 13), .key(.m4): Path(roundedRect: m4, cornerRadius: 13),
            .key(.turbo): Path(roundedRect: turbo, cornerRadius: 11), .key(.fn): Path(roundedRect: fn, cornerRadius: 11),
            .key(.lb): ControllerDrawing.bumperRegion(left: true), .key(.rb): ControllerDrawing.bumperRegion(left: false),
        ]
        for k in [FlydigiKey.up, .down, .left, .right] { r[.key(k)] = Path(roundedRect: dpadRect(k), cornerRadius: 8) }
        r[.lighting] = lightBar.strokedPath(.init(lineWidth: 14, lineCap: .round))
        r[.screen] = Path(roundedRect: screen, cornerRadius: 4)
        return r
    }()
}
