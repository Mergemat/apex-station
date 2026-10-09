import ApexKit
import AppKit
import ApplicationServices

/// Sends keyboard and mouse events to macOS for the keyboard & mouse mapping. macOS only lets
/// an app do this with Accessibility permission (System Settings → Privacy & Security →
/// Accessibility). Ad-hoc builds may need it granted again after an update.
final class KeyboardMouseOutput {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show the Accessibility prompt if permission is missing.
    static func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 won't read from a global.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private let source = CGEventSource(stateID: .hidSystemState)
    private var buttonsDown: Set<KeyboardMouseMap.MouseButton> = []
    /// Movement smaller than a point carries over to the next event.
    private var remainder = CGPoint.zero

    func post(_ events: [KeyboardMouseEvent]) {
        for event in events {
            switch event {
            case .keyDown(let code): key(code, down: true)
            case .keyUp(let code): key(code, down: false)
            case .mouseDown(let b): click(b, down: true)
            case .mouseUp(let b): click(b, down: false)
            case .scroll(let steps):
                CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: Int32(steps), wheel2: 0, wheel3: 0)?
                    .post(tap: .cghidEventTap)
            case let .move(dx, dy): move(dx, dy)
            }
        }
    }

    private func key(_ code: UInt16, down: Bool) {
        CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap)
    }

    private func click(_ b: KeyboardMouseMap.MouseButton, down: Bool) {
        if down { buttonsDown.insert(b) } else { buttonsDown.remove(b) }
        let type: CGEventType = switch (b, down) {
        case (.left, true): .leftMouseDown
        case (.left, false): .leftMouseUp
        case (.right, true): .rightMouseDown
        case (.right, false): .rightMouseUp
        case (.middle, true): .otherMouseDown
        case (.middle, false): .otherMouseUp
        }
        let button: CGMouseButton = switch b { case .left: .left; case .right: .right; case .middle: .center }
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    private func move(_ dx: Double, _ dy: Double) {
        let total = CGPoint(x: remainder.x + dx, y: remainder.y + dy)
        let step = CGPoint(x: total.x.rounded(.towardZero), y: total.y.rounded(.towardZero))
        remainder = CGPoint(x: total.x - step.x, y: total.y - step.y)
        guard step != .zero else { return }
        let from = location
        let to = clampToScreens(CGPoint(x: from.x + step.x, y: from.y + step.y))
        // Dragging while a button is held, so drags and games that read deltas both work.
        let (type, button): (CGEventType, CGMouseButton) =
            buttonsDown.contains(.left) ? (.leftMouseDragged, .left)
            : buttonsDown.contains(.right) ? (.rightMouseDragged, .right)
            : buttonsDown.contains(.middle) ? (.otherMouseDragged, .center)
            : (.mouseMoved, .left)
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: to, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(step.x))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(step.y))
        event.post(tap: .cghidEventTap)
    }

    private var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// Global display coordinates (origin top-left of the main display).
    private func clampToScreens(_ p: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let bounds = ids.map(CGDisplayBounds)
        if bounds.contains(where: { $0.contains(p) }) { return p }
        guard let nearest = bounds.min(by: { distance(p, $0) < distance(p, $1) }) else { return p }
        return CGPoint(x: min(max(p.x, nearest.minX), nearest.maxX - 1), y: min(max(p.y, nearest.minY), nearest.maxY - 1))
    }

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }
}
