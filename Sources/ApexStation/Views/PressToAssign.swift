import ApexKit
import SwiftUI

/// The one way to set something by pressing it: a card with the current value, Assign to wait
/// for the press (the card pulses while it waits), and a button to undo. Button remaps, the
/// gyro button and keyboard keys all use it.
struct AssignCard<Extra: View>: View {
    /// The current value, short.
    let chip: String
    /// True when it's set to something other than the default (the chip lights up).
    let isSet: Bool
    let title: String
    let subtitle: String
    let waiting: Bool
    let waitingTitle: String
    let waitingSubtitle: String
    var canAssign = true
    /// Why Assign is unavailable, shown under it.
    var unavailable: String?
    var resetTitle = "Default"
    let assign: () -> Void
    let cancel: () -> Void
    var reset: (() -> Void)?
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            card
            HStack(spacing: 8) {
                Button { waiting ? cancel() : assign() } label: {
                    Label(waiting ? "Cancel" : "Assign", systemImage: waiting ? "xmark" : "hand.point.up.left.fill")
                        .font(Theme.buttonFont)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .glass(.capsule, tint: waiting ? nil : Theme.accent.opacity(0.35), interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(!canAssign && !waiting)
                .opacity(!canAssign && !waiting ? 0.4 : 1)
                if let reset, isSet, !waiting {
                    Button(action: reset) {
                        Label(resetTitle, systemImage: "arrow.uturn.backward")
                            .font(Theme.buttonFont)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .glass(.capsule, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                if !waiting { extra }
            }
            if !canAssign, let unavailable {
                Text(unavailable).font(Theme.noteFont).foregroundStyle(Theme.label)
            }
        }
        .animation(.easeOut(duration: 0.18), value: waiting)
        .animation(.easeOut(duration: 0.18), value: chip)
    }

    private var card: some View {
        HStack(spacing: 14) {
            Text(chip)
                .font(.system(size: chip.count <= 2 ? 20 : chip.count <= 5 ? 15 : 11, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .frame(width: 56, height: 56)
                .foregroundStyle(isSet ? Color.white : Theme.secondary)
                .background(isSet ? Theme.accent : Color.white.opacity(0.06), in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isSet ? Theme.glow.opacity(0.6) : Theme.stroke))
                .bloom(isSet, radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(waiting ? waitingTitle : title).font(Theme.headingFont)
                Text(waiting ? waitingSubtitle : subtitle).font(Theme.detailFont).foregroundStyle(Theme.secondary)
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
}

extension AssignCard where Extra == EmptyView {
    init(chip: String, isSet: Bool, title: String, subtitle: String, waiting: Bool, waitingTitle: String, waitingSubtitle: String,
         canAssign: Bool = true, unavailable: String? = nil, resetTitle: String = "Default",
         assign: @escaping () -> Void, cancel: @escaping () -> Void, reset: (() -> Void)? = nil) {
        self.init(chip: chip, isSet: isSet, title: title, subtitle: subtitle, waiting: waiting, waitingTitle: waitingTitle,
                  waitingSubtitle: waitingSubtitle, canAssign: canAssign, unavailable: unavailable, resetTitle: resetTitle,
                  assign: assign, cancel: cancel, reset: reset) { EmptyView() }
    }
}

/// Remaps a button by example: Assign, then press the button it should act as on the
/// controller. Pressing the button itself puts it back to default.
struct PressToAssign: View {
    @Environment(ControllerService.self) private var service
    let key: FlydigiKey
    let current: KeyMapping
    @ViewState private var waiting = false

    var body: some View {
        AssignCard(chip: chip, isSet: current != .standard, title: title, subtitle: subtitle, waiting: waiting,
                   waitingTitle: "Press a button…",
                   waitingSubtitle: "Press the button \(key.name) should act as. Press \(key.name) itself for default.",
                   canAssign: service.canRead, unavailable: "Assigning needs Full controller, in settings.",
                   assign: listen, cancel: cancel,
                   reset: { Task { await service.remap(key, to: .standard) } })
            .onDisappear(perform: cancel)
    }

    private var chip: String {
        switch current {
        case .standard: key.shortName
        case .button(let k): k.shortName
        case .macro: "M"
        case .keyboardOrMouse: "⌨"
        case .unknown: "?"
        }
    }

    private var title: String {
        switch current {
        case .standard: "Its own button"
        case .button(let k): "Acts as \(k.name)"
        case .macro: "Runs a macro"
        case .keyboardOrMouse: "Keyboard or mouse"
        case .unknown: "Custom"
        }
    }

    private var subtitle: String {
        switch current {
        case .standard: "Assign, then press the button it should act as."
        case .button: "Pressing \(key.name) sends this instead."
        case .macro: "The macro is missing. Assign a button or record a new macro."
        case .keyboardOrMouse, .unknown: "Set up in Space Station."
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
