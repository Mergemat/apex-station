import ApexKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum RenderCommands {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-shape"), args.count > i + 6 {
            let v = args[(i + 2)...(i + 6)].compactMap(Double.init)
            renderShape(to: args[i + 1], size: CGSize(width: v[0], height: v[1]), origin: CGPoint(x: v[2], y: v[3]), width: v[4])
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-icon"), args.count > i + 2, let px = Double(args[i + 2]) {
            let renderer = ImageRenderer(content: AppIconView().frame(width: px, height: px))
            renderer.scale = 1
            if let image = renderer.cgImage { write(image, to: args[i + 1]) }
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-preview"), args.count > i + 1 {
            let scale = args.count > i + 2 ? Double(args[i + 2]) ?? 2 : 2
            renderPreview(to: args[i + 1], scale: scale)
            exit(0)
        }
    }

    private static func renderShape(to file: String, size: CGSize, origin: CGPoint, width: CGFloat) {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        // Image coordinates: origin top-left.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.addPath(ApexOutline.path(width: width, origin: origin).cgPath)
        ctx.fillPath()
        write(ctx.makeImage()!, to: file)
    }

    private static func renderPreview(to file: String, scale: Double) {
        var state = GamepadState()
        state.buttons = [.a, .leftBumper, .dpadUp, .m1, .leftMacro]
        state.leftTrigger = 180
        state.leftStick = StickPosition(x: 20000, y: 20000)
        let view = ControllerDrawing(state: state, live: true)
            .frame(width: 900, height: 760)
            .background(Theme.background)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        if let image = renderer.cgImage { write(image, to: file) }
    }

    private static func write(_ image: CGImage, to file: String) {
        let url = URL(fileURLWithPath: file) as CFURL
        let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
