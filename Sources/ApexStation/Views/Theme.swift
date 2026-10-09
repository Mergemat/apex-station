import SwiftUI

enum Theme {
    /// Electric blue, the app's primary colour.
    static let accent = Color(red: 0x3E / 255, green: 0x85 / 255, blue: 0xF6 / 255)
    /// Lighter blue for glows and highlights.
    static let glow = Color(red: 0x7F / 255, green: 0xB2 / 255, blue: 0xFF / 255)

    static let background = Color(red: 0.010, green: 0.015, blue: 0.034)
    /// Sheets: the same navy the main panel shows, so they don't read as black.
    static let sheet = Color(red: 0.065, green: 0.09, blue: 0.16)
    /// Deep navy over the main glass panel so it reads darker without going black.
    static let panelShade = Color(red: 0.03, green: 0.055, blue: 0.13).opacity(0.5)
    static let idle = Color.white.opacity(0.09)
    static let stroke = Color.white.opacity(0.10)
    static let label = Color.white.opacity(0.42)
    static let secondary = Color.white.opacity(0.62)
}

extension View {
    /// Liquid Glass on macOS 26+, frosted material before that.
    @ViewBuilder
    func glass(_ shape: some Shape = .rect(cornerRadius: 22), tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background((tint ?? .clear).opacity(0.25), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Theme.stroke))
        }
    }

    /// A soft blue bloom behind active elements.
    func bloom(_ on: Bool, radius: CGFloat = 18) -> some View {
        shadow(color: Theme.accent.opacity(on ? 0.65 : 0), radius: on ? radius : 0)
    }
}

/// Deep navy with slow-drifting blue light, the backdrop for all the glass.
struct AppBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { t in
            let phase = t.date.timeIntervalSinceReferenceDate / 14
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.background))
                let blobs: [(CGFloat, CGFloat, CGFloat, Double)] = [
                    (0.18, 0.15, 0.55, 0.26), (0.85, 0.30, 0.45, 0.16), (0.55, 0.95, 0.60, 0.13),
                ]
                var g = ctx
                g.addFilter(.blur(radius: 90))
                for (i, (x, y, r, a)) in blobs.enumerated() {
                    let dx = CGFloat(sin(phase + Double(i) * 2.1)) * 0.06
                    let dy = CGFloat(cos(phase * 0.8 + Double(i))) * 0.05
                    let radius = r * max(size.width, size.height) / 2
                    let c = CGPoint(x: (x + dx) * size.width, y: (y + dy) * size.height)
                    g.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(Theme.accent.opacity(a)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// A glass card with an optional uppercase title.
struct Card<Content: View>: View {
    var title: String?
    var padding: CGFloat = 20
    /// Stretch to the height of the row it sits in.
    var fillHeight = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title { Caption(title) }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
        .glass()
    }
}

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Theme.label)
    }
}

/// A glowing pill switch.
struct GlowToggle: View {
    @Binding var isOn: Bool
    var disabled = false

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.accent : Theme.idle)
                    .overlay(Capsule().stroke(isOn ? Theme.glow.opacity(0.6) : Theme.stroke))
                Circle().fill(.white).frame(width: 18, height: 18).padding(3)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .frame(width: 44, height: 24)
            .bloom(isOn, radius: 10)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .animation(.spring(duration: 0.25), value: isOn)
    }
}

/// A row of selectable glass chips.
struct ChipPicker<Value: Hashable>: View {
    let options: [Value]
    let selection: Value?
    let label: (Value) -> String
    let onSelect: (Value) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { onSelect(option) } label: {
                    Text(label(option))
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(selected ? .white : Theme.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selected ? Theme.accent : Color.white.opacity(0.05), in: .capsule)
                        .overlay(Capsule().stroke(selected ? Theme.glow.opacity(0.5) : Theme.stroke))
                        .bloom(selected, radius: 8)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.18), value: selection)
    }
}

/// Title and explanation on the left, a control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    /// Puts the control under the text, for wide controls like a row of chips.
    var stacked = false
    @ViewBuilder var control: Control

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 10) {
                text
                control
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 16) {
                text
                Spacer(minLength: 12)
                control
            }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13.5, weight: .medium))
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Lays views out left to right, starting a new row when the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.items + [i], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([i], size.width, size.height))
            }
        }
        return rows
    }
}
