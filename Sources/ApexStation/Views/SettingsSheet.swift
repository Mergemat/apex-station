import ApexKit
import AppKit
import SwiftUI

/// Controller-wide settings and app settings, behind the gear in the header.
struct SettingsSheet: View {
    @Environment(ControllerService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled
    @ViewState private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings").font(Theme.titleFont)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(spacing: 14) {
                    if service.connected {
                        controller
                    } else if service.bluetooth {
                        Card(title: "Controller") {
                            Note(service.cableNote("its settings"))
                            Button { Task { await service.testRumble() } } label: {
                                Label("Test rumble", systemImage: "waveform").frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .glass(.capsule, tint: Theme.accent.opacity(0.35), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    app
                }
            }
            .scrollIndicators(.never)
        }
        .padding(24)
        .frame(width: 560, height: 620)
        .background(Theme.sheet)
        .foregroundStyle(.white)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var xboxDetail: String {
        switch service.padStatus {
        case .on: "On: games see a standard Xbox controller with the controller's own remaps, gyro-to-stick and macros, at about 1000 Hz, like on Windows. It stays on from the menu bar while the window is closed."
        case .blocked: "macOS didn't allow it on this Mac."
        default: "Games see a standard Xbox controller over the cable, with the controller's own remaps, gyro-to-stick and macros, like on Windows."
        }
    }

    @ViewBuilder private var controller: some View {
        Card(title: "Controller") {
            VStack(spacing: 14) {
                SettingRow(title: "Xbox controller for games", detail: xboxDetail) {
                    GlowToggle(isOn: Binding(get: { service.xboxForGames }, set: { service.setXboxForGames($0) }))
                }
                if service.padStatus == .blocked {
                    Note("macOS only lets Apple-signed apps make a virtual controller. On this Mac it needs AMFI relaxed: run sudo nvram boot-args=\"amfi_get_out_of_my_way=1\" in Terminal and restart. This loosens code-signing checks for the whole Mac.")
                        .textSelection(.enabled)
                }
                if service.fullControllerEnabled != nil, !service.padActive {
                    SettingRow(title: "Full controller", detail: "Steam and SDL games read the controller directly: back paddles, gyro, 1000 Hz. They use their own settings then, so the controller's remaps, gyro-to-stick and macros apply only over Bluetooth or in Switch mode.") {
                        GlowToggle(isOn: Binding(get: { service.fullControllerEnabled ?? false }, set: { on in
                            busy = true
                            Task { await service.setFullController(on); busy = false }
                        }), disabled: busy)
                    }
                }
                if let s = service.settings {
                    SettingRow(title: "Sleep after", detail: "Press Home to wake it again.", stacked: true) {
                        ChipPicker(options: DeviceSettings.sleepOptions, selection: s.sleepMinutes, label: sleepLabel) { m in
                            Task { await service.setSleep(minutes: m) }
                        }
                    }
                    SettingRow(title: "Polling rate", detail: "How often the controller reports. Lower saves battery on wireless.", stacked: true) {
                        ChipPicker(options: [DeviceSettings.ReportRate.hz125, .hz250, .hz500, .hz1000], selection: s.reportRate ?? .hz1000,
                                   label: { "\($0.hertz) Hz" }) { r in Task { await service.setReportRate(r) } }
                    }
                    toggle(s, .quickProfileSwitch, "Fast Swap Config", "Fn + A, B, X or Y switches between the four profiles.")
                    toggle(s, .xboxHomeButton, "Home acts as Xbox button", "Sends the Xbox Guide button when you press Home.")
                    toggle(s, .audio, "Audio", "The headphone jack on the controller.")
                }
                Button { Task { await service.testRumble() } } label: {
                    Label("Test rumble", systemImage: "waveform").frame(maxWidth: .infinity).padding(.vertical, 8)
                        .glass(.capsule, tint: Theme.accent.opacity(0.35), interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
        if let info = service.info {
            Card(title: "About this controller") {
                VStack(spacing: 8) {
                    row("Model", info.modelName)
                    row("Firmware", info.firmware)
                    row("Motion sensor", info.sensorFirmware)
                    row("Radio", info.radioFirmware)
                    row("Battery", "\(info.batteryPercent)%")
                }
            }
        }
    }

    private var app: some View {
        Card(title: "Apex Station") {
            VStack(spacing: 14) {
                SettingRow(title: "Keyboard & mouse", detail: "Buttons, sticks and gyro you've set to keys or the mouse type and move the pointer. Needs Accessibility permission.") {
                    GlowToggle(isOn: Binding(get: { service.keyboardMouseOn }, set: { service.setKeyboardMouse($0) }))
                }
                SettingRow(title: "Open at login", detail: "Keeps battery status in the menu bar. Games don't need the app running.") {
                    GlowToggle(isOn: Binding(get: { launchAtLogin }, set: { launchAtLogin = $0; LaunchAtLogin.set($0) }))
                }
                SettingRow(title: "Profile backups", detail: "Every profile is saved to your Mac before anything on the controller changes.") {
                    Button("Show") { NSWorkspace.shared.open(ProfileBackup.folder) }
                }
            }
        }
    }

    @ViewBuilder
    private func toggle(_ s: DeviceSettings, _ sw: DeviceSettings.Switch, _ title: String, _ detail: String) -> some View {
        if s.available.contains(sw) {
            SettingRow(title: title, detail: detail) {
                GlowToggle(isOn: Binding(get: { s.enabled.contains(sw) }, set: { on in Task { await service.set(sw, on) } }))
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.detailFont).foregroundStyle(Theme.label)
            Spacer()
            Text(value).font(Theme.monoFont).foregroundStyle(Theme.secondary)
        }
    }

    private func sleepLabel(_ m: Int) -> String {
        switch m {
        case 0: "Never"
        case 60...: "\(m / 60) h"
        default: "\(m) min"
        }
    }
}
