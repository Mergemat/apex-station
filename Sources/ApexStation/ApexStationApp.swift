import ServiceManagement
import SwiftUI

@main
struct ApexStationApp: App {
    @ViewState private var service = ControllerService()

    var body: some Scene {
        Window("Apex Station", id: "main") {
            RootView()
                .environment(service)
                .task { service.startOnce() }
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent()
                .environment(service)
                .task { service.startOnce() }
        } label: {
            Image(systemName: service.connected ? "gamecontroller.fill" : "gamecontroller")
        }
    }
}

extension ControllerService {
    /// The menu bar item and the window both appear at launch; only start the hardware once.
    func startOnce() {
        guard !started else { return }
        started = true
        start()
    }
}

/// Open at login, backed by macOS's own login items.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Apex Station: login item change failed: \(error)")
        }
    }
}
