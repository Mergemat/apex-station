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
    @ViewState private var crop = Crop()
    @ViewState private var first = 0
    @ViewState private var last = 0
    /// Time per frame, in 100 ms steps (what the controller takes).
    @ViewState private var period = 1
    @ViewState private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption("Animation")
            if let source {
                CropEditor(source: source, crop: $crop, range: first...last, period: period)
                cropControls(source)
            } else {
                placeholder
            }
            Button { choose() } label: {
                Label(source == nil ? "Choose picture or GIF" : "Choose another", systemImage: "photo")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .glass(.capsule, interactive: true)
            }
            .buttonStyle(.plain)
            if let problem { Text(problem).font(.system(size: 11.5)).foregroundStyle(.orange) }
            if let source {
                uploadButton(title: "Put it on the controller") {
                    let frames = (first...last).map { source.encoded(frame: $0, crop: crop) }
                    await service.uploadScreen(frames, period: period)
                }
            }
            status
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
            Text("160 × 80").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Theme.label)
        }
        .aspectRatio(2, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
    }

    @ViewBuilder private func cropControls(_ source: SourceAnimation) -> some View {
        HStack(spacing: 8) {
            ChipPicker(options: [true, false], selection: crop.fills, label: { $0 ? "Fill" : "Fit" }) { fills in
                crop = Crop(fills: fills)
            }
            Spacer()
            Text("Drag to move").font(.system(size: 11.5)).foregroundStyle(Theme.label)
        }
        ValueSlider(title: "Zoom", range: 100...400, unit: "%", value: Int(crop.zoom * 100)) { v in crop.zoom = Double(v) / 100 }
        if source.count > 1 {
            ValueSlider(title: "First frame", range: 1...Double(source.count), value: first + 1) { v in
                first = min(v - 1, last)
                last = min(last, first + Screen.maxFrames - 1)
            }
            ValueSlider(title: "Last frame", range: 1...Double(source.count), value: last + 1) { v in
                last = max(v - 1, first)
                first = max(first, last - Screen.maxFrames + 1)
            }
            ValueSlider(title: "Frame time", range: 1...20, unit: "00 ms", value: period) { v in period = v }
            Text("\(last - first + 1) of \(source.count) frames (up to \(Screen.maxFrames))")
                .font(.system(size: 11.5)).foregroundStyle(Theme.label)
        }
    }

    @ViewBuilder private var status: some View {
        switch service.screenUpload {
        case .sending(let p)?:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: p).tint(Theme.accent)
                Text("Sending… \(Int(p * 100))%. Keep the cable plugged in.").font(.system(size: 11.5)).foregroundStyle(Theme.label)
            }
        case .done?:
            Note("Done. Press the power button on the back of the controller to restart it, and the new screen shows.")
        case .failed(let message)?:
            Text(message).font(.system(size: 11.5)).foregroundStyle(.orange)
        case nil where service.connected && viaReceiver:
            Note("Uploading needs the USB-C cable; the 2.4 GHz receiver doesn't pass it on.")
        case nil:
            EmptyView()
        }
    }

    private var viaReceiver: Bool { service.info?.connection == .wireless }

    private func uploadButton(title: String, primary: Bool = true, action: @escaping () async -> Void) -> some View {
        let enabled = service.connected && !viaReceiver && !service.saving
        return Button { Task { await action() } } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 9)
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
        source = animation
        problem = nil
        crop = Crop()
        first = 0
        last = min(animation.count, Screen.maxFrames) - 1
        period = animation.period
    }
}

/// How a picture is framed on the 160×80 screen: fill or fit, zoom on top of that, and an offset
/// in screen pixels from centred.
struct Crop: Equatable {
    var fills = true
    var zoom = 1.0
    var offset = CGSize.zero

    /// The image's size on the screen, in screen pixels.
    func size(of image: CGSize) -> CGSize {
        let w = CGFloat(Screen.width), h = CGFloat(Screen.height)
        let base = fills ? max(w / image.width, h / image.height) : min(w / image.width, h / image.height)
        return CGSize(width: image.width * base * zoom, height: image.height * base * zoom)
    }

    /// Where the image goes on the screen (y down), with the offset kept so the image can't be
    /// dragged further than its own edge.
    func rect(for image: CGSize) -> CGRect {
        let s = size(of: image)
        let w = CGFloat(Screen.width), h = CGFloat(Screen.height)
        let maxX = abs(s.width - w) / 2, maxY = abs(s.height - h) / 2
        let dx = min(max(offset.width, -maxX), maxX), dy = min(max(offset.height, -maxY), maxY)
        return CGRect(x: (w - s.width) / 2 + dx, y: (h - s.height) / 2 + dy, width: s.width, height: s.height)
    }
}

/// The chosen picture or GIF, with its frames and timing.
struct SourceAnimation {
    let name: String
    let frames: [CGImage]
    /// Time per frame from the GIF, in 100 ms steps (1 for still pictures).
    let period: Int

    var count: Int { frames.count }

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
        period = max(1, min(20, Int((average * 10).rounded())))
    }

    /// Frame `i` drawn on a black 160×80 canvas as `crop` frames it.
    func render(frame i: Int, crop: Crop) -> (image: CGImage, rgba: [UInt8])? {
        let w = Screen.width, h = Screen.height
        let image = frames[i]
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let made = rgba.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .high
            let r = crop.rect(for: CGSize(width: image.width, height: image.height))
            // CoreGraphics is y up.
            ctx.draw(image, in: CGRect(x: r.minX, y: CGFloat(h) - r.maxY, width: r.width, height: r.height))
            return ctx.makeImage()
        }
        return made.map { ($0, rgba) }
    }

    func encoded(frame i: Int, crop: Crop) -> [UInt8] {
        Screen.frame(rgba: render(frame: i, crop: crop)?.rgba ?? [UInt8](repeating: 0, count: Screen.width * Screen.height * 4))
    }
}

/// Frames the picture in the screen's exact 160×80 pixels, shown at a whole-number scale so what
/// you see is what the controller gets. Drag to move; plays the chosen frames at the chosen speed.
private struct CropEditor: View {
    let source: SourceAnimation
    @Binding var crop: Crop
    let range: ClosedRange<Int>
    let period: Int
    @ViewState private var dragStart: CGSize?

    var body: some View {
        GeometryReader { geo in
            let scale = max(1, floor(geo.size.width / CGFloat(Screen.width)))
            TimelineView(.animation(minimumInterval: Double(period) / 10, paused: range.count < 2)) { t in
                let i = range.lowerBound + Int(t.date.timeIntervalSinceReferenceDate * 10 / Double(period)) % range.count
                if let frame = source.render(frame: i, crop: crop)?.image {
                    Image(decorative: frame, scale: 1).resizable().interpolation(.none)
                        .frame(width: CGFloat(Screen.width) * scale, height: CGFloat(Screen.height) * scale)
                }
            }
            .frame(width: CGFloat(Screen.width) * scale, height: CGFloat(Screen.height) * scale)
            .clipShape(.rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.stroke))
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .gesture(DragGesture()
                .onChanged { g in
                    let start = dragStart ?? crop.offset
                    dragStart = start
                    let s = crop.size(of: CGSize(width: source.frames[0].width, height: source.frames[0].height))
                    let maxX = abs(s.width - CGFloat(Screen.width)) / 2, maxY = abs(s.height - CGFloat(Screen.height)) / 2
                    crop.offset = CGSize(width: min(max(start.width + g.translation.width / scale, -maxX), maxX),
                                         height: min(max(start.height + g.translation.height / scale, -maxY), maxY))
                }
                .onEnded { _ in dragStart = nil })
        }
        .aspectRatio(2, contentMode: .fit)
    }
}
