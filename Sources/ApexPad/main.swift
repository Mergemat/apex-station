import ApexKit
import Foundation

// ApexPad: Apex Station's helper that holds the virtual Xbox Wireless Controller games see.
// It reads Xbox input reports on stdin and writes PadLink messages to stdout, and quits when
// stdin closes (Apex Station quit or turned the controller off). It exits with status 2 if macOS
// won't create the virtual device; macOS may also stop it before it starts (no entitlement).

let out = FileHandle.standardOutput
let outLock = NSLock()
func tell(_ message: PadLink.Message) {
    let data = PadLink.encode(message)
    outLock.withLock { try? out.write(contentsOf: data) }
}

guard let pad = VirtualXboxController(onRumble: { tell(.rumble($0)) }) else {
    FileHandle.standardError.write(Data("virtual HID device not allowed\n".utf8))
    exit(2)
}
tell(.ready)

let reader = Thread {
    var pending: [UInt8] = []
    while true {
        let chunk = FileHandle.standardInput.availableData
        if chunk.isEmpty { exit(0) }
        pending += chunk
        while pending.count >= PadLink.reportSize {
            pad.send(report: Data(pending.prefix(PadLink.reportSize)))
            pending.removeFirst(PadLink.reportSize)
        }
    }
}
reader.start()
dispatchMain()
