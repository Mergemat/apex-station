import ApexKit
import SwiftUI

/// A clean, gamepad-shaped map of every Apex 5 control, all visible at once: shoulders on top,
/// face controls on the body, the four back paddles underneath. Built to be read at a glance,
/// not to copy the hardware. Drawn in a 500×430 space and scaled to fit.
struct ControllerDrawing: View {
    let state: GamepadState
    let live: Bool

    private static let space = CGSize(width: 500, height: 430)

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

    private func draw(_ ctx: inout GraphicsContext) {
        // Shoulders: triggers show how far they're pulled; bumpers and the extra LM/RM below.
        trigger(&ctx, CGRect(x: 52, y: 6, width: 116, height: 26), "LT", live ? state.leftTrigger : 0)
        trigger(&ctx, CGRect(x: 332, y: 6, width: 116, height: 26), "RT", live ? state.rightTrigger : 0)
        key(&ctx, .capsule(CGRect(x: 52, y: 40, width: 116, height: 24)), "LB", b.contains(.leftBumper))
        key(&ctx, .capsule(CGRect(x: 332, y: 40, width: 116, height: 24)), "RB", b.contains(.rightBumper))
        key(&ctx, .capsule(CGRect(x: 178, y: 40, width: 52, height: 24)), "LM", b.contains(.leftMacro))
        key(&ctx, .capsule(CGRect(x: 270, y: 40, width: 52, height: 24)), "RM", b.contains(.rightMacro))

        shell(&ctx)

        stick(&ctx, CGPoint(x: 126, y: 152), live ? state.leftStick : .init(), "L3", b.contains(.leftStick))
        stick(&ctx, CGPoint(x: 314, y: 232), live ? state.rightStick : .init(), "R3", b.contains(.rightStick))
        dpad(&ctx, CGPoint(x: 186, y: 232))
        key(&ctx, .circle(CGPoint(x: 374, y: 186), 15), "A", b.contains(.a))
        key(&ctx, .circle(CGPoint(x: 408, y: 152), 15), "B", b.contains(.b))
        key(&ctx, .circle(CGPoint(x: 340, y: 152), 15), "X", b.contains(.x))
        key(&ctx, .circle(CGPoint(x: 374, y: 118), 15), "Y", b.contains(.y))
        iconKey(&ctx, .capsule(CGRect(x: 196, y: 120, width: 34, height: 18)), "rectangle.on.rectangle", b.contains(.back))
        iconKey(&ctx, .capsule(CGRect(x: 270, y: 120, width: 34, height: 18)), "line.3.horizontal", b.contains(.start))
        home(&ctx, CGPoint(x: 250, y: 129), b.contains(.guide))
        key(&ctx, .capsule(CGRect(x: 214, y: 168, width: 34, height: 16)), "TURBO", b.contains(.c), small: true)
        key(&ctx, .capsule(CGRect(x: 252, y: 168, width: 34, height: 16)), "FN", b.contains(.z), small: true)
        lightBar(&ctx)

        // The four back paddles, kept on their side and in their row.
        caption(&ctx, "BACK PADDLES", CGPoint(x: 250, y: 352))
        key(&ctx, .capsule(CGRect(x: 92, y: 340, width: 92, height: 26)), "M2", b.contains(.m2))
        key(&ctx, .capsule(CGRect(x: 92, y: 374, width: 92, height: 26)), "M4", b.contains(.m4))
        key(&ctx, .capsule(CGRect(x: 316, y: 340, width: 92, height: 26)), "M1", b.contains(.m1))
        key(&ctx, .capsule(CGRect(x: 316, y: 374, width: 92, height: 26)), "M3", b.contains(.m3))
    }

    // MARK: - Body

    private func shell(_ ctx: inout GraphicsContext) {
        var p = Path()
        p.move(to: CGPoint(x: 250, y: 76))
        p.addCurve(to: CGPoint(x: 438, y: 82), control1: CGPoint(x: 330, y: 76), control2: CGPoint(x: 400, y: 72))
        p.addCurve(to: CGPoint(x: 484, y: 200), control1: CGPoint(x: 474, y: 92), control2: CGPoint(x: 486, y: 140))
        p.addCurve(to: CGPoint(x: 446, y: 322), control1: CGPoint(x: 482, y: 262), control2: CGPoint(x: 476, y: 310))
        p.addCurve(to: CGPoint(x: 380, y: 296), control1: CGPoint(x: 420, y: 332), control2: CGPoint(x: 394, y: 320))
        p.addCurve(to: CGPoint(x: 250, y: 282), control1: CGPoint(x: 356, y: 284), control2: CGPoint(x: 300, y: 282))
        p.addCurve(to: CGPoint(x: 120, y: 296), control1: CGPoint(x: 200, y: 282), control2: CGPoint(x: 144, y: 284))
        p.addCurve(to: CGPoint(x: 54, y: 322), control1: CGPoint(x: 106, y: 320), control2: CGPoint(x: 80, y: 332))
        p.addCurve(to: CGPoint(x: 16, y: 200), control1: CGPoint(x: 24, y: 310), control2: CGPoint(x: 18, y: 262))
        p.addCurve(to: CGPoint(x: 62, y: 82), control1: CGPoint(x: 14, y: 140), control2: CGPoint(x: 26, y: 92))
        p.addCurve(to: CGPoint(x: 250, y: 76), control1: CGPoint(x: 100, y: 72), control2: CGPoint(x: 170, y: 76))
        p.closeSubpath()

        var shadow = ctx
        shadow.addFilter(.blur(radius: 24))
        shadow.translateBy(x: 0, y: 16)
        shadow.fill(p, with: .color(.black.opacity(0.4)))
        ctx.fill(p, with: .linearGradient(Gradient(colors: [.white.opacity(0.14), .white.opacity(0.05)]),
                                          startPoint: CGPoint(x: 250, y: 76), endPoint: CGPoint(x: 250, y: 330)))
        ctx.stroke(p, with: .linearGradient(Gradient(colors: [.white.opacity(0.35), .white.opacity(0.08)]),
                                            startPoint: CGPoint(x: 250, y: 76), endPoint: CGPoint(x: 250, y: 330)),
                   lineWidth: 1.2)
    }

    private func lightBar(_ ctx: inout GraphicsContext) {
        var bar = Path()
        bar.move(to: CGPoint(x: 150, y: 293))
        bar.addCurve(to: CGPoint(x: 350, y: 293), control1: CGPoint(x: 200, y: 278), control2: CGPoint(x: 300, y: 278))
        if live {
            var g = ctx
            g.addFilter(.blur(radius: 6))
            g.stroke(bar, with: .color(Theme.accent), style: .init(lineWidth: 6, lineCap: .round))
        }
        ctx.stroke(bar, with: .color(live ? Theme.glow : .white.opacity(0.12)), style: .init(lineWidth: 2, lineCap: .round))
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
            ctx.fill(p, with: .color(.white.opacity(0.09)))
        }
        ctx.stroke(p, with: .color(.white.opacity(on ? 0.55 : 0.16)), lineWidth: 0.8)
    }

    private func key(_ ctx: inout GraphicsContext, _ s: Shape, _ label: String, _ on: Bool, small: Bool = false) {
        let p = path(s)
        fill(&ctx, p, on: on)
        ctx.draw(Text(label).font(.system(size: small ? 7.5 : 11, weight: .bold, design: .rounded)).tracking(0.4)
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.55)),
                 at: CGPoint(x: p.boundingRect.midX, y: p.boundingRect.midY))
    }

    private func iconKey(_ ctx: inout GraphicsContext, _ s: Shape, _ icon: String, _ on: Bool) {
        let p = path(s)
        fill(&ctx, p, on: on)
        ctx.draw(Text(Image(systemName: icon)).font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(on ? Color.white : Color.white.opacity(0.6)),
                 at: CGPoint(x: p.boundingRect.midX, y: p.boundingRect.midY))
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
        ctx.stroke(p, with: .color(.white.opacity(f > 0 ? 0.5 : 0.16)), lineWidth: 0.8)
        ctx.draw(Text(label).font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(f > 0.4 ? Color.white : Color.white.opacity(0.55)), at: CGPoint(x: r.midX, y: r.midY))
    }

    private func stick(_ ctx: inout GraphicsContext, _ c: CGPoint, _ pos: StickPosition, _ label: String, _ clicked: Bool) {
        let well = path(.circle(c, 38))
        ctx.fill(well, with: .color(.black.opacity(0.28)))
        ctx.stroke(well, with: .color(.white.opacity(0.14)), lineWidth: 1)
        // Faint crosshair so movement reads clearly.
        var cross = Path()
        cross.move(to: CGPoint(x: c.x - 30, y: c.y)); cross.addLine(to: CGPoint(x: c.x + 30, y: c.y))
        cross.move(to: CGPoint(x: c.x, y: c.y - 30)); cross.addLine(to: CGPoint(x: c.x, y: c.y + 30))
        ctx.stroke(cross, with: .color(.white.opacity(0.07)), lineWidth: 1)
        let travel: CGFloat = 16
        // Up-positive Y; screen Y grows downwards.
        let p = CGPoint(x: c.x + CGFloat(pos.x) / 32767 * travel, y: c.y - CGFloat(pos.y) / 32767 * travel)
        let moved = abs(Int(pos.x)) > 3000 || abs(Int(pos.y)) > 3000
        let cap = path(.circle(p, 21))
        fill(&ctx, cap, on: clicked)
        if moved && !clicked {
            ctx.stroke(cap, with: .color(Theme.glow.opacity(0.8)), lineWidth: 1.5)
        }
        ctx.draw(Text(label).font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(clicked ? Color.white : Color.white.opacity(0.35)), at: p)
    }

    /// Four separate arrow keys, so each direction reads on its own.
    private func dpad(_ ctx: inout GraphicsContext, _ c: CGPoint) {
        let size: CGFloat = 25, gap: CGFloat = 15
        let keys: [(GamepadButtons, CGPoint, String)] = [
            (.dpadUp, CGPoint(x: c.x, y: c.y - gap - size / 2), "chevron.up"),
            (.dpadDown, CGPoint(x: c.x, y: c.y + gap + size / 2), "chevron.down"),
            (.dpadLeft, CGPoint(x: c.x - gap - size / 2, y: c.y), "chevron.left"),
            (.dpadRight, CGPoint(x: c.x + gap + size / 2, y: c.y), "chevron.right"),
        ]
        for (button, p, icon) in keys {
            iconKey(&ctx, .rounded(CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size), 8), icon, b.contains(button))
        }
    }

    private func home(_ ctx: inout GraphicsContext, _ c: CGPoint, _ on: Bool) {
        fill(&ctx, path(.circle(c, 15)), on: on)
        var v = Path()
        v.move(to: CGPoint(x: c.x - 8, y: c.y - 5))
        v.addLine(to: CGPoint(x: c.x, y: c.y + 6))
        v.addLine(to: CGPoint(x: c.x + 8, y: c.y - 5))
        ctx.stroke(v, with: .color(on ? .white : .white.opacity(0.6)), style: .init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }

    private func caption(_ ctx: inout GraphicsContext, _ text: String, _ at: CGPoint) {
        ctx.draw(Text(text).font(.system(size: 8.5, weight: .semibold)).tracking(2).foregroundStyle(Theme.label), at: at)
    }
}
