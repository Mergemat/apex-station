import ApexKit
import SwiftUI

struct ControllerPage: View {
    @Environment(ControllerService.self) private var service
    @ViewState private var side: ControllerDrawing.Side = .front

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 18) {
                hero
                if service.live { LiveReadouts(state: service.state) }
            }
            VStack(spacing: 18) {
                if let info = service.info { BatteryCard(info: info) }
                if service.connected, service.fullControllerEnabled != nil { FullControllerCard() }
                if let info = service.info { FirmwareCard(info: info) }
            }
            .frame(width: 290)
        }
        .onAppear { service.liveViewAppeared() }
        .onDisappear { service.liveViewDisappeared() }
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(colors: [Theme.accent.opacity(service.live ? 0.28 : 0.10), .clear],
                           center: .center, startRadius: 20, endRadius: 380)
            ControllerDrawing(state: service.state, live: service.live, side: side)
                .rotation3DEffect(.degrees(side == .front ? 0 : 360), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .padding(.horizontal, 24)
                .padding(.top, 44)
                .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 6) {
                Text((service.info?.modelName ?? "Apex 5").uppercased())
                    .font(.system(size: 34, weight: .thin))
                    .tracking(8)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.label)
            }
            .padding(24)
            ChipPicker(options: [ControllerDrawing.Side.front, .back], selection: side,
                       label: { $0 == .front ? "Front" : "Back" }) { s in
                withAnimation(.spring(duration: 0.6)) { side = s }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topTrailing)
            if !service.connected {
                Label("Plug in your Apex 5 with the USB-C cable", systemImage: "cable.connector")
                    .font(.callout)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .glass(.capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 22)
            } else if service.fullControllerEnabled == false {
                Label("Turn on Full controller to see live input", systemImage: "sparkles")
                    .font(.callout)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .glass(.capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 22)
            }
        }
        .frame(height: 520)
        .clipShape(.rect(cornerRadius: 28))
        .glass(.rect(cornerRadius: 28))
        .animation(.easeOut(duration: 0.4), value: service.live)
    }

    private var subtitle: String {
        if !service.connected { return "Waiting for controller" }
        return service.live ? "Live · wired · \(service.reportRate) Hz" : "Wired"
    }
}

private struct BatteryCard: View {
    let info: DeviceInfo

    var body: some View {
        Card(title: "Battery") {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Theme.idle, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(info.batteryPercent) / 100)
                        .stroke(Theme.accent, style: .init(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .bloom(true, radius: 6)
                    Image(systemName: info.charging == .onBattery ? "battery.100percent" : "bolt.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.glow)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(info.batteryPercent)%").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    Text(chargingText).font(.system(size: 12)).foregroundStyle(Theme.label)
                }
            }
        }
    }

    private var chargingText: String {
        switch info.charging {
        case .onBattery: "On battery"
        case .charging: "Charging"
        case .charged: "Fully charged"
        }
    }
}

private struct FullControllerCard: View {
    @Environment(ControllerService.self) private var service
    @ViewState private var busy = false

    var body: some View {
        Card(title: "Full controller") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(service.fullControllerEnabled == true ? "On" : "Off")
                        .font(.system(size: 20, weight: .semibold))
                    Spacer()
                    GlowToggle(isOn: Binding(
                        get: { service.fullControllerEnabled ?? false },
                        set: { on in
                            busy = true
                            Task { await service.setFullController(on); busy = false }
                        }), disabled: busy)
                }
                Text("Back paddles, gyro and 1000 Hz in Steam and SDL games, plus the live view here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FirmwareCard: View {
    @Environment(ControllerService.self) private var service
    let info: DeviceInfo

    var body: some View {
        Card(title: "Controller") {
            VStack(spacing: 10) {
                row("Firmware", info.firmware)
                row("Motion", info.sensorFirmware)
                row("Radio", info.radioFirmware)
                Button {
                    Task { await service.testRumble() }
                } label: {
                    Label("Test rumble", systemImage: "waveform")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .glass(.capsule, tint: Theme.accent.opacity(0.35), interactive: true)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
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
}

private struct LiveReadouts: View {
    let state: GamepadState

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Card(title: "Triggers", fillHeight: true) {
                Meter(label: "LT", value: Double(state.leftTrigger) / 255)
                Meter(label: "RT", value: Double(state.rightTrigger) / 255)
            }
            Card(title: "Gyro", fillHeight: true) {
                if let m = state.motion {
                    Meter(label: "X", value: Double(m.gyro.x) / 8000, centered: true)
                    Meter(label: "Y", value: Double(m.gyro.y) / 8000, centered: true)
                    Meter(label: "Z", value: Double(m.gyro.z) / 8000, centered: true)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A thin glowing bar. `centered` draws from the middle for signed values (-1…1).
struct Meter: View {
    let label: String
    let value: Double
    var centered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.label).frame(width: 18, alignment: .leading)
            GeometryReader { g in
                let w = g.size.width
                let v = centered ? max(-1, min(1, value)) : max(0, min(1, value))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.idle)
                    Capsule().fill(Theme.accent)
                        .frame(width: max(3, abs(v) * (centered ? w / 2 : w)))
                        .offset(x: centered ? (v >= 0 ? w / 2 : w / 2 - abs(v) * w / 2) : 0)
                        .bloom(abs(v) > 0.05, radius: 5)
                }
            }
            .frame(height: 6)
        }
    }
}
