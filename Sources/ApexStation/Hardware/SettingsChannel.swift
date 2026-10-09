import ApexKit
import CoreHID
import Foundation

/// The Apex 5's vendor HID interface (usage page 0xFFA0): commands out, replies and the
/// controller's own input stream (paddles, gyro) in.
actor SettingsChannel {
    enum Event: Sendable {
        case connected
        case disconnected
        case input(GamepadState)
    }

    struct Timeout: Error {}
    struct Disconnected: Error {}

    private var client: HIDDeviceClient?
    private var waiting: [UInt8: [(id: UUID, cont: CheckedContinuation<[UInt8], Error>)]] = [:]
    private let events: AsyncStream<Event>.Continuation
    nonisolated let eventStream: AsyncStream<Event>

    init() {
        (eventStream, events) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .bufferingNewest(64))
    }

    func start() async {
        let criteria = HIDDeviceManager.DeviceMatchingCriteria(
            primaryUsage: .init(page: Flydigi.usagePage, usage: 0x01),
            vendorID: Flydigi.vendorID, productID: Flydigi.apex5ProductID
        )
        do {
            for try await note in await HIDDeviceManager().monitorNotifications(matchingCriteria: [criteria]) {
                switch note {
                case .deviceMatched(let ref):
                    Log.settings.notice("settings interface matched")
                    guard client == nil, let c = HIDDeviceClient(deviceReference: ref) else { continue }
                    client = c
                    Task { await self.listen(to: c) }
                    events.yield(.connected)
                case .deviceRemoved(let ref):
                    if client?.deviceReference == ref { drop() }
                @unknown default: break
                }
            }
        } catch {
            Log.settings.error("device monitoring failed: \(error.localizedDescription, privacy: .public)")
            drop()
        }
    }

    /// Sends a command and waits for the reply to that command.
    func request(_ frame: Data, timeout: Duration = .milliseconds(500)) async throws -> [UInt8] {
        let command = frame[frame.startIndex + 2]
        let id = UUID()
        return try await withCheckedThrowingContinuation { cont in
            // Registered before sending, so a fast reply can't slip past.
            waiting[command, default: []].append((id, cont))
            Task {
                do { try await self.send(frame) } catch { self.resolve(command, id, .failure(error)) }
                try? await Task.sleep(for: timeout)
                self.resolve(command, id, .failure(Timeout()))
            }
        }
    }

    /// Sends a command that has no reply.
    func send(_ frame: Data) async throws {
        guard let client else { throw Disconnected() }
        Log.settings.notice("out: \(frame.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " "), privacy: .public)")
        // CoreHID wants the report ID both as the parameter and as the first data byte.
        try await client.dispatchSetReportRequest(
            type: .output, id: HIDReportID(rawValue: Flydigi.commandReportID), data: Data([Flydigi.commandReportID]) + frame)
    }

    private func resolve(_ command: UInt8, _ id: UUID, _ result: Result<[UInt8], Error>) {
        guard let i = waiting[command]?.firstIndex(where: { $0.id == id }) else { return }
        waiting[command]!.remove(at: i).cont.resume(with: result)
    }

    private func listen(to c: HIDDeviceClient) async {
        do {
            for try await note in await c.monitorNotifications(reportIDsToMonitor: [HIDReportID.allReports], elementsToMonitor: []) {
                guard case let .inputReport(_, data, _) = note else {
                    if case .deviceRemoved = note { break }
                    continue
                }
                handle([UInt8](data))
            }
        } catch {}
        if client === c { drop() }
    }

    private func handle(_ report: [UInt8]) {
        if Flydigi.command(of: report) != Flydigi.Command.input.rawValue {
            Log.settings.notice("in: \(report.prefix(12).map { String(format: "%02x", $0) }.joined(separator: " "), privacy: .public)")
        }
        guard let command = Flydigi.command(of: report) else { return }
        if command == Flydigi.Command.input.rawValue {
            if let state = FlydigiInputReport.parse(report) { events.yield(.input(state)) }
            return
        }
        guard let first = waiting[command]?.first else { return }
        resolve(command, first.id, .success(report))
    }

    private func drop() {
        client = nil
        for (_, list) in waiting { list.forEach { $0.cont.resume(throwing: Disconnected()) } }
        waiting = [:]
        events.yield(.disconnected)
    }
}
