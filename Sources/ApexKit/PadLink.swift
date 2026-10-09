import Foundation

/// How Apex Station talks to its ApexPad helper, which holds the virtual Xbox controller.
/// Apex Station writes Xbox input reports (`XboxWirelessReport.encode`, 17 bytes each) to the
/// helper's stdin; the helper writes messages to stdout: `ready` once the controller exists,
/// then a `rumble` message for each rumble request from a game.
public enum PadLink {
    public static let reportSize = 17

    public enum Message: Equatable, Sendable {
        case ready
        case rumble(XboxWirelessReport.Rumble)
    }

    static let readyTag: UInt8 = 0x01, rumbleTag: UInt8 = 0x02

    public static func encode(_ message: Message) -> Data {
        switch message {
        case .ready:
            return Data([readyTag])
        case .rumble(let r):
            // Duration in 10 ms steps; 0xFFFF means until the next request.
            let steps = r.duration.map { UInt16(min(0xFFFE, $0.components.seconds * 100 + $0.components.attoseconds / 10_000_000_000_000_000)) } ?? 0xFFFF
            return Data([rumbleTag, r.strong, r.weak, UInt8(steps & 0xFF), UInt8(steps >> 8)])
        }
    }

    /// Takes whole messages off the front of `buffer`, leaving any partial one.
    public static func decode(_ buffer: inout [UInt8]) -> [Message] {
        var out: [Message] = []
        while let tag = buffer.first {
            if tag == readyTag {
                out.append(.ready)
                buffer.removeFirst()
            } else if tag == rumbleTag {
                guard buffer.count >= 5 else { break }
                let steps = UInt16(buffer[3]) | UInt16(buffer[4]) << 8
                out.append(.rumble(.init(strong: buffer[1], weak: buffer[2],
                                         duration: steps == 0xFFFF ? nil : .milliseconds(Int(steps) * 10))))
                buffer.removeFirst(5)
            } else {
                buffer.removeFirst() // not ours; skip
            }
        }
        return out
    }
}
