import ApexKit
import Foundation
import IOKit.hid

/// The Apex 5's vendor HID interface (usage page 0xFFA0): commands out, replies and the
/// controller's own input stream (paddles, gyro) in.
///
/// Built on IOKit's HID API rather than CoreHID: CoreHID routes sends and incoming reports
/// through one device actor, so a single send the controller doesn't answer froze the input
/// stream too. Here input arrives on a dedicated run-loop thread that sends can't block, sends
/// run on their own queue, and every request times out independently.
final class SettingsChannel: @unchecked Sendable {
    enum Event: Sendable {
        case connected
        case disconnected
    }

    struct Timeout: Error {}
    struct Disconnected: Error {}
    struct SendFailed: Error { let code: IOReturn }

    /// Latest input and a running report count, written at the controller's ~1000 Hz and read
    /// by the UI at display rate, so no report has to queue anywhere.
    let live = LiveInput()
    let eventStream: AsyncStream<Event>

    private let events: AsyncStream<Event>.Continuation
    private let sendQueue = DispatchQueue(label: "apex.settings.send", qos: .userInitiated)
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    // Guarded by `lock`.
    private let lock = NSLock()
    private var device: IOHIDDevice?
    private var waiting: [UInt8: [(id: UUID, cont: CheckedContinuation<[UInt8], Error>)]] = [:]
    /// Multi-reply requests: every reply for the command goes to `take` until it returns true.
    private var collectors: [UInt8: (id: UUID, take: ([UInt8]) -> Bool, cont: CheckedContinuation<Void, Error>)] = [:]

    init() {
        (eventStream, events) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .bufferingNewest(16))
    }

    /// Starts watching for the controller on a dedicated thread.
    func start() {
        let thread = Thread { [self] in runLoop() }
        thread.name = "apex.settings.hid"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Sends a command and waits for the reply to that command.
    func request(_ frame: Data, timeout: Duration = .milliseconds(600)) async throws -> [UInt8] {
        let command = frame[frame.startIndex + 2]
        let id = UUID()
        return try await withCheckedThrowingContinuation { cont in
            // Registered before sending, so a fast reply can't slip past.
            lock.withLock { waiting[command, default: []].append((id, cont)) }
            let ms = Int(timeout.components.seconds * 1000) + Int(timeout.components.attoseconds / 1_000_000_000_000_000)
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(ms)) { [self] in
                resolve(command, id, .failure(Timeout()))
            }
            sendQueue.async { [self] in
                if let error = sendNow(frame) { resolve(command, id, .failure(error)) }
            }
        }
    }

    /// Sends a command whose answer comes as several replies, handing each to `take` until it
    /// returns true (for example once every chunk of a profile has arrived).
    func collect(_ frame: Data, timeout: Duration = .seconds(3), take: @escaping @Sendable ([UInt8]) -> Bool) async throws {
        let command = frame[frame.startIndex + 2]
        let id = UUID()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.withLock { collectors[command] = (id, take, cont) }
            let ms = Int(timeout.components.seconds * 1000) + Int(timeout.components.attoseconds / 1_000_000_000_000_000)
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(ms)) { [self] in
                finishCollect(command, id, .failure(Timeout()))
            }
            sendQueue.async { [self] in
                if let error = sendNow(frame) { finishCollect(command, id, .failure(error)) }
            }
        }
    }

    private func finishCollect(_ command: UInt8, _ id: UUID, _ result: Result<Void, Error>) {
        let cont = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard let c = collectors[command], c.id == id else { return nil }
            collectors[command] = nil
            return c.cont
        }
        cont?.resume(with: result)
    }

    /// Sends a command that has no reply.
    func send(_ frame: Data) async throws {
        let error: Error? = await withCheckedContinuation { cont in
            sendQueue.async { [self] in cont.resume(returning: sendNow(frame)) }
        }
        if let error { throw error }
    }

    // MARK: - IOKit

    private func sendNow(_ frame: Data) -> Error? {
        guard let device = lock.withLock({ self.device }) else { return Disconnected() }
        Log.settings.notice("out: \(frame.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "), privacy: .public)")
        // IOKit takes the report ID as the first byte of the buffer as well as the parameter.
        let report = [Flydigi.commandReportID] + [UInt8](frame)
        let result = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(Flydigi.commandReportID), $0.baseAddress!, $0.count)
        }
        return result == kIOReturnSuccess ? nil : SendFailed(code: result)
    }

    private func runLoop() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Flydigi.vendorID,
            kIOHIDProductIDKey: Flydigi.apex5ProductID,
            kIOHIDPrimaryUsagePageKey: Int(Flydigi.usagePage),
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<SettingsChannel>.fromOpaque(ctx!).takeUnretainedValue().matched(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            Unmanaged<SettingsChannel>.fromOpaque(ctx!).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        CFRunLoopRun()
    }

    private func matched(_ device: IOHIDDevice) {
        let isNew = lock.withLock { () -> Bool in
            guard self.device == nil else { return false }
            self.device = device
            return true
        }
        guard isNew else { return }
        Log.settings.notice("settings interface matched")
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, { ctx, _, _, _, _, report, length in
            let bytes = [UInt8](UnsafeBufferPointer(start: report, count: length))
            Unmanaged<SettingsChannel>.fromOpaque(ctx!).takeUnretainedValue().handle(bytes)
        }, Unmanaged.passUnretained(self).toOpaque())
        events.yield(.connected)
    }

    private func removed(_ device: IOHIDDevice) {
        let pending = lock.withLock { () -> [CheckedContinuation<[UInt8], Error>]? in
            guard self.device === device else { return nil }
            self.device = nil
            defer { waiting = [:] }
            let pendingCollectors = collectors.values.map(\.cont)
            collectors = [:]
            pendingCollectors.forEach { $0.resume(throwing: Disconnected()) }
            return waiting.values.flatMap { $0.map(\.cont) }
        }
        guard let pending else { return }
        pending.forEach { $0.resume(throwing: Disconnected()) }
        events.yield(.disconnected)
    }

    private func handle(_ report: [UInt8]) {
        guard let command = Flydigi.command(of: report) else { return }
        if command == Flydigi.Command.input.rawValue {
            if let state = FlydigiInputReport.parse(report) { live.update(state) }
            return
        }
        if let c = lock.withLock({ collectors[command] }) {
            if c.take(report) { finishCollect(command, c.id, .success(())) }
            return
        }
        Log.settings.notice("in: \(report.prefix(12).map { String(format: "%02x", $0) }.joined(separator: " "), privacy: .public)")
        let first = lock.withLock { waiting[command]?.first?.id }
        if let first { resolve(command, first, .success(report)) }
    }

    private func resolve(_ command: UInt8, _ id: UUID, _ result: Result<[UInt8], Error>) {
        let cont = lock.withLock { () -> CheckedContinuation<[UInt8], Error>? in
            guard let i = waiting[command]?.firstIndex(where: { $0.id == id }) else { return nil }
            return waiting[command]!.remove(at: i).cont
        }
        cont?.resume(with: result)
    }
}

final class LiveInput: @unchecked Sendable {
    private let lock = NSLock()
    private var state = GamepadState()
    private var count = 0

    func update(_ s: GamepadState) {
        lock.lock(); defer { lock.unlock() }
        state = s
        count += 1
    }

    /// The latest state and how many reports have arrived in total.
    func snapshot() -> (state: GamepadState, count: Int) {
        lock.lock(); defer { lock.unlock() }
        return (state, count)
    }
}
