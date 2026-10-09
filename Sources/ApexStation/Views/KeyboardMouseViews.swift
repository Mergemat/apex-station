import ApexKit
import AppKit
import SwiftUI

/// Picks the key or mouse action a button sends while keyboard & mouse is on: press the key on
/// your keyboard, or choose a click or scroll.
struct KeyAssign: View {
    @Environment(ControllerService.self) private var service
    let key: FlydigiKey
    @ViewState private var listening = false
    @ViewState private var monitor: Any?

    var body: some View {
        let current = service.keyboardMouseMap[key]
        VStack(alignment: .leading, spacing: 10) {
            AssignCard(chip: current.map(chip) ?? key.shortName, isSet: current != nil,
                       title: current.map { "Sends \($0.label)" } ?? "Nothing yet",
                       subtitle: "Assign, then press a key on your keyboard, or pick a mouse action.",
                       waiting: listening, waitingTitle: "Press a key…",
                       waitingSubtitle: "Press the key \(key.name) should send.",
                       resetTitle: "Clear", assign: listen, cancel: stop, reset: { set(nil) }) {
                Menu {
                    ForEach(KeyboardMouseMap.MouseButton.allCases, id: \.self) { b in
                        Button(KeyboardMouseMap.Output.mouse(b).label) { set(.mouse(b)) }
                    }
                    Divider()
                    Button("Scroll up") { set(.scroll(up: true)) }
                    Button("Scroll down") { set(.scroll(up: false)) }
                } label: {
                    Label("Mouse", systemImage: "computermouse")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .glass(.capsule, interactive: true)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            }
            KeyboardMouseStatus()
        }
        .onDisappear(perform: stop)
    }

    /// Short form for the card's chip.
    private func chip(_ out: KeyboardMouseMap.Output) -> String {
        switch out {
        case .key(_, let label): label
        case .mouse(.left): "L"
        case .mouse(.right): "R"
        case .mouse(.middle): "M"
        case .scroll(true): "↑"
        case .scroll(false): "↓"
        }
    }

    private func set(_ out: KeyboardMouseMap.Output?) {
        service.editKeyboardMouse { $0[key] = out }
    }

    private func listen() {
        listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Any key counts, Esc included (games use it); a modifier counts when it goes down.
            if event.type == .flagsChanged, !Self.isModifierDown(event) { return nil }
            set(.key(code: event.keyCode, label: Self.label(for: event)))
            stop()
            return nil
        }
    }

    private func stop() {
        listening = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func isModifierDown(_ e: NSEvent) -> Bool {
        switch e.keyCode {
        case 56, 60: e.modifierFlags.contains(.shift)
        case 59, 62: e.modifierFlags.contains(.control)
        case 58, 61: e.modifierFlags.contains(.option)
        case 55, 54: e.modifierFlags.contains(.command)
        case 57: true
        default: false
        }
    }

    private static let names: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc", 117: "Fwd Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        56: "Shift", 60: "Right Shift", 59: "Control", 62: "Right Control", 58: "Option", 61: "Right Option",
        55: "Command", 54: "Right Command", 57: "Caps Lock",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func label(for e: NSEvent) -> String {
        if let name = names[e.keyCode] { return name }
        let chars = (e.charactersIgnoringModifiers ?? "").uppercased()
        return chars.isEmpty ? "Key \(e.keyCode)" : chars
    }
}

/// Whether keyboard & mouse is actually working, and what to do if it isn't.
struct KeyboardMouseStatus: View {
    @Environment(ControllerService.self) private var service

    var body: some View {
        if !service.keyboardMouseOn {
            HStack {
                Text("Keyboard & mouse is off.").font(.system(size: 11.5)).foregroundStyle(Theme.label)
                Spacer()
                Button("Turn on") { service.setKeyboardMouse(true) }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.glow)
            }
        } else if !KeyboardMouseOutput.isTrusted {
            HStack(alignment: .top) {
                Text("Allow Apex Station under Privacy & Security → Accessibility so it can type and move the pointer.")
                    .font(.system(size: 11.5)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Open") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.glow)
            }
        } else if !service.live {
            Text(service.connected ? "Needs Full controller, in settings." : "Connect the controller to use it.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.label)
        } else {
            Text("Saved on this Mac for profile \((service.activeProfile ?? 0) + 1).")
                .font(.system(size: 11.5)).foregroundStyle(Theme.label)
        }
    }
}

/// What a stick does while keyboard & mouse is on: stay a stick, press four keys, or move the pointer.
struct StickActsAs: View {
    @Environment(ControllerService.self) private var service
    let left: Bool

    private enum Choice: Hashable { case stick, wasd, arrows, mouse }

    var body: some View {
        let mode = left ? service.keyboardMouseMap.leftStick : service.keyboardMouseMap.rightStick
        VStack(alignment: .leading, spacing: 10) {
            Caption("Keyboard & mouse")
            ChipPicker(options: [Choice.stick, .wasd, .arrows, .mouse], selection: choice(mode), label: label) { c in
                let new: KeyboardMouseMap.StickMode = switch c {
                case .stick: .stick
                case .wasd: .wasd
                case .arrows: .arrows
                case .mouse: .mouse(sensitivity: 50)
                }
                set(new)
            }
            if case .mouse(let sensitivity) = mode {
                ValueSlider(title: "Pointer speed", range: 1...100, value: sensitivity) { v in set(.mouse(sensitivity: v)) }
            }
            if mode != .stick { KeyboardMouseStatus() }
        }
    }

    private func set(_ mode: KeyboardMouseMap.StickMode) {
        service.editKeyboardMouse { map in
            if left { map.leftStick = mode } else { map.rightStick = mode }
        }
    }

    private func choice(_ m: KeyboardMouseMap.StickMode) -> Choice {
        switch m {
        case .stick: .stick
        case .mouse: .mouse
        case .keys: m == .arrows ? .arrows : .wasd
        }
    }

    private func label(_ c: Choice) -> String {
        switch c {
        case .stick: "Stick"
        case .wasd: "WASD"
        case .arrows: "Arrows"
        case .mouse: "Mouse"
        }
    }
}
