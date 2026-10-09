import ApexKit
import Foundation
import Observation

/// Everything the app knows about the connected Apex 5, and the actions it can take.
///
/// Games don't need this app: with "Full controller" on, SDL (Steam and most Mac games) drives
/// the Apex 5 itself. The app configures the controller and shows it live. While the live view is
/// open the app holds the controller and reads its own input stream (paddles, gyro); the
/// controller hands itself back ~15 s after we stop refreshing, so nothing stays stuck.
///
/// In PC Bluetooth mode the controller is a plain Xbox pad with no settings interface, so the
/// app can only show it live and rumble it; changing anything needs the cable.
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
    /// Buttons going down and up, newest first, for the input test.
    private(set) var inputLog = InputLog()

    func clearInputLog() { inputLog.clear() }

    /// What a button acts as right now: its keyboard & mouse key, or its remap in the active profile.
    func actsAs(_ key: FlydigiKey) -> String? {
        if keyboardMouseOn, let out = keyboardMouseMap[key] { return out.label }
        return switch editingProfile?.mapping(for: key) {
        case .button(let k)?: k.shortName
        case .macro?: "macro"
        case .keyboardOrMouse?: "keyboard/mouse"
        default: nil
        }
    }

    /// Average and longest gap between reports over the last second, in ms.
    private(set) var reportTiming: (average: Double, longest: Double)?
    /// Settings stored on the controller.
    private(set) var settings: DeviceSettings?
    /// The controller's four on-board profiles, and which one is active.
    private(set) var profiles: [Profile] = []
    /// Each profile's lighting, by slot.
    private(set) var lighting: [Int: Lighting] = [:]
    private(set) var activeProfile: Int?
    /// The controller is connected over Bluetooth (live view only).
    private(set) var bluetooth = false
    private(set) var bluetoothBattery: Int?

    @ObservationIgnored var started = false
    @ObservationIgnored private let channel = SettingsChannel()
    @ObservationIgnored private let pad = BluetoothPad()
    @ObservationIgnored private var liveViewers = 0
    @ObservationIgnored private var keepAlive: Task<Void, Never>?
    /// The keep-alive stays quiet while a screen upload has the channel.
    @ObservationIgnored private var uploadingScreen = false

    func start() {
        if UserDefaults.standard.bool(forKey: "keyboardMouse") { setKeyboardMouse(true, prompt: false) }
        channel.start()
        pad.start()
        Task { await watchChannel() }
        Task { await watchPad() }
        Task { await refreshUI() }
    }

    /// What to tell the user when something can't be changed right now.
    func cableNote(_ what: String) -> String {
        bluetooth
            ? "Over Bluetooth the controller can't be changed. Connect it with the USB-C cable to change \(what); it keeps your changes when you go back to Bluetooth."
            : "Connect your Apex 5 with the USB-C cable to change \(what)."
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
    func setReportRate(_ r: DeviceSettings.ReportRate) async { await apply(Flydigi.setReportRate(r)) }

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
    var editingLighting: Lighting? { lighting[activeProfile ?? 0] }
    /// True while a profile write is in flight.
    private(set) var saving = false

    func remap(_ key: FlydigiKey, to mapping: KeyMapping) async {
        await edit { $0.setMapping(mapping, for: key) }
    }

    func setTrigger(_ t: TriggerConfig, left: Bool) async { await edit { $0.setTrigger(t, left: left) } }
    func setVibration(_ v: VibrationConfig) async { await edit { $0.setVibration(v) } }
    func setGyro(_ g: GyroConfig) async { await edit { $0.setGyro(g) } }

    func rename(slot: Int, to name: String) async {
        await edit(slot: slot) { $0.setName(name) }
    }

    /// Puts profile `slot` back to Flydigi's factory settings (backed up first like any change).
    func resetProfile(_ slot: Int) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        _ = try? await channel.request(Flydigi.resetProfile(slot), timeout: .seconds(2))
        await reloadProfile(slot)
        await reloadLighting(slot)
    }

    /// Profile `slot` as a file to share or keep.
    func exportProfile(_ slot: Int) -> ProfileFile? {
        guard let p = profiles.first(where: { $0.slot == slot }) else { return nil }
        return ProfileFile(profile: p, lighting: lighting[slot], name: displayName(p))
    }

    /// Writes a profile file into `slot` (only the bytes that differ, backed up first like any change).
    func importProfile(_ file: ProfileFile, into slot: Int) async {
        guard let new = file.profile(for: slot) else { return }
        await edit(slot: slot) { $0 = new }
        if let light = file.lighting(for: slot) { await editLighting(slot: slot) { $0 = light } }
    }

    /// Applies `change` to a profile's lighting (the active one by default) and writes only what changed.
    func editLighting(slot: Int? = nil, _ change: (inout Lighting) -> Void) async {
        guard let old = slot.map({ lighting[$0] }) ?? editingLighting, !saving else { return }
        var new = old
        change(&new)
        let frames = Flydigi.writeLighting(from: old, to: new)
        guard !frames.isEmpty else { return }
        saving = true
        defer { saving = false }
        for frame in frames {
            do { _ = try await channel.request(frame, timeout: .seconds(1)) } catch { break }
        }
        await reloadLighting(old.slot)
    }

    private func reloadLighting(_ slot: Int) async {
        let active = activeProfile
        defer { Task { await switchBack(to: active) } }
        let box = AssemblerBox(command: .readLighting)
        guard (try? await channel.collect(Flydigi.readLighting(slot)) { box.add($0) }) != nil,
              let r = box.result, let l = Lighting(slot: r.slot, bytes: r.bytes) else { return }
        lighting[slot] = l
        ProfileBackup.save(profiles, lighting: Array(lighting.values))
    }

    func setStick(_ config: StickConfig, left: Bool) async {
        await edit { $0.setStick(config, left: left) }
    }

    /// Stores `macro` on its button, replacing any macro that button had.
    func setMacro(_ macro: Macro) async {
        await edit { p in p.setMacros(p.macros.filter { $0.key != macro.key } + [macro]) }
    }

    func removeMacro(on key: FlydigiKey) async {
        await edit { p in p.setMacros(p.macros.filter { $0.key != key }) }
    }

    /// Steps recorded so far, while recording a macro from the controller.
    private(set) var recordedSteps: [Macro.Step]?
    private var recordingTask: Task<Void, Never>?

    func startRecording() {
        guard live, connected, recordingTask == nil else { return }
        recordedSteps = []
        recordingTask = Task { [channel] in
            var recorder = MacroRecorder()
            let start = ContinuousClock.now
            func elapsed() -> Int { Int((ContinuousClock.now - start) / .milliseconds(1)) }
            while !Task.isCancelled, !recorder.isFull {
                recorder.add(channel.live.snapshot().state, at: elapsed())
                if recorder.steps.count != recordedSteps?.count { recordedSteps = recorder.steps }
                try? await Task.sleep(for: .milliseconds(2))
            }
            recordedSteps = recorder.finish(at: elapsed())
        }
    }

    /// Stops recording and returns what was recorded.
    func stopRecording() async -> [Macro.Step] {
        recordingTask?.cancel()
        await recordingTask?.value
        recordingTask = nil
        defer { recordedSteps = nil }
        return recordedSteps ?? []
    }

    /// True while waiting for the user to press a button on the controller.
    private(set) var listening = false
    private var listenTask: Task<FlydigiKey?, Never>?

    /// Waits for the next button press on the controller (up to 15 s) and returns it, or nil if
    /// cancelled or nothing was pressed. Buttons already held when it starts don't count.
    func nextPress() async -> FlydigiKey? {
        guard live, connected else { return nil }
        listenTask?.cancel()
        let task = Task { [channel] () -> FlydigiKey? in
            let targets = FlydigiKey.remapTargets
            var held = FlydigiKey.pressed(in: channel.live.snapshot().state, among: targets)
            let deadline = ContinuousClock.now + .seconds(15)
            while !Task.isCancelled, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(4))
                let down = FlydigiKey.pressed(in: channel.live.snapshot().state, among: targets)
                if let key = targets.first(where: { down.contains($0) && !held.contains($0) }) { return key }
                held = down
            }
            return nil
        }
        listenTask = task
        listening = true
        let key = await task.value
        if listenTask == task { listening = false; listenTask = nil }
        return key
    }

    func cancelListening() { listenTask?.cancel() }

    func setTurbo(_ key: FlydigiKey, _ turbo: (mode: TurboMode, speed: UInt8)?) async {
        await edit { $0.setTurbo(turbo, for: key) }
    }

    /// Applies `change` to the active profile, writes only what changed, then reads the profile
    /// back so the app shows what the controller actually stored.
    private func edit(slot: Int? = nil, _ change: (inout Profile) -> Void) async {
        let target = slot ?? activeProfile ?? 0
        guard let old = profiles.first(where: { $0.slot == target }), !saving else { return }
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
        let active = activeProfile
        defer { Task { await switchBack(to: active) } }
        let box = AssemblerBox()
        guard (try? await channel.collect(Flydigi.readProfile(slot)) { box.add($0) }) != nil,
              let r = box.result, let p = Profile(slot: r.slot, bytes: r.bytes) else { return }
        profiles = profiles.map { $0.slot == slot ? p : $0 }
        ProfileBackup.save(profiles, lighting: Array(lighting.values))
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

    /// Reading a profile makes it the controller's active one (Space Station switches back after
    /// reading too), so after reads this puts the profile the user was on back.
    private func switchBack(to slot: Int?) async {
        guard let slot else { return }
        await loadActiveProfile()
        if activeProfile != slot {
            _ = try? await channel.request(Flydigi.applyProfile(slot))
            await loadActiveProfile()
        }
    }

    private func loadProfiles() async {
        await loadActiveProfile()
        let active = activeProfile
        defer { Task { await switchBack(to: active) } }
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
            let lightBox = AssemblerBox(command: .readLighting)
            if (try? await channel.collect(Flydigi.readLighting(slot)) { lightBox.add($0) }) != nil,
               let r = lightBox.result, let l = Lighting(slot: r.slot, bytes: r.bytes) {
                lighting[slot] = l
            }
        }
        profiles = loaded
        ProfileBackup.save(loaded, lighting: Array(lighting.values))
    }

    /// Runs the grip motors (0-255 each) for a moment, for the input test.
    func rumble(left: UInt8, right: UInt8) async {
        if !connected, bluetooth {
            pad.rumble(strong: UInt8(Int(left) * 100 / 255), weak: UInt8(Int(right) * 100 / 255), duration: .milliseconds(400))
            return
        }
        try? await channel.send(Flydigi.frame(.rumble, [left, right, 0, 0]))
        try? await Task.sleep(for: .milliseconds(400))
        try? await channel.send(Flydigi.frame(.rumble, [0, 0, 0, 0]))
    }

    func testRumble() async {
        if !connected, bluetooth {
            pad.rumble(strong: 75, weak: 75, duration: .milliseconds(350))
            return
        }
        try? await channel.send(Flydigi.frame(.rumble, [0xC0, 0xC0, 0, 0]))
        try? await Task.sleep(for: .milliseconds(350))
        try? await channel.send(Flydigi.frame(.rumble, [0, 0, 0, 0]))
    }

    // MARK: - Keyboard & mouse

    /// Whether buttons, sticks and gyro type and move the pointer (as mapped per profile).
    private(set) var keyboardMouseOn = false
    /// Mappings by profile slot, kept on this Mac like Space Station keeps them on the PC.
    private(set) var keyboardMouseMaps: [Int: KeyboardMouseMap] = KeyboardMouseStore.load()
    @ObservationIgnored private var keyboardMouseTask: Task<Void, Never>?

    var keyboardMouseMap: KeyboardMouseMap { keyboardMouseMaps[activeProfile ?? 0] ?? KeyboardMouseMap() }

    func editKeyboardMouse(_ change: (inout KeyboardMouseMap) -> Void) {
        var map = keyboardMouseMap
        change(&map)
        keyboardMouseMaps[activeProfile ?? 0] = map
        KeyboardMouseStore.save(keyboardMouseMaps)
    }

    /// `prompt` shows macOS's Accessibility prompt when permission is missing; it's off when
    /// the app restores the setting at launch.
    func setKeyboardMouse(_ on: Bool, prompt: Bool = true) {
        guard on != keyboardMouseOn else { return }
        keyboardMouseOn = on
        UserDefaults.standard.set(on, forKey: "keyboardMouse")
        if on {
            if prompt { KeyboardMouseOutput.requestTrust() }
            // Holding the controller keeps its input coming while the window is closed.
            liveViewAppeared()
            keyboardMouseTask = Task { await runKeyboardMouse() }
        } else {
            keyboardMouseTask?.cancel()
            keyboardMouseTask = nil
            liveViewDisappeared()
        }
    }

    private func runKeyboardMouse() async {
        let output = KeyboardMouseOutput()
        var engine = KeyboardMouseEngine(map: keyboardMouseMap)
        var last = ContinuousClock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(2))
            let now = ContinuousClock.now
            let dt = Double((now - last) / .microseconds(1)) / 1_000_000
            last = now
            guard live else {
                output.post(engine.releaseAll())
                continue
            }
            engine.map = keyboardMouseMap
            let source = connected || !bluetooth ? channel.live : pad.live
            var gyro: KeyboardMouseEngine.GyroMouse?
            if let g = editingProfile?.gyro, g.target == .mouse {
                gyro = .init(sensitivity: g.sensitivity, key: g.key, hold: g.activation == .hold)
            }
            output.post(engine.step(source.snapshot().state, dt: dt, gyro: gyro))
        }
        output.post(engine.releaseAll())
    }

    // MARK: - Screen

    enum ScreenUpload: Equatable {
        case sending(Double)
        case done
        case failed(String)
    }

    /// Progress of the last screen upload.
    private(set) var screenUpload: ScreenUpload?

    /// Flydigi's own animation for this controller, if it has been copied out of Space Station's
    /// installer (scripts/screen-default.ts). It's their artwork, so the app doesn't ship it.
    var defaultScreenFile: URL? {
        guard let id = info?.deviceID else { return nil }
        let url = ProfileBackup.folder.deletingLastPathComponent()
            .appendingPathComponent("Screen/default_screen_image_\(id).bin")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Sends an animation (encoded frames) to the controller's screen. It shows after the
    /// controller restarts.
    func uploadScreen(_ frames: [[UInt8]]) async {
        guard connected, !frames.isEmpty, !saving else { return }
        let packets = Screen.uploadPackets(frames: Array(frames.prefix(Screen.maxFrames)))
        saving = true
        uploadingScreen = true
        defer { saving = false; uploadingScreen = false }
        screenUpload = .sending(0)
        Log.settings.notice("screen upload: \(frames.count) frames, \(packets.count) packets")
        for (i, packet) in packets.enumerated() {
            var acked = false
            for _ in 0..<3 where !acked {
                acked = (try? await channel.exchange(packet.bytes, timeout: packet.timeout) { Screen.acknowledges($0, packet) }) != nil
            }
            guard acked else {
                Log.settings.error("screen upload stopped at packet \(i) (command \(packet.command))")
                screenUpload = .failed("The controller stopped answering. Slide the power switch on the back off and on, then try again.")
                return
            }
            if i % 25 == 0 { screenUpload = .sending(Double(i) / Double(packets.count)) }
        }
        screenUpload = .done
    }

    func restoreDefaultScreen() async {
        guard let url = defaultScreenFile, let data = try? Data(contentsOf: url) else { return }
        await uploadScreen(Screen.frames(in: [UInt8](data)))
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
        if !connected, bluetooth {
            live = true
            return
        }
        guard keepAlive == nil, connected, fullControllerEnabled == true else { return }
        keepAlive = Task {
            while !Task.isCancelled {
                if uploadingScreen {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
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
        if connected { Task { try? await channel.send(Flydigi.acquire(false)) } }
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
                lighting = [:]
                activeProfile = nil
                fullControllerEnabled = nil
                keepAlive?.cancel()
                keepAlive = nil
                live = false
                state = GamepadState()
                if liveViewers > 0 { beginLive() }
            }
        }
    }

    private func watchPad() async {
        for await event in pad.eventStream {
            switch event {
            case .connected:
                bluetooth = true
                if liveViewers > 0 { beginLive() }
            case .disconnected:
                bluetooth = false
                bluetoothBattery = nil
                if !connected {
                    live = false
                    state = GamepadState()
                }
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
        // Input comes from the cable's stream when there is one, otherwise from Bluetooth.
        var source = channel.live
        var lastCount = source.snapshot().count
        var lastRateAt = ContinuousClock.now
        // Turbo and Fn are combo keys: the controller only reports them as a brief pulse when
        // they're released on their own, so their highlight is held long enough to see.
        var pulseUntil: [UInt32: ContinuousClock.Instant] = [:]
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let current = connected || !bluetooth ? channel.live : pad.live
            if current !== source {
                source = current
                lastCount = source.snapshot().count
            }
            let snap = source.snapshot()
            let changes = source.takeChanges()
            if live, !changes.isEmpty { inputLog.add(changes, actsAs: actsAs) }
            var shown = snap.state
            let now = ContinuousClock.now
            for key in [GamepadButtons.turbo, .fn] {
                if snap.state.buttons.contains(key) { pulseUntil[key.rawValue] = now + .milliseconds(500) }
                if let until = pulseUntil[key.rawValue], until > now { shown.buttons.insert(key) }
            }
            if live, shown != state { state = shown }
            if ContinuousClock.now - lastRateAt >= .seconds(1) {
                reportRate = live ? snap.count - lastCount : 0
                let timing = source.takeTiming()
                reportTiming = live ? timing : nil
                if bluetoothBattery != pad.battery { bluetoothBattery = pad.battery }
                lastCount = snap.count
                lastRateAt = .now
            }
        }
    }
}

/// Collects a profile's chunks as they arrive on the channel's thread.
private final class AssemblerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var assembler: ProfileAssembler
    init(command: Flydigi.Command = .readProfile) { assembler = ProfileAssembler(command: command) }
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

    static func save(_ profiles: [Profile], lighting: [Lighting] = []) {
        guard !profiles.isEmpty else { return }
        let fm = FileManager.default
        let latest = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter(\.hasDirectoryPath).sorted { $0.lastPathComponent < $1.lastPathComponent }.last
        if let latest,
           profiles.allSatisfy({ (try? Data(contentsOf: latest.appendingPathComponent("profile-\($0.slot).bin"))) == Data($0.bytes) }),
           lighting.allSatisfy({ (try? Data(contentsOf: latest.appendingPathComponent("lighting-\($0.slot).bin"))) == Data($0.bytes) }) {
            return
        }
        let stamp = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: [.withFullDate, .withTime, .withDashSeparatorInDate])
        let dir = folder.appendingPathComponent(stamp, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for p in profiles { try Data(p.bytes).write(to: dir.appendingPathComponent("profile-\(p.slot).bin")) }
            for l in lighting { try Data(l.bytes).write(to: dir.appendingPathComponent("lighting-\(l.slot).bin")) }
            Log.settings.notice("backed up \(profiles.count) profiles to \(dir.path, privacy: .public)")
        } catch {
            Log.settings.error("profile backup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension Lighting {
    /// Flydigi's default animation (12 LEDs × 10 frames), recorded from a factory profile, used
    /// to switch a profile back to "Default" after a custom colour overwrote its frames.
    static let factoryFrames = [UInt8](Data(base64Encoded: "AICAAICAAICAAHGOAGCfAEm2ACvUAAD/KgDVSQC2YACfcQCOALZJALZJALZJAJ9gAI5xAICAAHGOAGCfAEm2ACvUAAD/KgDVK9QAK9QAK9QAAP8AANUqALZJAJ9gAI5xAICAAHGOAGCfAEm2cY4AcY4AcY4AYJ8ASbYAK9QAAP8AANUqALZJAJ9gAI5xAICAn2AAn2AAn2AAjnEAgIAAcY4AYJ8ASbYAK9QAAP8AANUqALZJ/wAA/wAA/wAA1CoAtkkAn2AAjnEAgIAAcY4AYJ8ASbYAK9QAnwBgnwBgnwBgtgBJ1AAr/wAA1CoAtkkAn2AAjnEAgIAAcY4AcQCOcQCOcQCOgACAjgBxnwBgtgBJ1AAr/wAA1CoAtkkAn2AAKgDVKgDVKgDVSQC2YACfcQCOgACAjgBxnwBgtgBJ1AAr/wAAAEm2AEm2AEm2ACvUAAD/KgDVSQC2YACfcQCOgACAjgBxnwBg")!)
}

/// Keyboard & mouse mappings, saved in Application Support as JSON.
enum KeyboardMouseStore {
    private static var file: URL {
        ProfileBackup.folder.deletingLastPathComponent().appendingPathComponent("keyboard-mouse.json")
    }

    static func load() -> [Int: KeyboardMouseMap] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([Int: KeyboardMouseMap].self, from: data)) ?? [:]
    }

    static func save(_ maps: [Int: KeyboardMouseMap]) {
        guard let data = try? JSONEncoder().encode(maps) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file)
    }
}
