import ApexKit
import SwiftUI

/// The whole app on one screen: the controller in the middle, click any part of it to configure
/// that part in the panel that slides in. Profiles and device settings live in the header.
struct RootView: View {
    @Environment(ControllerService.self) private var service
    /// `-select <button>` on the command line opens with a control selected (used for screenshots).
    @ViewState private var selected: ControllerControl? = UserDefaults.standard.string(forKey: "select").flatMap { name in
        switch name.lowercased() {
        case "leftstick": .leftStick
        case "rightstick": .rightStick
        case "lighting": .lighting
        case "gyro": .gyro
        case "vibration": .vibration
        case "screen": .screen
        default: FlydigiKey.allCases.first { $0.name.lowercased() == name.lowercased() }.map { .key($0) }
        }
    }
    @ViewState private var hovered: ControllerControl?
    @ViewState private var showingSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()
            VStack(spacing: 18) {
                header
                HStack(alignment: .top, spacing: 18) {
                    stage
                    if let selected {
                        Inspector(control: selected) { self.selected = nil }
                            .frame(width: 340)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.35), value: selected)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 22)
        }
        .foregroundStyle(.white)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) { SettingsSheet() }
        .onAppear { service.liveViewAppeared() }
        .onDisappear { service.liveViewDisappeared() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            // Leaves room for the window's traffic lights.
            Color.clear.frame(width: 60, height: 1)
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.fill").foregroundStyle(Theme.accent)
                Text("APEX STATION").font(.system(size: 13, weight: .heavy)).tracking(3)
            }
            Spacer()
            ProfileSwitcher()
            Spacer()
            StatusBadge()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .glass(.circle, interactive: true)
            }
            .buttonStyle(.plain)
            .help("Controller and app settings")
        }
    }

    // MARK: - Controller stage

    private var stage: some View {
        ZStack(alignment: .bottom) {
            RadialGradient(colors: [Theme.accent.opacity(service.live ? 0.25 : 0.08), .clear],
                           center: .center, startRadius: 20, endRadius: 420)
            GeometryReader { geo in
                ControllerDrawing(state: service.state, live: service.live, profile: service.editingProfile,
                                  selected: selected, hovered: hovered)
                    .contentShape(.rect)
                    .onContinuousHover { phase in
                        if case .active(let p) = phase { hovered = ControllerDrawing.control(at: p, in: geo.size) } else { hovered = nil }
                    }
                    .onTapGesture(coordinateSpace: .local) { p in
                        let hit = ControllerDrawing.control(at: p, in: geo.size)
                        selected = hit == selected ? nil : hit
                    }
                    .pointerStyle(hovered == nil ? .default : .link)
            }
            .padding(28)
            HStack {
                ForEach([(ControllerControl.vibration, "Vibration", "waveform"), (.gyro, "Gyro", "gyroscope"), (.lighting, "Lighting", "lightbulb.led")], id: \.1) { c, title, icon in
                    let on = selected == c
                    Button { selected = on ? nil : c } label: {
                        Label(title, systemImage: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(on ? .white : Theme.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(on ? Theme.accent : Color.white.opacity(0.06), in: .capsule)
                            .overlay(Capsule().strokeBorder(on ? Theme.glow.opacity(0.6) : Theme.stroke))
                            .bloom(on, radius: 8)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                hint
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: 28))
        .background(Theme.panelShade, in: .rect(cornerRadius: 28))
        .glass(.rect(cornerRadius: 28))
    }

    @ViewBuilder private var hint: some View {
        let text: String? = if !service.connected && service.bluetooth {
            "Bluetooth shows the controller live. Use the cable to change settings"
        } else if !service.connected {
            "Plug in your Apex 5 with the USB-C cable, or pair it in PC Bluetooth mode"
        } else if service.fullControllerEnabled == false {
            "Turn on Full controller in settings to see live input"
        } else if selected == nil {
            "Click any part of the controller to change it"
        } else {
            nil
        }
        if let text {
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .glass(.capsule)
                .transition(.opacity)
        }
    }
}

/// The controller's four on-board profiles. Clicking one makes it active; edits go to the active one.
private struct ProfileSwitcher: View {
    @Environment(ControllerService.self) private var service
    @Namespace private var pill
    @ViewState private var renaming: Int?
    @ViewState private var resetting: Int?
    @ViewState private var newName = ""

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { slot in
                let profile = service.profiles.first { $0.slot == slot }
                let active = slot == service.activeProfile
                Button { Task { await service.useProfile(slot) } } label: {
                    HStack(spacing: 6) {
                        Text("\(slot + 1)").font(.system(size: 13, weight: .bold, design: .rounded))
                        if active, let profile { Text(displayName(profile)).font(.system(size: 12, weight: .medium)).lineLimit(1) }
                    }
                    .foregroundStyle(active ? .white : Theme.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        if active {
                            Capsule().fill(Theme.accent).matchedGeometryEffect(id: "active", in: pill).bloom(true, radius: 10)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(!service.connected)
                .contextMenu {
                    Button("Rename…") { renaming = slot; newName = profile.map(displayName) ?? "" }
                    Button("Reset to factory settings…", role: .destructive) { resetting = slot }
                }
                .help(profile.map { "Profile \(slot + 1): \(displayName($0))" + ($0.remapped.isEmpty ? "" : " · \($0.remapped.count) remapped") } ?? "Profile \(slot + 1)")
            }
        }
        .padding(4)
        .glass(.capsule)
        .animation(.spring(duration: 0.3), value: service.activeProfile)
        .alert("Rename profile", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name (up to 10 characters)", text: $newName)
            Button("Save") { if let slot = renaming { Task { await service.rename(slot: slot, to: newName) } } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Reset profile \((resetting ?? 0) + 1)?", isPresented: Binding(get: { resetting != nil }, set: { if !$0 { resetting = nil } })) {
            Button("Reset", role: .destructive) { if let slot = resetting { Task { await service.resetProfile(slot) } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its buttons, sticks, triggers and lighting go back to Flydigi's defaults. A backup is kept on your Mac.")
        }
    }
}

private struct StatusBadge: View {
    @Environment(ControllerService.self) private var service

    var body: some View {
        HStack(spacing: 10) {
            if !service.connected, let battery = service.bluetoothBattery {
                Label("\(battery)%", systemImage: "battery.100percent")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            } else if let info = service.info {
                Label("\(info.batteryPercent)%", systemImage: info.charging == .onBattery ? "battery.100percent" : "battery.100percent.bolt")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(service.live ? Theme.glow : service.connected || service.bluetooth ? Theme.accent : Color.white.opacity(0.25))
                    .frame(width: 7, height: 7)
                    .bloom(service.live, radius: 5)
                Text(text).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glass(.capsule)
    }

    private var text: String {
        if service.saving { return "Saving…" }
        if !service.connected && service.bluetooth { return service.live ? "Bluetooth · \(service.reportRate) Hz" : "Bluetooth" }
        if !service.connected { return "No controller" }
        return service.live ? "\(service.reportRate) Hz" : "Connected"
    }
}

/// Flydigi names new profiles "配置N" ("Config N").
func displayName(_ p: Profile) -> String {
    let name = p.name
    if name.isEmpty { return "Profile \(p.slot + 1)" }
    if name.hasPrefix("配置") { return "Config " + name.dropFirst(2) }
    return name
}
