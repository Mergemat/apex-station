import ApexKit
import SwiftUI

/// The app icon: the Apex 5's outline in frosted glass with a lit rim, on a deep blue tile.
/// Rendered to Resources/AppIcon.icns by `ApexStation --render-icon` (see scripts/icon.ts).
struct AppIconView: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 1024
            // Apple's icon grid: an 824 pt tile centred on a 1024 pt canvas.
            let tile = Path(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: s, y: s)),
                            cornerRadius: 185 * s, style: .continuous)
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: .black.opacity(0.45), radius: 18 * s, y: 10 * s))
                l.fill(tile, with: .linearGradient(Gradient(colors: [Color(red: 0.11, green: 0.18, blue: 0.38), Color(red: 0.02, green: 0.04, blue: 0.10)]),
                                                    startPoint: CGPoint(x: 0, y: 100 * s), endPoint: CGPoint(x: 0, y: 924 * s)))
            }
            ctx.clip(to: tile)
            ctx.fill(tile, with: .radialGradient(Gradient(colors: [Theme.accent.opacity(0.55), .clear]),
                                                 center: CGPoint(x: 512 * s, y: 600 * s), startRadius: 0, endRadius: 430 * s))

            // The controller, in ControllerDrawing's 500-wide space, scaled to ~700 pt wide.
            let shell = ApexOutline.path(width: 500, origin: CGPoint(x: 0, y: ControllerLayout.bodyTop))
            let box = shell.boundingRect
            let k = 700 * s / box.width
            let t = CGAffineTransform(translationX: 512 * s, y: 512 * s).scaledBy(x: k, y: k).translatedBy(x: -box.midX, y: -box.midY)
            let body = shell.applying(t)
            // Glow behind the shell, then the glass body, then a lit rim.
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 34 * s))
                l.stroke(body, with: .color(Theme.accent.opacity(0.9)), lineWidth: 26 * s)
            }
            let top = body.boundingRect.minY, bottom = body.boundingRect.maxY
            ctx.fill(body, with: .linearGradient(Gradient(colors: [Color(red: 0.42, green: 0.58, blue: 0.95).opacity(0.75), Color(red: 0.10, green: 0.17, blue: 0.40).opacity(0.85)]),
                                                 startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
            ctx.drawLayer { l in
                l.clip(to: body)
                l.fill(body,
                       with: .radialGradient(Gradient(colors: [Color.white.opacity(0.35), .clear]),
                                             center: CGPoint(x: 512 * s, y: top + 10 * s), startRadius: 0, endRadius: 200 * s))
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 6 * s))
                l.stroke(body, with: .color(Theme.glow), lineWidth: 10 * s)
            }
            ctx.stroke(body, with: .color(Color(red: 0.85, green: 0.92, blue: 1)), lineWidth: 5 * s)

            func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).applying(t)
            }
            let L = ControllerLayout.self
            for c in [L.leftStick, L.rightStick] {
                ctx.fill(circle(c, L.stickRadius), with: .color(Color(red: 0.03, green: 0.06, blue: 0.15).opacity(0.55)))
                ctx.fill(circle(c, L.stickRadius * 0.62), with: .color(.white.opacity(0.22)))
            }
            for c in [L.a, L.b, L.x, L.y] { ctx.fill(circle(c, L.faceRadius), with: .color(.white.opacity(0.28))) }
            ctx.fill(L.dpadCross.applying(t), with: .color(.white.opacity(0.28)))

            // A thin rim light on the tile edge.
            ctx.stroke(tile, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.04)]),
                                                   startPoint: CGPoint(x: 0, y: 100 * s), endPoint: CGPoint(x: 0, y: 924 * s)), lineWidth: 3 * s)
        }
    }
}
