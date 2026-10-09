import ApexKit
import SwiftUI

struct DevicePage: View {
    @Environment(ControllerService.self) private var service
    @ViewState private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(spacing: 18) {
            if let s = service.settings {
                ControllerSettings(settings: s)
            } else {
                Card { Text("Connect your Apex 5 to change its settings.").foregroundStyle(Theme.secondary) }
            }
            Card(title: "Apex Station") {
                SettingRow(title: "Open at login", detail: "Keeps battery status in the menu bar. Games don't need the app running.") {
                    GlowToggle(isOn: Binding(get: { launchAtLogin },
                                             set: { launchAtLogin = $0; LaunchAtLogin.set($0) }))
                }
            }
        }
    }
}

private struct ControllerSettings: View {
    @Environment(ControllerService.self) private var service
    let settings: DeviceSettings

    var body: some View {
        Card(title: "Controller") {
            VStack(spacing: 18) {
                SettingRow(title: "Sleep after", detail: "Press Home to wake it again.") {
                    ChipPicker(options: DeviceSettings.sleepOptions, selection: settings.sleepMinutes, label: sleepLabel) { m in
                        Task { await service.setSleep(minutes: m) }
                    }
                }
                Divider().overlay(Theme.stroke)
                toggle(.quickProfileSwitch, "Fast Swap Config", "Switch between the controller's 4 configs with a button combo + A/B/X/Y.")
                toggle(.xboxHomeButton, "Home acts as Xbox button", "Sends the Xbox Guide button when you press Home.")
                if settings.available.contains(.screenOff) {
                    SettingRow(title: "Screen", detail: "The display on the controller.") {
                        GlowToggle(isOn: Binding(get: { !settings.enabled.contains(.screenOff) },
                                                 set: { on in Task { await service.set(.screenOff, !on) } }))
                    }
                }
                toggle(.screenStatusBarAlwaysOn, "Status bar always on", "Otherwise a light press on Home shows it briefly.")
                toggle(.audio, "Audio", nil)
            }
        }
    }

    @ViewBuilder
    private func toggle(_ s: DeviceSettings.Switch, _ title: String, _ detail: String?) -> some View {
        if settings.available.contains(s) {
            SettingRow(title: title, detail: detail) {
                GlowToggle(isOn: Binding(get: { settings.enabled.contains(s) },
                                         set: { on in Task { await service.set(s, on) } }))
            }
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
