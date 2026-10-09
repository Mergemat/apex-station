import ApexKit
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The controller's 160×80 display: put your own picture or GIF on it, or Flydigi's animation
/// back, and choose what it shows.
struct ScreenPanel: View {
    @Environment(ControllerService.self) private var service
    @ViewState private var picked: PickedAnimation?
    @ViewState private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Caption("Animation")
            preview
            HStack(spacing: 8) {
                Button { choose() } label: {
                    Label(picked == nil ? "Choose picture or GIF" : "Choose another", systemImage: "photo")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .glass(.capsule, interactive: true)
                }
                .buttonStyle(.plain)
            }
            if let problem { Text(problem).font(.system(size: 11.5)).foregroundStyle(.orange) }
            if let picked {
                Text("\(picked.name) · \(picked.frames.count) frame\(picked.frames.count == 1 ? "" : "s")\(picked.trimmed ? ", trimmed to \(Screen.maxFrames)" : "")")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.label)
                uploadButton(title: "Put it on the controller") { await service.uploadScreen(picked.encoded) }
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

    // MARK: Preview

    private var preview: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: (picked?.frames.count ?? 0) < 2)) { t in
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black)
                if let frames = picked?.frames, !frames.isEmpty {
                    let i = Int(t.date.timeIntervalSinceReferenceDate * 12) % frames.count
                    Image(decorative: frames[i], scale: 1).resizable().interpolation(.none)
                } else {
                    Text("Your picture here").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.label)
                }
            }
            .aspectRatio(2, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
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
        case nil where service.connected && !viaReceiver:
            Note("Uploading goes through Flydigi's 2.4 GHz receiver, like on Windows. Plug the receiver in and switch the controller to 2.4G mode.")
        case nil:
            Text("The controller plays frames at its own speed. Up to \(Screen.maxFrames) frames.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.label)
        }
    }

    /// Uploads go through Flydigi's 2.4 GHz receiver: Space Station sends them to the radio, in
    /// 64-byte packets the cable's 32-byte settings interface can't carry, and over the cable the
    /// controller ignores them.
    private var viaReceiver: Bool { service.info?.connection == .wireless }

    private func uploadButton(title: String, primary: Bool = true, action: @escaping () async -> Void) -> some View {
        let enabled = service.connected && viaReceiver && !service.saving
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

    // MARK: Picking

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .webP, .bmp, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let animation = PickedAnimation(url: url) {
            picked = animation
            problem = nil
        } else {
            problem = "Couldn't read that image."
        }
    }
}

/// A picture or GIF scaled to fill the 160×80 screen (centred, cropped), ready to upload.
struct PickedAnimation {
    let name: String
    let frames: [CGImage]
    let encoded: [[UInt8]]
    /// True when the GIF had more frames than the controller takes; every nth frame is kept.
    let trimmed: Bool

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        let picks = count > Screen.maxFrames
            ? (0..<Screen.maxFrames).map { $0 * count / Screen.maxFrames }
            : Array(0..<count)
        var frames: [CGImage] = [], encoded: [[UInt8]] = []
        for i in picks {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil),
                  let (frame, rgba) = Self.fill(image) else { continue }
            frames.append(frame)
            encoded.append(Screen.frame(rgba: rgba))
        }
        guard !frames.isEmpty else { return nil }
        name = url.lastPathComponent
        self.frames = frames
        self.encoded = encoded
        trimmed = count > Screen.maxFrames
    }

    /// Draws `image` over a black 160×80 canvas, scaled to cover it, and returns the canvas and its pixels.
    private static func fill(_ image: CGImage) -> (CGImage, [UInt8])? {
        let w = Screen.width, h = Screen.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let made = rgba.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .high
            let scale = max(CGFloat(w) / CGFloat(image.width), CGFloat(h) / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            ctx.draw(image, in: CGRect(x: (CGFloat(w) - size.width) / 2, y: (CGFloat(h) - size.height) / 2, width: size.width, height: size.height))
            return ctx.makeImage()
        }
        guard let made else { return nil }
        return (made, rgba)
    }
}
