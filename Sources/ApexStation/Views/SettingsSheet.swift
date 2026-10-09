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
                Text("Settings").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(spacing: 16) {
                    if service.connected { controller }
                    app
                }
            }
            .scrollIndicators(.never)
        }
        .padding(24)
        .frame(width: 560, height: 620)
        .background(Theme.background)
        .foregroundStyle(.white)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var controller: some View {
        Card(title: "Controller") {
            VStack(spacing: 16) {
                if service.fullControllerEnabled != nil {
                    SettingRow(title: "Full controller", detail: "Back paddles, gyro and 1000 Hz in Steam and SDL games, plus the live view here.") {
                        GlowToggle(isOn: Binding(get: { service.fullControllerEnabled ?? false }, set: { on in
                            busy = true
                            Task { await service.setFullController(on); busy = false }
                        }), disabled: busy)
                    }
                }
                if let s = service.settings {
                    SettingRow(title: "Sleep after", detail: "Press Home to wake it again.") {
                        ChipPicker(options: DeviceSettings.sleepOptions, selection: s.sleepMinutes, label: sleepLabel) { m in
                            Task { await service.setSleep(minutes: m) }
                        }
                    }
                    toggle(s, .quickProfileSwitch, "Fast Swap Config", "Fn + A, B, X or Y switches between the four profiles.")
                    toggle(s, .xboxHomeButton, "Home acts as Xbox button", "Sends the Xbox Guide button when you press Home.")
                    if s.available.contains(.screenOff) {
                        SettingRow(title: "Screen", detail: "The display on the controller.") {
                            GlowToggle(isOn: Binding(get: { !s.enabled.contains(.screenOff) }, set: { on in Task { await service.set(.screenOff, !on) } }))
                        }
                    }
                    toggle(s, .screenStatusBarAlwaysOn, "Status bar always on", "Otherwise a light press on Home shows it briefly.")
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
            VStack(spacing: 16) {
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
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.label)
            Spacer()
            Text(value).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Theme.secondary)
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
