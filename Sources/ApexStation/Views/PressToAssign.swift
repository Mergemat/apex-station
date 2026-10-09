import ApexKit
import SwiftUI

/// Remaps a button by example: click Assign, then press the button it should act as on the
/// controller. Pressing the button itself puts it back to default.
struct PressToAssign: View {
    @Environment(ControllerService.self) private var service
    let key: FlydigiKey
    let current: KeyMapping
    @ViewState private var waiting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            card
            actions
            if !service.canRead {
                Text("Assigning needs Full controller, in settings.").font(.system(size: 11.5)).foregroundStyle(Theme.label)
            }
        }
        .animation(.easeOut(duration: 0.18), value: waiting)
        .animation(.easeOut(duration: 0.18), value: current)
        .onDisappear(perform: cancel)
    }

    private var chip: some View {
        Text(targetLabel)
            .font(.system(size: target == nil ? 15 : 20, weight: .bold, design: .rounded))
            .frame(width: 56, height: 56)
            .foregroundStyle(remapped ? Color.white : Theme.secondary)
            .background(remapped ? Theme.accent : Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(remapped ? Theme.glow.opacity(0.6) : Theme.stroke))
            .bloom(remapped, radius: 10)
    }

    private var card: some View {
        HStack(spacing: 14) {
            chip
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(waiting ? 0.08 : 0.04), in: .rect(cornerRadius: 18))
        .overlay { border }
        .bloom(waiting, radius: 10)
    }

    @ViewBuilder private var border: some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        if waiting {
            shape.strokeBorder(Theme.glow, lineWidth: 1.5)
                .phaseAnimator([1.0, 0.3]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 0.7) }
        } else {
            shape.strokeBorder(Theme.stroke, lineWidth: 1)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { if waiting { cancel() } else { listen() } } label: {
                Label(waiting ? "Cancel" : "Assign", systemImage: waiting ? "xmark" : "gamecontroller.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .glass(.capsule, tint: waiting ? nil : Theme.accent.opacity(0.35), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(!service.canRead && !waiting)
            .opacity(!service.canRead && !waiting ? 0.4 : 1)
            if remapped && !waiting {
                Button { Task { await service.remap(key, to: .standard) } } label: {
                    Label("Default", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .glass(.capsule, interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var target: FlydigiKey? {
        if case .button(let k) = current { k } else { nil }
    }

    private var remapped: Bool { current != .standard }

    private var targetLabel: String {
        switch current {
        case .standard: key.shortName
        case .button(let k): k.shortName
        case .macro: "M"
        case .keyboardOrMouse: "⌨"
        case .unknown: "?"
        }
    }

    private var title: String {
        if waiting { return "Press a button…" }
        switch current {
        case .standard: return "Its own button"
        case .button(let k): return "Acts as \(k.name)"
        case .macro: return "Runs a macro"
        case .keyboardOrMouse: return "Keyboard or mouse"
        case .unknown: return "Custom"
        }
    }

    private var subtitle: String {
        if waiting { return "Press the button \(key.name) should act as. Press \(key.name) itself for default." }
        switch current {
        case .standard: return "Click Assign, then press the button it should act as."
        case .button: return "Pressing \(key.name) sends this instead."
        case .macro: return "The macro is missing. Assign a button or record a new macro."
        case .keyboardOrMouse: return "Set up in Space Station."
        case .unknown: return "Set up in Space Station."
        }
    }

    private func listen() {
        waiting = true
        Task {
            let pressed = await service.nextPress()
            guard waiting else { return }
            waiting = false
            guard let pressed else { return }
            await service.remap(key, to: pressed == key ? .standard : .button(pressed))
        }
    }

    private func cancel() {
        guard waiting else { return }
        waiting = false
        service.cancelListening()
    }
}
