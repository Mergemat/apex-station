import ApexKit
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The controller's 160×80 display: put your own picture or GIF on it (framed with the crop
/// editor), or Flydigi's animation back, and choose what it shows.
struct ScreenPanel: View {
    @Environment(ControllerService.self) private var service
    @ViewState private var source: SourceAnimation?
    @ViewState private var selection: ScreenSelection?
    /// The picture being framed in the crop window.
    @ViewState private var cropping: SourceAnimation?
    @ViewState private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption("Animation")
            if let source, let selection {
                GeometryReader { geo in
                    ScreenPreview(source: source, selection: selection, scale: geo.size.width / CGFloat(Screen.width))
                }
                .aspectRatio(2, contentMode: .fit)
                HStack(spacing: 8) {
                    smallButton("Edit crop", icon: "crop") { cropping = source }
                    smallButton("Choose another", icon: "photo") { choose() }
                }
            } else {
                placeholder
                smallButton("Choose picture or GIF", icon: "photo") { choose() }
            }
            if let problem { Text(problem).font(Theme.noteFont).foregroundStyle(Theme.warning) }
            if let source, let selection {
                uploadButton(title: "Put it on the controller") {
                    let frames = (selection.first...selection.last).map { source.encoded(frame: $0, crop: selection.crop) }
                    await service.uploadScreen(frames, frameTime: source.frameTime)
                }
            }
            status
        }
        .sheet(item: $cropping) { item in
            ScreenCropSheet(source: item, initial: selection ?? .initial(for: item)) { chosen in
                source = item
                selection = chosen
            }
        }
        if service.defaultScreenFile != nil {
            VStack(alignment: .leading, spacing: 10) {
                Caption("Original")
                uploadButton(title: "Restore Flydigi animation", primary: false) { await service.restoreDefaultScreen() }
            }
        }
        if let s = service.settings {
            VStack(alignment: .leading, spacing: 14) {
                Caption("Display")
                if s.available.contains(.screenAnimation) {
                    SettingRow(title: "Animation", detail: "Off stops the animation; the controller's screen menus still work.") {
                        GlowToggle(isOn: Binding(get: { s.enabled.contains(.screenAnimation) }, set: { on in Task { await service.set(.screenAnimation, on) } }))
                    }
                }
                if s.available.contains(.screenStatusBarAlwaysOn) {
                    SettingRow(title: "Status bar always on", detail: "Otherwise a light press on Home shows it briefly.") {
                        GlowToggle(isOn: Binding(get: { s.enabled.contains(.screenStatusBarAlwaysOn) },
                                                 set: { on in Task { await service.set(.screenStatusBarAlwaysOn, on) } }))
                    }
                }
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.black)
            Text("160 × 80").font(Theme.monoFont.weight(.medium)).foregroundStyle(Theme.label)
        }
        .aspectRatio(2, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
    }

    private func smallButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(Theme.buttonFont)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .glass(.capsule, interactive: true)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var status: some View {
        switch service.screenUpload {
        case .sending(let p)?:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: p).tint(Theme.accent)
                Text("Sending… \(Int(p * 100))%. The controller is offline until it's done; keep the cable plugged in.")
                    .font(Theme.noteFont).foregroundStyle(Theme.label)
            }
        case .done?:
            Note("Done.")
        case .failed(let message)?:
            Text(message).font(Theme.noteFont).foregroundStyle(Theme.warning)
        case nil where service.connected && !service.canUploadScreen:
            Note("Uploading to the screen needs the USB cable.")
        case nil:
            EmptyView()
        }
    }

    private func uploadButton(title: String, primary: Bool = true, action: @escaping () async -> Void) -> some View {
        let enabled = service.canUploadScreen && !service.saving
        return Button { Task { await action() } } label: {
            Text(title)
                .font(Theme.buttonFont)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(primary && enabled ? Theme.accent : Color.white.opacity(0.06), in: .capsule)
                .foregroundStyle(enabled ? .white : Theme.label)
                .bloom(primary && enabled, radius: 8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .webP, .bmp, .tiff]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let animation = SourceAnimation(url: url) else {
            problem = "Couldn't read that image."
            return
        }
        problem = nil
        selection = nil
        cropping = animation
    }
}

/// The chosen picture or GIF, with its frames and timing.
struct SourceAnimation: Identifiable {
    let id = UUID()
    let name: String
    let frames: [CGImage]
    /// Time per frame from the GIF, in 10 ms steps, as the screen takes it.
    let frameTime: Int

    var count: Int { frames.count }
    var size: CGSize { CGSize(width: frames[0].width, height: frames[0].height) }

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var frames: [CGImage] = [], delays: [Double] = []
        for i in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(image)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            if let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] ?? gif?[kCGImagePropertyGIFDelayTime]) as? Double, d > 0 { delays.append(d) }
        }
        guard !frames.isEmpty else { return nil }
        name = url.lastPathComponent
        self.frames = frames
        let average = delays.isEmpty ? 0.1 : delays.reduce(0, +) / Double(delays.count)
        frameTime = max(1, min(255, Int((average * 100).rounded())))
    }

    /// Frame `i` with `crop` (in image pixels) drawn over a black 160×80 canvas.
    func render(frame i: Int, crop: CGRect) -> (image: CGImage, rgba: [UInt8])? {
        let w = Screen.width, h = Screen.height
        let image = frames[i]
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let made = rgba.withUnsafeMutableBytes { buf -> CGImage? in
            guard crop.width > 0, let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .high
            let scale = CGFloat(w) / crop.width
            let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            // CoreGraphics is y up; the crop is y down.
            ctx.draw(image, in: CGRect(x: -crop.minX * scale, y: CGFloat(h) - drawn.height + crop.minY * scale,
                                       width: drawn.width, height: drawn.height))
            return ctx.makeImage()
        }
        return made.map { ($0, rgba) }
    }

    func encoded(frame i: Int, crop: CGRect) -> [UInt8] {
        Screen.frame(rgba: render(frame: i, crop: crop)?.rgba ?? [UInt8](repeating: 0, count: Screen.width * Screen.height * 4))
    }
}
