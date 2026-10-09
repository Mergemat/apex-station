import ApexKit
import AppKit
import SwiftUI

/// Frames a picture or GIF for the controller's 160×80 screen: the whole image with a 2:1 crop
/// frame on top (drag to move, corners to resize, pinch to zoom), an exact 160×80 preview, and
/// for GIFs the frames to keep.
struct ScreenCropSheet: View {
    let source: SourceAnimation
    let initial: ScreenSelection
    let done: (ScreenSelection) -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewState private var selection = ScreenSelection(crop: .zero, first: 0, last: 0)
    @ViewState private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Frame the picture").font(.system(size: 20, weight: .semibold))
                    Text("\(source.name.count > 40 ? String(source.name.prefix(37)) + "…" : source.name) · \(Int(source.size.width))×\(Int(source.size.height))\(source.count > 1 ? " · \(source.count) frames" : "")")
                        .font(.system(size: 12)).foregroundStyle(Theme.label)
                }
                Spacer()
            }
            HStack(alignment: .top, spacing: 20) {
                CropCanvas(source: source, crop: $selection.crop)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.35), in: .rect(cornerRadius: 14))
                    .clipShape(.rect(cornerRadius: 14))
                sidebar.frame(width: 340)
            }
            HStack(spacing: 10) {
                Button("Fill") { selection.crop = ScreenSelection.filling(source.size) }
                    .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7).glass(.capsule, interactive: true)
                Button("Whole image") { selection.crop = ScreenSelection.fitting(source.size) }
                    .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7).glass(.capsule, interactive: true)
                Text("Drag the frame to move it, its corners to resize, or pinch to zoom.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.label)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Use") { done(selection); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 900, height: 600)
        .background(Theme.sheet)
        .foregroundStyle(.white)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            guard !loaded else { return }
            selection = initial
            loaded = true
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Caption("On the controller · 160 × 80")
                ScreenPreview(source: source, selection: selection, scale: 2)
            }
            if source.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    ValueSlider(title: "First frame", range: 1...Double(source.count), value: selection.first + 1) { v in
                        selection.first = min(v - 1, selection.last)
                        selection.last = min(selection.last, selection.first + Screen.maxFrames - 1)
                    }
                    ValueSlider(title: "Last frame", range: 1...Double(source.count), value: selection.last + 1) { v in
                        selection.last = max(v - 1, selection.first)
                        selection.first = max(selection.first, selection.last - Screen.maxFrames + 1)
                    }
                    Text("Keeping \(selection.last - selection.first + 1) of \(source.count) frames. The controller takes up to \(Screen.maxFrames) and plays them at its own speed.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.label).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
    }
}

/// What will go on the screen: the part of the image (in image pixels, 2:1; it may reach past
/// the image, which shows as black) and the frames to keep.
struct ScreenSelection: Equatable {
    var crop: CGRect
    var first: Int
    var last: Int

    static let aspect = CGFloat(Screen.width) / CGFloat(Screen.height)

    /// The largest 2:1 area inside the image, centred.
    static func filling(_ size: CGSize) -> CGRect {
        let w = min(size.width, size.height * aspect), h = w / aspect
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    /// The smallest 2:1 area holding the whole image, centred (black bars where it's empty).
    static func fitting(_ size: CGSize) -> CGRect {
        let w = max(size.width, size.height * aspect), h = w / aspect
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    static func initial(for source: SourceAnimation) -> ScreenSelection {
        ScreenSelection(crop: filling(source.size), first: 0, last: min(source.count, Screen.maxFrames) - 1)
    }
}

/// The image with the crop frame over it. Everything is in image pixels, mapped to the view.
private struct CropCanvas: View {
    let source: SourceAnimation
    @Binding var crop: CGRect

    private enum Grab: Equatable { case move, corner(xMin: Bool, yMin: Bool) }
    @ViewState private var grab: Grab?
    @ViewState private var startCrop = CGRect.zero
    @ViewState private var pinchStart: CGRect?

    var body: some View {
        GeometryReader { geo in
            let map = Mapping(source: source.size, crop: crop, view: geo.size)
            ZStack {
                Image(decorative: source.frames[0], scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: map.imageRect.width, height: map.imageRect.height)
                    .position(x: map.imageRect.midX, y: map.imageRect.midY)
                Canvas { ctx, size in
                    let r = map.view(crop)
                    // Dim everything outside the frame.
                    var outside = Path(CGRect(origin: .zero, size: size))
                    outside.addRect(r)
                    ctx.fill(outside, with: .color(.black.opacity(0.6)), style: FillStyle(eoFill: true))
                    // Rule of thirds.
                    var grid = Path()
                    for f in [1.0 / 3, 2.0 / 3] {
                        grid.move(to: CGPoint(x: r.minX + r.width * f, y: r.minY)); grid.addLine(to: CGPoint(x: r.minX + r.width * f, y: r.maxY))
                        grid.move(to: CGPoint(x: r.minX, y: r.minY + r.height * f)); grid.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * f))
                    }
                    ctx.stroke(grid, with: .color(.white.opacity(0.25)), lineWidth: 0.5)
                    ctx.stroke(Path(r), with: .color(.white), lineWidth: 1.5)
                    // Corner handles.
                    for p in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                        let h = Path(roundedRect: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12), cornerRadius: 3)
                        ctx.fill(h, with: .color(.white))
                        ctx.stroke(h, with: .color(Theme.accent), lineWidth: 1.5)
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in drag(g, map: map) }
                .onEnded { _ in grab = nil })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { g in
                    let start = pinchStart ?? crop
                    pinchStart = start
                    crop = clamp(resized(start, width: start.width / g.magnification))
                }
                .onEnded { _ in pinchStart = nil })
        }
    }

    private func drag(_ g: DragGesture.Value, map: Mapping) {
        if grab == nil {
            startCrop = crop
            let r = map.view(crop), p = g.startLocation
            let corners: [(CGPoint, Grab)] = [
                (CGPoint(x: r.minX, y: r.minY), .corner(xMin: true, yMin: true)), (CGPoint(x: r.maxX, y: r.minY), .corner(xMin: false, yMin: true)),
                (CGPoint(x: r.minX, y: r.maxY), .corner(xMin: true, yMin: false)), (CGPoint(x: r.maxX, y: r.maxY), .corner(xMin: false, yMin: false)),
            ]
            if let hit = corners.first(where: { hypot($0.0.x - p.x, $0.0.y - p.y) < 16 }) {
                grab = hit.1
            } else {
                grab = .move
            }
        }
        let dx = g.translation.width / map.scale, dy = g.translation.height / map.scale
        switch grab {
        case .move?:
            crop = clamp(startCrop.offsetBy(dx: dx, dy: dy))
        case .corner(let xMin, let yMin)?:
            // Keep the opposite corner fixed and the 2:1 shape; follow whichever way moved more.
            let s = startCrop
            let wFromX = xMin ? s.width - dx : s.width + dx
            let wFromY = (yMin ? s.height - dy : s.height + dy) * ScreenSelection.aspect
            var w = abs(wFromX - s.width) >= abs(wFromY - s.width) ? wFromX : wFromY
            w = min(max(w, minWidth), maxWidth)
            let h = w / ScreenSelection.aspect
            let x = xMin ? s.maxX - w : s.minX, y = yMin ? s.maxY - h : s.minY
            crop = clamp(CGRect(x: x, y: y, width: w, height: h), keepSize: true)
        case nil:
            break
        }
    }

    private var minWidth: CGFloat { min(40, source.size.width) }
    private var maxWidth: CGFloat { ScreenSelection.fitting(source.size).width }

    private func resized(_ r: CGRect, width: CGFloat) -> CGRect {
        let w = min(max(width, minWidth), maxWidth), h = w / ScreenSelection.aspect
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    /// Keeps the frame over the image: inside it when smaller, covering it when bigger.
    private func clamp(_ r: CGRect, keepSize: Bool = false) -> CGRect {
        var r = r
        let size = source.size
        func fit(_ origin: CGFloat, _ length: CGFloat, _ total: CGFloat) -> CGFloat {
            length <= total ? min(max(origin, 0), total - length) : min(max(origin, total - length), 0)
        }
        r.origin.x = fit(r.minX, r.width, size.width)
        r.origin.y = fit(r.minY, r.height, size.height)
        return r
    }
}

/// Where the image and the frame land in the canvas: both fitted with a margin.
private struct Mapping {
    let scale: CGFloat
    let offset: CGPoint
    let imageRect: CGRect

    init(source: CGSize, crop: CGRect, view: CGSize) {
        let bounds = CGRect(origin: .zero, size: source).union(crop)
        let margin: CGFloat = 24
        scale = min((view.width - margin * 2) / bounds.width, (view.height - margin * 2) / bounds.height)
        offset = CGPoint(x: (view.width - bounds.width * scale) / 2 - bounds.minX * scale,
                         y: (view.height - bounds.height * scale) / 2 - bounds.minY * scale)
        imageRect = CGRect(x: offset.x, y: offset.y, width: source.width * scale, height: source.height * scale)
    }

    func view(_ r: CGRect) -> CGRect {
        CGRect(x: offset.x + r.minX * scale, y: offset.y + r.minY * scale, width: r.width * scale, height: r.height * scale)
    }
}

/// The 160×80 result at a whole-number scale, playing the kept frames.
struct ScreenPreview: View {
    let source: SourceAnimation
    let selection: ScreenSelection
    var scale: CGFloat = 2

    var body: some View {
        let range = selection.first...selection.last
        TimelineView(.animation(minimumInterval: Double(source.period) / 10, paused: range.count < 2)) { t in
            let i = range.lowerBound + Int(t.date.timeIntervalSinceReferenceDate * 10 / Double(source.period)) % range.count
            if let frame = source.render(frame: i, crop: selection.crop)?.image {
                Image(decorative: frame, scale: 1).resizable().interpolation(.none)
            }
        }
        .frame(width: CGFloat(Screen.width) * scale, height: CGFloat(Screen.height) * scale)
        .background(Color.black)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.stroke))
    }
}
