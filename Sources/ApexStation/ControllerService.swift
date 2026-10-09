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
    /// The controller's four on-board profiles, and which one is active.
    private(set) var profiles: [Profile] = []
    private(set) var activeProfile: Int?

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

    /// The profile button changes go to: the one the controller is using.
    var editingProfile: Profile? { profiles.first { $0.slot == (activeProfile ?? 0) } }
    /// True while a profile write is in flight.
    private(set) var saving = false

    func remap(_ key: FlydigiKey, to mapping: KeyMapping) async {
        await edit { $0.setMapping(mapping, for: key) }
    }

    func setTurbo(_ key: FlydigiKey, _ turbo: (mode: TurboMode, speed: UInt8)?) async {
        await edit { $0.setTurbo(turbo, for: key) }
    }

    /// Applies `change` to the active profile, writes only what changed, then reads the profile
    /// back so the app shows what the controller actually stored.
    private func edit(_ change: (inout Profile) -> Void) async {
        guard let old = editingProfile, !saving else { return }
        var new = old
        change(&new)
        let frames = Flydigi.writeProfile(from: old, to: new)
        guard !frames.isEmpty else { return }
        saving = true
        defer { saving = false }
        for frame in frames {
            do { _ = try await channel.request(frame, timeout: .seconds(1)) } catch {
                Log.settings.error("profile write failed at command \(frame[frame.startIndex + 2])")
                break
            }
        }
        await reloadProfile(old.slot)
    }

    private func reloadProfile(_ slot: Int) async {
        let box = AssemblerBox()
        guard (try? await channel.collect(Flydigi.readProfile(slot)) { box.add($0) }) != nil,
              let r = box.result, let p = Profile(slot: r.slot, bytes: r.bytes) else { return }
        profiles = profiles.map { $0.slot == slot ? p : $0 }
        ProfileBackup.save(profiles)
    }

    /// Makes `slot` the active profile, like the controller's Fast Swap.
    func useProfile(_ slot: Int) async {
        _ = try? await channel.request(Flydigi.applyProfile(slot))
        await loadActiveProfile()
    }

    private func loadActiveProfile() async {
        if let reply = try? await channel.request(Flydigi.readProfileVersions()) {
            activeProfile = Flydigi.activeProfile(reply)
        }
    }

    private func loadProfiles() async {
        await loadActiveProfile()
        var loaded: [Profile] = []
        for slot in 0..<4 {
            let box = AssemblerBox()
            do {
                try await channel.collect(Flydigi.readProfile(slot)) { reply in box.add(reply) }
            } catch {
                Log.settings.error("reading profile \(slot) failed")
                continue
            }
            if let r = box.result, let p = Profile(slot: r.slot, bytes: r.bytes) { loaded.append(p) }
        }
        profiles = loaded
        ProfileBackup.save(loaded)
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
                // The controller can switch profiles itself (Fn + a face button), so keep up.
                await loadActiveProfile()
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
                await loadProfiles()
                if liveViewers > 0 { beginLive() }
            case .disconnected:
                connected = false
                info = nil
                settings = nil
                profiles = []
                activeProfile = nil
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

/// Collects a profile's chunks as they arrive on the channel's thread.
private final class AssemblerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var assembler = ProfileAssembler()
    private(set) var result: (slot: Int, bytes: [UInt8])?

    /// Returns true once the whole profile has arrived.
    func add(_ reply: [UInt8]) -> Bool {
        lock.withLock {
            if let r = assembler.add(reply) { result = r }
            return result != nil
        }
    }
}

/// Keeps a copy of every profile read from the controller, so nothing written later can be lost.
/// Backups live in ~/Library/Application Support/Apex Station/Backups/<date>/profile-<slot>.bin;
/// a new folder is only made when something changed since the last one.
enum ProfileBackup {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Apex Station/Backups", isDirectory: true)
    }

    static func save(_ profiles: [Profile]) {
        guard !profiles.isEmpty else { return }
        let fm = FileManager.default
        let latest = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter(\.hasDirectoryPath).sorted { $0.lastPathComponent < $1.lastPathComponent }.last
        if let latest, profiles.allSatisfy({ (try? Data(contentsOf: latest.appendingPathComponent("profile-\($0.slot).bin"))) == Data($0.bytes) }) {
            return
        }
        let stamp = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: [.withFullDate, .withTime, .withDashSeparatorInDate])
        let dir = folder.appendingPathComponent(stamp, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for p in profiles { try Data(p.bytes).write(to: dir.appendingPathComponent("profile-\(p.slot).bin")) }
            Log.settings.notice("backed up \(profiles.count) profiles to \(dir.path, privacy: .public)")
        } catch {
            Log.settings.error("profile backup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
