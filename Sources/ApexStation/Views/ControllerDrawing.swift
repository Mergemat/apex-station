import ApexKit
import SwiftUI

/// A live, glassy drawing of the Apex 5, front or back. Proportions follow the real
/// controller; the artwork is our own. Drawn in a 500×380 space and scaled to fit.
struct ControllerDrawing: View {
    enum Side { case front, back }

    let state: GamepadState
    let live: Bool
    var side: Side = .front

    private static let space = CGSize(width: 500, height: 380)
    /// The body starts below the shoulder buttons.
    private static let top: CGFloat = 34

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / Self.space.width, size.height / Self.space.height)
            ctx.translateBy(x: (size.width - Self.space.width * s) / 2, y: (size.height - Self.space.height * s) / 2)
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: 0, y: Self.top)
            switch side {
            case .front: drawFront(&ctx)
            case .back: drawBack(&ctx)
            }
        }
        .accessibilityLabel(side == .front ? "Live view of the controller" : "Back paddles")
    }

    private var buttons: GamepadButtons { live ? state.buttons : [] }

    // MARK: - Front

    private func drawFront(_ ctx: inout GraphicsContext) {
        let b = buttons
        triggers(&ctx)
        shell(&ctx, Self.bodyPath, dark: false)
        rim(&ctx)
        faceplate(&ctx)
        centreScreen(&ctx)
        sideScreen(&ctx)
        lightBar(&ctx)

        stick(&ctx, center: CGPoint(x: 116, y: 98), live ? state.leftStick : .init(), clicked: b.contains(.leftStick))
        stick(&ctx, center: CGPoint(x: 318, y: 180), live ? state.rightStick : .init(), clicked: b.contains(.rightStick))
        dpad(&ctx, center: CGPoint(x: 190, y: 184), b)
        face(&ctx, CGPoint(x: 386, y: 128), "A", b.contains(.a))
        face(&ctx, CGPoint(x: 419, y: 98), "B", b.contains(.b))
        face(&ctx, CGPoint(x: 353, y: 98), "X", b.contains(.x))
        face(&ctx, CGPoint(x: 386, y: 68), "Y", b.contains(.y))
        // Small round keys beside the sticks and pill keys on the grip edges.
        dot(&ctx, CGPoint(x: 182, y: 110))
        dot(&ctx, CGPoint(x: 384, y: 164))
        pill(&ctx, center: CGPoint(x: 50, y: 140), degrees: 0)
        pill(&ctx, center: CGPoint(x: 452, y: 128), degrees: 0)
        pill(&ctx, center: CGPoint(x: 120, y: 232), degrees: -40)
        pill(&ctx, center: CGPoint(x: 384, y: 226), degrees: 40)
        smallKey(&ctx, center: CGPoint(x: 191, y: 56), degrees: 35, icon: "rectangle.on.rectangle", on: b.contains(.back))
        smallKey(&ctx, center: CGPoint(x: 309, y: 56), degrees: -35, icon: "line.3.horizontal", on: b.contains(.start))
        logo(&ctx, center: CGPoint(x: 250, y: 50), on: b.contains(.guide))

        // A paddle pressed while looking at the front: light the grip it's on.
        gripHint(&ctx, left: !b.isDisjoint(with: [.m2, .m4]), right: !b.isDisjoint(with: [.m1, .m3]))
    }

    /// Triggers sit furthest back, peeking over the top of the body.
    private func triggers(_ ctx: inout GraphicsContext) {
        trigger(&ctx, Self.leftTrigger, live ? state.leftTrigger : 0, label: "LT", labelAt: CGPoint(x: 92, y: -15))
        trigger(&ctx, Self.leftTrigger.applying(Self.mirror), live ? state.rightTrigger : 0, label: "RT", labelAt: CGPoint(x: 408, y: -15))
    }

    /// Bumpers and M5/M6 ride on the top rim, in front of the body.
    private func rim(_ ctx: inout GraphicsContext) {
        let b = buttons
        part(&ctx, Self.leftBumper, on: b.contains(.leftBumper), label: "LB", labelAt: CGPoint(x: 120, y: 30))
        part(&ctx, Self.leftBumper.applying(Self.mirror), on: b.contains(.rightBumper), label: "RB", labelAt: CGPoint(x: 380, y: 30))
        part(&ctx, Path(roundedRect: CGRect(x: 170, y: -7, width: 34, height: 13), cornerRadius: 6.5), on: b.contains(.leftMacro), label: "M5", labelAt: CGPoint(x: 187, y: -16))
        part(&ctx, Path(roundedRect: CGRect(x: 296, y: -7, width: 34, height: 13), cornerRadius: 6.5), on: b.contains(.rightMacro), label: "M6", labelAt: CGPoint(x: 313, y: -16))
    }

    private func faceplate(_ ctx: inout GraphicsContext) {
        var p = Path()
        p.move(to: CGPoint(x: 152, y: 27))
        p.addLine(to: CGPoint(x: 348, y: 27))
        p.addQuadCurve(to: CGPoint(x: 354, y: 39), control: CGPoint(x: 358, y: 30))
        p.addLine(to: CGPoint(x: 290, y: 124))
        p.addQuadCurve(to: CGPoint(x: 276, y: 131), control: CGPoint(x: 285, y: 131))
        p.addLine(to: CGPoint(x: 224, y: 131))
        p.addQuadCurve(to: CGPoint(x: 210, y: 124), control: CGPoint(x: 215, y: 131))
        p.addLine(to: CGPoint(x: 146, y: 39))
        p.addQuadCurve(to: CGPoint(x: 152, y: 27), control: CGPoint(x: 142, y: 30))
        p.closeSubpath()
        ctx.fill(p, with: .linearGradient(Gradient(colors: [.black.opacity(0.32), .black.opacity(0.22)]),
                                          startPoint: CGPoint(x: 250, y: 27), endPoint: CGPoint(x: 250, y: 131)))
        ctx.stroke(p, with: .color(.white.opacity(0.22)), lineWidth: 0.8)
    }

    /// The display in the faceplate.
    private func centreScreen(_ ctx: inout GraphicsContext) {
        let r = CGRect(x: 220, y: 88, width: 60, height: 24)
        let shape = Path(roundedRect: r, cornerRadius: 6)
        ctx.fill(shape, with: .color(.black.opacity(0.55)))
        if live {
            var g = ctx
            g.addFilter(.blur(radius: 6))
            g.fill(shape, with: .color(Theme.accent.opacity(0.55)))
            ctx.fill(shape, with: .linearGradient(Gradient(colors: [Theme.glow.opacity(0.9), Theme.accent]),
                                                  startPoint: r.origin, endPoint: CGPoint(x: r.maxX, y: r.maxY)))
            ctx.draw(Text(Image(systemName: "gamecontroller.fill")).font(.system(size: 11)).foregroundStyle(.white),
                     at: CGPoint(x: r.midX, y: r.midY))
        }
        ctx.stroke(shape, with: .color(.white.opacity(0.18)), lineWidth: 0.8)
    }

    /// The small status screen on the left grip.
    private func sideScreen(_ ctx: inout GraphicsContext) {
        let r = CGRect(x: 34, y: 194, width: 62, height: 28)
        let shape = Path(roundedRect: r, cornerRadius: 4)
            .applying(CGAffineTransform(translationX: -r.midX, y: -r.midY).concatenating(.init(rotationAngle: 0.08))
                .concatenating(.init(translationX: r.midX, y: r.midY)))
        ctx.fill(shape, with: .color(.black.opacity(0.35)))
        ctx.stroke(shape, with: .color(.white.opacity(0.14)), lineWidth: 0.8)
        let green = Color(red: 0.35, green: 1, blue: 0.75)
        let text = Text("FLYDIGI").font(.system(size: 8.5, weight: .heavy)).tracking(1)
        if live {
            var g = ctx
            g.addFilter(.blur(radius: 3))
            g.draw(text.foregroundStyle(green), at: CGPoint(x: r.midX, y: r.midY))
        }
        ctx.draw(text.foregroundStyle(live ? green : Color.white.opacity(0.2)), at: CGPoint(x: r.midX, y: r.midY))
    }

    private func dot(_ ctx: inout GraphicsContext, _ c: CGPoint) {
        part(&ctx, Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)), on: false)
    }

    private func pill(_ ctx: inout GraphicsContext, center c: CGPoint, degrees: Double) {
        let shape = Path(roundedRect: CGRect(x: -5, y: -12, width: 10, height: 24), cornerRadius: 5)
            .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180).concatenating(.init(translationX: c.x, y: c.y)))
        part(&ctx, shape, on: false)
    }

    private func lightBar(_ ctx: inout GraphicsContext) {
        var bar = Path()
        bar.move(to: CGPoint(x: 78, y: 304))
        bar.addCurve(to: CGPoint(x: 150, y: 252), control1: CGPoint(x: 100, y: 278), control2: CGPoint(x: 122, y: 254))
        bar.addLine(to: CGPoint(x: 350, y: 252))
        bar.addCurve(to: CGPoint(x: 428, y: 300), control1: CGPoint(x: 380, y: 254), control2: CGPoint(x: 404, y: 274))
        let style = StrokeStyle(lineWidth: 3, lineCap: .round)
        if live {
            var wide = ctx
            wide.addFilter(.blur(radius: 10))
            wide.stroke(bar, with: .color(Theme.accent), style: .init(lineWidth: 12, lineCap: .round))
            var near = ctx
            near.addFilter(.blur(radius: 3))
            near.stroke(bar, with: .color(Theme.glow), style: .init(lineWidth: 5, lineCap: .round))
            ctx.stroke(bar, with: .color(.white.opacity(0.95)), style: .init(lineWidth: 1.6, lineCap: .round))
        } else {
            ctx.stroke(bar, with: .color(.white.opacity(0.12)), style: style)
        }
    }

    // MARK: - Back

    private func drawBack(_ ctx: inout GraphicsContext) {
        let b = buttons
        triggers(&ctx)
        shell(&ctx, Self.bodyPath, dark: true)
        rim(&ctx)
        // Seen through the shell, so left stays left.
        paddle(&ctx, center: CGPoint(x: 128, y: 214), length: 64, degrees: -14, "M2", b.contains(.m2))
        paddle(&ctx, center: CGPoint(x: 372, y: 214), length: 64, degrees: 14, "M1", b.contains(.m1))
        paddle(&ctx, center: CGPoint(x: 86, y: 270), length: 56, degrees: -32, "M4", b.contains(.m4))
        paddle(&ctx, center: CGPoint(x: 414, y: 270), length: 56, degrees: 32, "M3", b.contains(.m3))
        part(&ctx, Path(roundedRect: CGRect(x: 214, y: 150, width: 30, height: 12), cornerRadius: 6), on: b.contains(.c), label: "TURBO", labelAt: CGPoint(x: 229, y: 174))
        part(&ctx, Path(roundedRect: CGRect(x: 256, y: 150, width: 30, height: 12), cornerRadius: 6), on: b.contains(.z), label: "FN", labelAt: CGPoint(x: 271, y: 174))
    }

    private func paddle(_ ctx: inout GraphicsContext, center c: CGPoint, length: CGFloat, degrees: Double, _ text: String, _ on: Bool) {
        let shape = Path(roundedRect: CGRect(x: -13, y: -length / 2, width: 26, height: length), cornerRadius: 13)
            .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180).concatenating(.init(translationX: c.x, y: c.y)))
        part(&ctx, shape, on: on, label: text, labelAt: c)
    }

    private func gripHint(_ ctx: inout GraphicsContext, left: Bool, right: Bool) {
        for (on, x) in [(left, 70.0), (right, 430.0)] where on {
            var g = ctx
            g.addFilter(.blur(radius: 14))
            g.fill(Path(ellipseIn: CGRect(x: x - 34, y: 236, width: 68, height: 70)), with: .color(Theme.accent.opacity(0.7)))
        }
    }

    // MARK: - Shared parts

    /// The controller outline, our own trace of the Apex 5's silhouette.
    private static let bodyPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 250, y: 24))
        p.addCurve(to: CGPoint(x: 400, y: 22), control1: CGPoint(x: 320, y: 24), control2: CGPoint(x: 360, y: 18))
        p.addCurve(to: CGPoint(x: 476, y: 72), control1: CGPoint(x: 440, y: 26), control2: CGPoint(x: 466, y: 40))
        p.addCurve(to: CGPoint(x: 485, y: 205), control1: CGPoint(x: 486, y: 105), control2: CGPoint(x: 488, y: 160))
        p.addCurve(to: CGPoint(x: 458, y: 322), control1: CGPoint(x: 482, y: 255), control2: CGPoint(x: 476, y: 300))
        p.addCurve(to: CGPoint(x: 392, y: 320), control1: CGPoint(x: 440, y: 342), control2: CGPoint(x: 404, y: 340))
        p.addCurve(to: CGPoint(x: 352, y: 270), control1: CGPoint(x: 380, y: 300), control2: CGPoint(x: 370, y: 282))
        p.addCurve(to: CGPoint(x: 250, y: 254), control1: CGPoint(x: 330, y: 256), control2: CGPoint(x: 290, y: 254))
        p.addCurve(to: CGPoint(x: 148, y: 270), control1: CGPoint(x: 210, y: 254), control2: CGPoint(x: 170, y: 256))
        p.addCurve(to: CGPoint(x: 108, y: 320), control1: CGPoint(x: 130, y: 282), control2: CGPoint(x: 120, y: 300))
        p.addCurve(to: CGPoint(x: 42, y: 322), control1: CGPoint(x: 96, y: 340), control2: CGPoint(x: 60, y: 342))
        p.addCurve(to: CGPoint(x: 15, y: 205), control1: CGPoint(x: 24, y: 300), control2: CGPoint(x: 18, y: 255))
        p.addCurve(to: CGPoint(x: 24, y: 72), control1: CGPoint(x: 12, y: 160), control2: CGPoint(x: 14, y: 105))
        p.addCurve(to: CGPoint(x: 100, y: 22), control1: CGPoint(x: 34, y: 40), control2: CGPoint(x: 60, y: 26))
        p.addCurve(to: CGPoint(x: 250, y: 24), control1: CGPoint(x: 140, y: 18), control2: CGPoint(x: 180, y: 24))
        p.closeSubpath()
        return p
    }()

    private static let leftBumper: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 30, y: 58))
        p.addCurve(to: CGPoint(x: 150, y: 8), control1: CGPoint(x: 44, y: 24), control2: CGPoint(x: 90, y: 8))
        p.addQuadCurve(to: CGPoint(x: 160, y: 22), control: CGPoint(x: 166, y: 9))
        p.addCurve(to: CGPoint(x: 42, y: 66), control1: CGPoint(x: 100, y: 22), control2: CGPoint(x: 58, y: 36))
        p.addQuadCurve(to: CGPoint(x: 30, y: 58), control: CGPoint(x: 30, y: 70))
        p.closeSubpath()
        return p
    }()

    private static let leftTrigger = Path(roundedRect: CGRect(x: 62, y: -28, width: 60, height: 26), cornerRadius: 11)

    private static let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 500, ty: 0)

    private func shell(_ ctx: inout GraphicsContext, _ body: Path, dark: Bool) {
        var shadow = ctx
        shadow.addFilter(.blur(radius: 22))
        shadow.translateBy(x: 0, y: 18)
        shadow.fill(body, with: .color(.black.opacity(0.45)))

        ctx.fill(body, with: .linearGradient(
            Gradient(colors: dark
                ? [.white.opacity(0.10), .white.opacity(0.04)]
                : [.white.opacity(0.30), .white.opacity(0.15), .white.opacity(0.20)]),
            startPoint: CGPoint(x: 250, y: 20), endPoint: CGPoint(x: 250, y: 340)))
        // A soft sheen across the upper half, like light on a translucent shell.
        var sheen = ctx
        sheen.clip(to: body)
        sheen.addFilter(.blur(radius: 26))
        sheen.fill(Path(ellipseIn: CGRect(x: 60, y: -40, width: 380, height: 140)), with: .color(.white.opacity(dark ? 0.04 : 0.10)))
        ctx.stroke(body, with: .linearGradient(Gradient(colors: [.white.opacity(0.45), .white.opacity(0.08)]),
                                               startPoint: CGPoint(x: 250, y: 20), endPoint: CGPoint(x: 250, y: 340)),
                   lineWidth: 1.2)
    }

    /// Any button-like part: dim glass when idle, glowing blue when pressed.
    private func part(_ ctx: inout GraphicsContext, _ shape: Path, on: Bool, label: String? = nil, labelAt: CGPoint? = nil) {
        if on {
            var g = ctx
            g.addFilter(.blur(radius: 10))
            g.fill(shape, with: .color(Theme.accent.opacity(0.9)))
        }
        ctx.fill(shape, with: on
            ? .linearGradient(Gradient(colors: [Theme.glow, Theme.accent]), startPoint: shape.boundingRect.origin,
                              endPoint: CGPoint(x: shape.boundingRect.maxX, y: shape.boundingRect.maxY))
            : .color(.white.opacity(0.10)))
        ctx.stroke(shape, with: .color(.white.opacity(on ? 0.6 : 0.18)), lineWidth: 0.8)
        if let label, let at = labelAt { tag(&ctx, label, at, on: on) }
    }

    private func trigger(_ ctx: inout GraphicsContext, _ shape: Path, _ value: UInt8, label: String, labelAt: CGPoint) {
        ctx.fill(shape, with: .color(.white.opacity(0.07)))
        ctx.stroke(shape, with: .color(.white.opacity(0.16)), lineWidth: 0.8)
        let f = CGFloat(value) / 255
        if f > 0 {
            let r = shape.boundingRect
            var fill = ctx
            fill.clip(to: shape)
            let level = Path(CGRect(x: r.minX, y: r.maxY - r.height * f, width: r.width, height: r.height * f))
            var g = fill
            g.addFilter(.blur(radius: 6))
            g.fill(level, with: .color(Theme.accent))
            fill.fill(level, with: .linearGradient(Gradient(colors: [Theme.glow, Theme.accent]),
                                                  startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        }
        tag(&ctx, label, labelAt, on: false)
    }

    private func stick(_ ctx: inout GraphicsContext, center c: CGPoint, _ p: StickPosition, clicked: Bool) {
        // Recessed well.
        let well = Path(ellipseIn: CGRect(x: c.x - 37, y: c.y - 37, width: 74, height: 74))
        ctx.fill(well, with: .radialGradient(Gradient(colors: [.black.opacity(0.55), .black.opacity(0.2)]),
                                             center: c, startRadius: 10, endRadius: 37))
        ctx.stroke(well, with: .color(.white.opacity(0.2)), lineWidth: 1)
        // Domed cap, following the stick.
        let travel: CGFloat = 12
        let dot = CGPoint(x: c.x + CGFloat(p.x) / 32767 * travel, y: c.y - CGFloat(p.y) / 32767 * travel)
        let cap = Path(ellipseIn: CGRect(x: dot.x - 26, y: dot.y - 26, width: 52, height: 52))
        let moved = abs(Int(p.x)) > 3000 || abs(Int(p.y)) > 3000
        if clicked || moved {
            var g = ctx
            g.addFilter(.blur(radius: 12))
            g.fill(cap, with: .color(Theme.accent.opacity(clicked ? 0.9 : 0.45)))
        }
        ctx.fill(cap, with: .radialGradient(
            Gradient(colors: clicked ? [Theme.glow, Theme.accent] : [.white.opacity(0.42), .white.opacity(0.16)]),
            center: CGPoint(x: dot.x - 7, y: dot.y - 9), startRadius: 2, endRadius: 32))
        ctx.stroke(cap, with: .color(.white.opacity(0.35)), lineWidth: 0.8)
        let grip = Path(ellipseIn: CGRect(x: dot.x - 17, y: dot.y - 17, width: 34, height: 34))
        ctx.stroke(grip, with: .color(.white.opacity(clicked ? 0.5 : 0.18)), lineWidth: 1)
    }

    /// The Apex 5's cushioned d-pad: a rounded square with a shallow cross pressed into it.
    private func dpad(_ ctx: inout GraphicsContext, center c: CGPoint, _ b: GamepadButtons) {
        let half: CGFloat = 34
        let pad = Path(roundedRect: CGRect(x: c.x - half, y: c.y - half, width: half * 2, height: half * 2), cornerRadius: 20)
        ctx.fill(pad, with: .radialGradient(Gradient(colors: [.white.opacity(0.42), .white.opacity(0.22)]),
                                            center: CGPoint(x: c.x - 8, y: c.y - 10), startRadius: 4, endRadius: 50))
        ctx.stroke(pad, with: .color(.white.opacity(0.35)), lineWidth: 0.8)
        var cross = Path()
        cross.move(to: CGPoint(x: c.x, y: c.y - half + 8)); cross.addLine(to: CGPoint(x: c.x, y: c.y + half - 8))
        cross.move(to: CGPoint(x: c.x - half + 8, y: c.y)); cross.addLine(to: CGPoint(x: c.x + half - 8, y: c.y))
        ctx.stroke(cross, with: .color(.black.opacity(0.18)), style: .init(lineWidth: 1, lineCap: .round))
        let w: CGFloat = 22
        let arms: [(GamepadButtons, CGRect)] = [
            (.dpadUp, CGRect(x: c.x - w / 2, y: c.y - half + 3, width: w, height: half - 8)),
            (.dpadDown, CGRect(x: c.x - w / 2, y: c.y + 5, width: w, height: half - 8)),
            (.dpadLeft, CGRect(x: c.x - half + 3, y: c.y - w / 2, width: half - 8, height: w)),
            (.dpadRight, CGRect(x: c.x + 5, y: c.y - w / 2, width: half - 8, height: w)),
        ]
        for (button, rect) in arms where b.contains(button) {
            part(&ctx, Path(roundedRect: rect, cornerRadius: 8), on: true)
        }
    }

    private func face(_ ctx: inout GraphicsContext, _ c: CGPoint, _ letter: String, _ on: Bool) {
        let shape = Path(ellipseIn: CGRect(x: c.x - 16, y: c.y - 16, width: 32, height: 32))
        if on {
            var g = ctx
            g.addFilter(.blur(radius: 10))
            g.fill(shape, with: .color(Theme.accent))
        }
        ctx.fill(shape, with: .radialGradient(
            Gradient(colors: on ? [Theme.glow, Theme.accent] : [.white.opacity(0.36), .white.opacity(0.12)]),
            center: CGPoint(x: c.x - 5, y: c.y - 6), startRadius: 1, endRadius: 20))
        ctx.stroke(shape, with: .color(.white.opacity(on ? 0.7 : 0.3)), lineWidth: 0.8)
        ctx.draw(Text(letter).font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.7)), at: c)
    }

    private func smallKey(_ ctx: inout GraphicsContext, center c: CGPoint, degrees: Double, icon: String, on: Bool) {
        let shape = Path(roundedRect: CGRect(x: -14, y: -7, width: 28, height: 14), cornerRadius: 7)
            .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180).concatenating(.init(translationX: c.x, y: c.y)))
        part(&ctx, shape, on: on)
        ctx.draw(Text(Image(systemName: icon)).font(.system(size: 7, weight: .bold))
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.6)), at: c)
    }

    /// Flydigi's winged mark, which is also the Home button.
    private func logo(_ ctx: inout GraphicsContext, center c: CGPoint, on: Bool) {
        var p = Path()
        p.move(to: CGPoint(x: c.x - 19, y: c.y - 12))
        p.addLine(to: CGPoint(x: c.x - 4, y: c.y - 6))
        p.addLine(to: CGPoint(x: c.x, y: c.y + 2))
        p.addLine(to: CGPoint(x: c.x + 4, y: c.y - 6))
        p.addLine(to: CGPoint(x: c.x + 19, y: c.y - 12))
        p.addLine(to: CGPoint(x: c.x + 3, y: c.y + 15))
        p.addLine(to: CGPoint(x: c.x, y: c.y + 11))
        p.addLine(to: CGPoint(x: c.x - 3, y: c.y + 15))
        p.closeSubpath()
        if on {
            var g = ctx
            g.addFilter(.blur(radius: 8))
            g.fill(p, with: .color(Theme.accent))
        }
        ctx.fill(p, with: .color(on ? Theme.glow : .white.opacity(0.55)))
    }

    private func tag(_ ctx: inout GraphicsContext, _ text: String, _ at: CGPoint, on: Bool) {
        ctx.draw(Text(text).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.6)
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.4)), at: at)
    }
}
