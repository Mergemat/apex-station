import ApexKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Command-line render modes. They run before the UI starts and exit afterwards.
///
///   ApexStation --render-icon <out.png> <pixels>
///       The app icon at one size (scripts/icon.ts builds the .icns from these).
///   ApexStation --render-crop <image> <out.png>
///       The screen crop window with that image, framed as it opens.
///   ApexStation --render-curve <out.png>
///       The stick curve editor with a sample curve (dead zone, bent middle, early edge).
@MainActor
enum RenderCommands {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), args.count > i + 2, let px = Double(args[i + 2]) {
            let renderer = ImageRenderer(content: AppIconView().frame(width: px, height: px))
            renderer.scale = 1
            if let image = renderer.cgImage { write(image, to: args[i + 1]) }
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-crop"), args.count > i + 2,
           let source = SourceAnimation(url: URL(fileURLWithPath: args[i + 1])) {
            let view = ScreenCropSheet(source: source, initial: .initial(for: source)) { _ in }
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.cgImage { write(image, to: args[i + 2]) }
            exit(0)
        }
        if let i = args.firstIndex(of: "--render-curve"), args.count > i + 1 {
            let config = StickConfig(curve: .custom, deadZone: 12, edge: 15, point1: .init(x: 40, y: 20), point2: .init(x: 90, y: 100))
            let view = CurveEditor(config: config, position: StickPosition(x: 18000, y: 9000), live: true) { _ in }
                .frame(width: 300, height: 260).padding(20).background(Theme.sheet).foregroundStyle(.white)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            if let image = renderer.cgImage { write(image, to: args[i + 1]) }
            exit(0)
        }
    }

    private static func write(_ image: CGImage, to file: String) {
        let url = URL(fileURLWithPath: file) as CFURL
        let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
