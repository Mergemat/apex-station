import ApexKit
import Foundation

/// Runs the ApexPad helper, which holds the virtual Xbox Wireless Controller games see, and
/// feeds it the Apex 5's input. See `PadLink` for what goes between them.
final class VirtualPad: @unchecked Sendable {
    enum Status: Equatable, Sendable {
        case off
        case starting
        case on
        /// macOS wouldn't let the helper make a virtual controller.
        case blocked
    }

    /// Status changes and rumble requests from games, on a background thread.
    var onStatus: (@Sendable (Status) -> Void)?
    var onRumble: (@Sendable (XboxWirelessReport.Rumble) -> Void)?

    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var last: Data?

    init() {
        // Writing to a helper that has quit must fail quietly instead of killing the app.
        signal(SIGPIPE, SIG_IGN)
    }

    private var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ApexPad")
    }

    func start() {
        let already = lock.withLock { process != nil }
        guard !already else { return }
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            Log.usb.error("ApexPad helper missing at \(self.helperURL.path, privacy: .public)")
            onStatus?(.blocked)
            return
        }
        let p = Process()
        p.executableURL = helperURL
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        let link = LinkState()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            for message in link.decode(data) {
                switch message {
                case .ready:
                    self.onStatus?(.on)
                case .rumble(let r):
                    self.onRumble?(r)
                }
            }
        }
        p.terminationHandler = { [weak self] proc in
            stdout.fileHandleForReading.readabilityHandler = nil
            guard let self else { return }
            let wasCurrent = self.lock.withLock { () -> Bool in
                guard self.process === proc else { return false }
                self.process = nil
                self.input = nil
                return true
            }
            guard wasCurrent else { return }
            // Killed before it was ready (no entitlement) or refused by CoreHID: blocked.
            let refused = !link.ready && (proc.terminationReason == .uncaughtSignal || proc.terminationStatus == 2)
            Log.usb.notice("ApexPad ended: status \(proc.terminationStatus), ready \(link.ready)")
            self.onStatus?(refused ? .blocked : .off)
        }
        do {
            try p.run()
        } catch {
            Log.usb.error("ApexPad didn't start: \(error.localizedDescription, privacy: .public)")
            onStatus?(.blocked)
            return
        }
        lock.withLock {
            process = p
            input = stdin.fileHandleForWriting
            last = nil
        }
        onStatus?(.starting)
    }

    func stop() {
        let p = lock.withLock { () -> Process? in
            defer { process = nil; input = nil }
            try? input?.close()
            return process
        }
        if p != nil { onStatus?(.off) }
    }

    /// Passes on the controller's state; repeats are skipped.
    func send(_ state: GamepadState) {
        let report = XboxWirelessReport.encode(state)
        lock.withLock {
            guard let input, report != last else { return }
            last = report
            try? input.write(contentsOf: report)
        }
    }
}

/// What the helper has said so far.
private final class LinkState: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [UInt8] = []
    private var sawReady = false

    var ready: Bool { lock.withLock { sawReady } }

    func decode(_ data: Data) -> [PadLink.Message] {
        lock.withLock {
            pending += data
            let messages = PadLink.decode(&pending)
            if messages.contains(.ready) { sawReady = true }
            return messages
        }
    }
}
