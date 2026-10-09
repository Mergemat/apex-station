import ApexKit
import AppKit
import CoreText
import SwiftUI

struct ControllerDrawing: View {
    let state: GamepadState
    let live: Bool

    private static let space = CGSize(width: 500, height: 520)
    /// The outline is 500 wide and starts below the shoulder row.
    private static let bodyTop: CGFloat = 74

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

    /// Unit coordinates on the outline (x and y divided by its width) → drawing space.
    private func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: u * 500, y: Self.bodyTop + v * 500) }

    private func draw(_ ctx: inout GraphicsContext) {
        // Shoulder row above the body: triggers fill with how far they're pulled.
        trigger(&ctx, CGRect(x: 58, y: 18, width: 104, height: 26), "LT", live ? state.leftTrigger : 0)
        trigger(&ctx, CGRect(x: 338, y: 18, width: 104, height: 26), "RT", live ? state.rightTrigger : 0)
        key(&ctx, .capsule(CGRect(x: 172, y: 18, width: 46, height: 26)), "LM", b.contains(.leftMacro))
        key(&ctx, .capsule(CGRect(x: 282, y: 18, width: 46, height: 26)), "RM", b.contains(.rightMacro))

        let shell = ApexOutline.path(width: 500, origin: CGPoint(x: 0, y: Self.bodyTop))
        drawShell(&ctx, shell)
        bumper(&ctx, shell, left: true, on: b.contains(.leftBumper))
        bumper(&ctx, shell, left: false, on: b.contains(.rightBumper))
        faceplate(&ctx)
        lightBar(&ctx)

        stick(&ctx, at(0.2373, 0.1793), live ? state.leftStick : .init(), "L3", b.contains(.leftStick))
        stick(&ctx, at(0.6226, 0.3532), live ? state.rightStick : .init(), "R3", b.contains(.rightStick))
        dpad(&ctx, at(0.3649, 0.3492))
        key(&ctx, .circle(at(0.7619, 0.2514), 16), "A", b.contains(.a))
        key(&ctx, .circle(at(0.8277, 0.1887), 16), "B", b.contains(.b))
        key(&ctx, .circle(at(0.6922, 0.1879), 16), "X", b.contains(.x))
        key(&ctx, .circle(at(0.7588, 0.1214), 16), "Y", b.contains(.y))
        smallKey(&ctx, at(0.3720, 0.0799), degrees: 50, icon: "rectangle.on.rectangle", on: b.contains(.back))
        smallKey(&ctx, at(0.6226, 0.0799), degrees: -50, icon: "line.3.horizontal", on: b.contains(.start))
        home(&ctx, at(0.4965, 0.0673), on: b.contains(.guide))

        // Back: paddles under the grip they sit on, Turbo and Fn in the middle.
        caption(&ctx, "BACK", CGPoint(x: 250, y: 452))
        key(&ctx, .capsule(CGRect(x: 40, y: 446, width: 100, height: 26)), "M2", b.contains(.m2))
        key(&ctx, .capsule(CGRect(x: 40, y: 480, width: 100, height: 26)), "M4", b.contains(.m4))
        key(&ctx, .capsule(CGRect(x: 360, y: 446, width: 100, height: 26)), "M1", b.contains(.m1))
        key(&ctx, .capsule(CGRect(x: 360, y: 480, width: 100, height: 26)), "M3", b.contains(.m3))
        key(&ctx, .capsule(CGRect(x: 196, y: 476, width: 50, height: 22)), "TURBO", b.contains(.c), small: true)
        key(&ctx, .capsule(CGRect(x: 254, y: 476, width: 50, height: 22)), "FN", b.contains(.z), small: true)
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
    private func bumper(_ ctx: inout GraphicsContext, _ shell: Path, left: Bool, on: Bool) {
        let thickness: CGFloat = 13
        let span = left ? CGRect(x: 0.12 * 500, y: Self.bodyTop - 10, width: 0.22 * 500, height: 40)
                        : CGRect(x: 0.66 * 500, y: Self.bodyTop - 10, width: 0.22 * 500, height: 40)
        var strip = ctx
        strip.clip(to: Path(roundedRect: span, cornerRadius: 12))
        strip.clip(to: shell)
        strip.clip(to: shell.applying(.init(translationX: 0, y: thickness)), options: .inverse)
        if on {
            var g = strip
            g.addFilter(.blur(radius: 6))
            g.fill(Path(span), with: .color(Theme.accent))
        }
        strip.fill(Path(span), with: on
            ? .linearGradient(Gradient(colors: [Theme.glow, Theme.accent]), startPoint: span.origin,
                              endPoint: CGPoint(x: span.maxX, y: span.maxY))
            : .color(.white.opacity(0.16)))
        label(&ctx, left ? "LB" : "RB", at: CGPoint(x: span.midX, y: Self.bodyTop + 22), size: 9.5,
              color: on ? .white : .white.opacity(0.5))
    }

    private func faceplate(_ ctx: inout GraphicsContext) {
        let corners = [(0.320, 0.026), (0.680, 0.026), (0.672, 0.104), (0.548, 0.248), (0.452, 0.248), (0.328, 0.104)]
        var p = Path()
        p.addLines(corners.map { at($0.0, $0.1) })
        p.closeSubpath()
        ctx.fill(p, with: .color(.black.opacity(0.18)))
        ctx.stroke(p, with: .color(.white.opacity(0.12)), lineWidth: 0.8)
    }

    /// The light bar's path, measured from the photo.
    private func lightBar(_ ctx: inout GraphicsContext) {
        let pts = [(0.1621, 0.5889), (0.2060, 0.5489), (0.2529, 0.5121), (0.2999, 0.4965), (0.3469, 0.4949),
                   (0.5, 0.4945), (0.6528, 0.4949), (0.6998, 0.4965), (0.7468, 0.5121), (0.7937, 0.5489), (0.8379, 0.5889)]
        var bar = Path()
        bar.move(to: at(pts[0].0, pts[0].1))
        for i in 1..<pts.count {
            let a = at(pts[i - 1].0, pts[i - 1].1), c = at(pts[i].0, pts[i].1)
            bar.addQuadCurve(to: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2), control: a)
        }
        bar.addLine(to: at(pts.last!.0, pts.last!.1))
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
        let size: CGFloat = 24, gap: CGFloat = 14
        let keys: [(GamepadButtons, CGPoint, String)] = [
            (.dpadUp, CGPoint(x: c.x, y: c.y - gap - size / 2), "chevron.up"),
            (.dpadDown, CGPoint(x: c.x, y: c.y + gap + size / 2), "chevron.down"),
            (.dpadLeft, CGPoint(x: c.x - gap - size / 2, y: c.y), "chevron.left"),
            (.dpadRight, CGPoint(x: c.x + gap + size / 2, y: c.y), "chevron.right"),
        ]
        for (button, p, icon) in keys {
            let shape = path(.rounded(CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size), 8))
            fill(&ctx, shape, on: b.contains(button))
            ctx.draw(Text(Image(systemName: icon)).font(.system(size: 9, weight: .bold))
                .foregroundStyle(b.contains(button) ? Color.white : Color.white.opacity(0.65)), at: p)
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
