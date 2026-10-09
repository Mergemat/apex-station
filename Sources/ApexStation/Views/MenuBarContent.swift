import ApexKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(ControllerService.self) private var service
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)
        if let info = service.info {
            Text("Battery \(info.batteryPercent)%\(info.charging == .onBattery ? "" : " · charging")")
        }
        Divider()
        Button("Open Apex Station…") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Test Rumble") { Task { await service.testRumble() } }
            .disabled(!service.connected)
        Divider()
        Button("Quit Apex Station") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        service.connected ? "\(service.info?.modelName ?? "Apex 5") connected" : "No controller"
    }
}
