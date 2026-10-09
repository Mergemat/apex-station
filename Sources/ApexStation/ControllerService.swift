import ApexKit
import Foundation
import Observation

/// Everything the app knows about the connected Apex 5, and the actions it can take.
///
/// Games don't need this app: with "Full controller" on, SDL (Steam and most Mac games) drives
/// the Apex 5 itself. The app configures the controller and shows it live. While the live view is
/// open the app holds the controller and reads its own input stream (paddles, gyro); the
/// controller hands itself back ~15 s after we stop refreshing, so nothing stays stuck.
@MainActor @Observable
final class ControllerService {
    private(set) var connected = false
    private(set) var info: DeviceInfo?
    /// The controller's "allow third-party apps" switch. Needed for SDL games and the live view.
    private(set) var fullControllerEnabled: Bool?
    private(set) var state = GamepadState()
    /// True while the live view holds the controller.
    private(set) var live = false
    /// Input reports per second while live.
    private(set) var reportRate = 0
    /// Settings stored on the controller.
    private(set) var settings: DeviceSettings?

    @ObservationIgnored var started = false
    @ObservationIgnored private let channel = SettingsChannel()
    @ObservationIgnored private var liveViewers = 0
    @ObservationIgnored private var keepAlive: Task<Void, Never>?

    func start() {
        channel.start()
        Task { await watchChannel() }
        Task { await refreshUI() }
    }

    // MARK: - Settings

    func setFullController(_ on: Bool) async {
        _ = try? await channel.request(Flydigi.setDataStreams(thirdPartyControl: on))
        await loadStatus()
        if on, liveViewers > 0 { beginLive() }
        if !on { endLive() }
    }

    func set(_ s: DeviceSettings.Switch, _ on: Bool) async { await apply(Flydigi.set(s, on)) }
    func setSleep(minutes: Int) async { await apply(Flydigi.setSleep(minutes: minutes)) }
    func setPrecision(_ p: DeviceSettings.Precision) async { await apply(Flydigi.setPrecision(p)) }
    func setSensitivity(_ s: DeviceSettings.Sensitivity) async { await apply(Flydigi.setSensitivity(s)) }

    /// Writes a setting, then reads everything back so the UI shows what the controller actually stored.
    private func apply(_ frame: Data) async {
        _ = try? await channel.request(frame)
        await loadSettings()
    }

    private func loadSettings() async {
        if let reply = try? await channel.request(Flydigi.readSettings()) {
            settings = DeviceSettings(reply: reply)
        }
    }

    func testRumble() async {
        try? await channel.send(Flydigi.frame(.rumble, [0xC0, 0xC0, 0, 0]))
        try? await Task.sleep(for: .milliseconds(350))
        try? await channel.send(Flydigi.frame(.rumble, [0, 0, 0, 0]))
    }

    // MARK: - Live view

    /// Views showing live input call this on appear/disappear; the controller is held while any are visible.
    func liveViewAppeared() {
        liveViewers += 1
        if liveViewers == 1 { beginLive() }
    }

    func liveViewDisappeared() {
        liveViewers = max(0, liveViewers - 1)
        if liveViewers == 0 { endLive() }
    }

    private func beginLive() {
        guard keepAlive == nil, connected, fullControllerEnabled == true else { return }
        keepAlive = Task {
            while !Task.isCancelled {
                if let reply = try? await channel.request(Flydigi.acquire(true)) {
                    live = Flydigi.acquireGranted(reply) ?? false
                }
                // Well inside the controller's ~15 s release timeout.
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func endLive() {
        keepAlive?.cancel()
        keepAlive = nil
        guard live else { return }
        live = false
        state = GamepadState()
        Task { try? await channel.send(Flydigi.acquire(false)) }
    }

    // MARK: - Channel

    private func watchChannel() async {
        for await event in channel.eventStream {
            switch event {
            case .connected:
                connected = true
                await loadInfo()
                await loadStatus()
                await loadSettings()
                if liveViewers > 0 { beginLive() }
            case .disconnected:
                connected = false
                info = nil
                settings = nil
                fullControllerEnabled = nil
                keepAlive?.cancel()
                keepAlive = nil
                live = false
                state = GamepadState()
            }
        }
    }

    private func loadInfo() async {
        for _ in 0..<3 {
            if let reply = try? await channel.request(Flydigi.frame(.getInfo)), let info = DeviceInfo(reply: reply) {
                self.info = info
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    private func loadStatus() async {
        if let reply = try? await channel.request(Flydigi.frame(.getStatus)) {
            fullControllerEnabled = Flydigi.thirdPartyAllowed(reply)
        }
    }

    /// Redraw at display rate, not at the controller's ~1000 Hz.
    private func refreshUI() async {
        var lastCount = channel.live.snapshot().count
        var lastRateAt = ContinuousClock.now
        // Turbo and Fn are combo keys: the controller only reports them as a brief pulse when
        // they're released on their own, so their highlight is held long enough to see.
        var pulseUntil: [UInt32: ContinuousClock.Instant] = [:]
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let snap = channel.live.snapshot()
            var shown = snap.state
            let now = ContinuousClock.now
            for key in [GamepadButtons.turbo, .fn] {
                if snap.state.buttons.contains(key) { pulseUntil[key.rawValue] = now + .milliseconds(500) }
                if let until = pulseUntil[key.rawValue], until > now { shown.buttons.insert(key) }
            }
            if live, shown != state { state = shown }
            if ContinuousClock.now - lastRateAt >= .seconds(1) {
                reportRate = live ? snap.count - lastCount : 0
                lastCount = snap.count
                lastRateAt = .now
            }
        }
    }
}
