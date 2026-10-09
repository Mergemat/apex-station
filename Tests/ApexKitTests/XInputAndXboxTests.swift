import Foundation
import Testing
@testable import ApexKit

/// Reports recorded from a real Apex 5 over the cable.
private func report(_ hex: String) -> [UInt8] { hex.split(separator: " ").map { UInt8($0, radix: 16)! } }

@Suite struct XInputReportTests {
    @Test func restingPadHasNothingPressed() throws {
        let s = try #require(XInputReport.parse(report("00 14 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")))
        #expect(s == GamepadState())
    }

    @Test(arguments: [
        ("00 14 00 10 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00", GamepadButtons.a),
        ("00 14 00 80 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00", .y),
        ("00 14 00 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00", .guide),
        ("00 14 00 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00", .leftBumper),
        ("00 14 20 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00", .back),
        ("00 14 10 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00", .start),
        ("00 14 08 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00", .dpadRight),
    ])
    func recordedButtons(hex: String, expected: GamepadButtons) throws {
        #expect(try #require(XInputReport.parse(report(hex))).buttons == expected)
    }

    @Test func recordedStickExtremes() throws {
        let up = try #require(XInputReport.parse(report("00 14 00 00 00 00 00 00 ff 7f 00 00 00 00 00 00 00 00 00 00")))
        #expect(up.leftStick == StickPosition(x: 0, y: 32767))
        let left = try #require(XInputReport.parse(report("00 14 00 00 00 00 00 00 00 00 00 80 00 00 00 00 00 00 00 00")))
        #expect(left.rightStick == StickPosition(x: -32768, y: 0))
    }

    @Test func ignoresNonInputPackets() {
        #expect(XInputReport.parse([0x01, 0x03, 0x02]) == nil)
    }
}

/// Reports from the Apex 5 in PC Bluetooth mode, where it shows up as an Xbox Wireless Controller.
@Suite struct XboxBluetoothReportTests {
    private func state(_ hex: String) throws -> GamepadState {
        var s = GamepadState()
        #expect(XboxBluetoothReport.apply(report(hex), to: &s))
        return s
    }

    @Test func recordedRestingPadIsCentred() throws {
        // Recorded from the controller lying on the desk.
        let s = try state("01 00 80 ff 80 00 80 ff 80 00 00 00 00 00 00 00")
        #expect(s.buttons.isEmpty)
        #expect(s.leftStick == StickPosition(x: 0, y: -255))
        #expect(s.rightStick == StickPosition(x: 0, y: -255))
        #expect(s.leftTrigger == 0 && s.rightTrigger == 0)
    }

    @Test func sticksAreUpPositive() throws {
        let s = try state("01 ff ff 00 00 00 00 ff ff 00 00 00 00 00 00 00")
        #expect(s.leftStick == StickPosition(x: 32767, y: 32767))
        #expect(s.rightStick == StickPosition(x: -32768, y: -32767))
    }

    @Test func triggersScaleTo255() throws {
        let s = try state("01 00 80 00 80 00 80 00 80 ff 03 00 02 00 00 00")
        #expect(s.leftTrigger == 255)
        #expect(s.rightTrigger == 128)
    }

    @Test(arguments: [
        ("01 00 80 00 80 00 80 00 80 00 00 00 00 00 01 00", GamepadButtons.a),
        ("01 00 80 00 80 00 80 00 80 00 00 00 00 00 04 00", .x),
        ("01 00 80 00 80 00 80 00 80 00 00 00 00 00 20 00", .rightBumper),
        ("01 00 80 00 80 00 80 00 80 00 00 00 00 00 80 00", .start),
        ("01 00 80 00 80 00 80 00 80 00 00 00 00 00 00 02", .rightStick),
        ("01 00 80 00 80 00 80 00 80 00 00 00 00 03 00 00", .dpadRight),
        ("01 00 80 00 80 00 80 00 80 00 00 00 00 08 00 00", GamepadButtons([.dpadUp, .dpadLeft])),
    ])
    func buttons(hex: String, expected: GamepadButtons) throws {
        #expect(try state(hex).buttons == expected)
    }

    @Test func xboxButtonComesSeparatelyAndSticks() throws {
        var s = GamepadState()
        _ = XboxBluetoothReport.apply([2, 1], to: &s)
        _ = XboxBluetoothReport.apply(report("01 00 80 00 80 00 80 00 80 00 00 00 00 00 01 00"), to: &s)
        #expect(s.buttons == [.guide, .a])
        _ = XboxBluetoothReport.apply([2, 0], to: &s)
        #expect(s.buttons == .a)
    }

    @Test func ignoresOtherReports() {
        var s = GamepadState()
        #expect(!XboxBluetoothReport.apply([4, 200], to: &s))
        #expect(XboxBluetoothReport.battery([4, 255]) == 100)
        #expect(XboxBluetoothReport.battery([1, 255]) == nil)
    }

    @Test func rumbleReport() {
        #expect(XboxBluetoothReport.rumble(strong: 30, weak: 120, duration: .milliseconds(350)) == [3, 3, 0, 0, 30, 100, 35, 0, 0])
    }
}

@Suite struct XboxWirelessReportTests {
    @Test func restingPadIsCentred() {
        let r = [UInt8](XboxWirelessReport.encode(GamepadState()))
        #expect(r.count == 17 && r[0] == 0x01)
        #expect(r[1...8] == [0x00, 0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0x80]) // 32768 each
        #expect(r[13] == 0) // hat centred
        #expect(r[14] == 0 && r[15] == 0)
    }

    @Test func stickYIsFlippedAndExtremesDoNotOverflow() {
        var s = GamepadState()
        s.leftStick.y = .max // full up in XInput
        #expect([UInt8](XboxWirelessReport.encode(s))[3...4] == [0x01, 0x00]) // 1 = top in HID
        s.leftStick.y = .min // full down; -Int16.min would overflow
        #expect([UInt8](XboxWirelessReport.encode(s))[3...4] == [0xFF, 0xFF])
    }

    @Test func buttonsUseXboxBluetoothUsageOrder() {
        var s = GamepadState()
        s.buttons = [.a, .guide]
        let r = [UInt8](XboxWirelessReport.encode(s))
        #expect(UInt16(r[14]) | UInt16(r[15]) << 8 == 0b100_0000_0001) // usage 1 and 11
    }

    static let hats: [(GamepadButtons, UInt8)] = [
        (.dpadUp, 1), ([.dpadUp, .dpadRight], 2), (.dpadRight, 3), ([.dpadDown, .dpadRight], 4),
        (.dpadDown, 5), ([.dpadDown, .dpadLeft], 6), (.dpadLeft, 7), ([.dpadUp, .dpadLeft], 8),
        ([.dpadUp, .dpadDown], 0), ([], 0),
    ]

    @Test(arguments: hats)
    func dpadBecomesHat(buttons: GamepadButtons, hat: UInt8) {
        var s = GamepadState()
        s.buttons = buttons
        #expect([UInt8](XboxWirelessReport.encode(s))[13] == hat)
    }

    @Test func triggersScaleTo10Bits() {
        var s = GamepadState()
        s.leftTrigger = 255
        s.rightTrigger = 128
        let r = [UInt8](XboxWirelessReport.encode(s))
        #expect(UInt16(r[9]) | UInt16(r[10]) << 8 == 1023)
        #expect(UInt16(r[11]) | UInt16(r[12]) << 8 == 514)
    }

    @Test func rumbleAsSDLSendsIt() throws {
        // SDL: enable 0x0F, LT 0, RT 0, strong 100, weak 50, duration 0xFF, delay 0, loop 0.
        let r = try #require(XboxWirelessReport.decodeRumble([0x0F, 0, 0, 100, 50, 0xFF, 0, 0]))
        #expect(r == .init(strong: 255, weak: 127, duration: nil))
    }

    @Test func rumbleRespectsEnableBitsAndDuration() throws {
        let r = try #require(XboxWirelessReport.decodeRumble([0x03, 0x01, 0, 0, 100, 100, 30, 0, 1]))
        #expect(r == .init(strong: 0, weak: 255, duration: .milliseconds(600))) // report ID stripped, 2 loops
    }
}

@Suite struct PadLinkTests {
    @Test func messagesSurviveBeingSplitAcrossReads() {
        let rumble = XboxWirelessReport.Rumble(strong: 255, weak: 64, duration: .milliseconds(600))
        let stream = [UInt8](PadLink.encode(.ready) + PadLink.encode(.rumble(rumble)) + PadLink.encode(.rumble(.init(strong: 0, weak: 0, duration: nil))))
        var buffer = Array(stream.prefix(4))
        #expect(PadLink.decode(&buffer) == [.ready])
        #expect(buffer.count == 3) // the rumble message is still incomplete
        buffer += stream.dropFirst(4)
        #expect(PadLink.decode(&buffer) == [.rumble(rumble), .rumble(.init(strong: 0, weak: 0, duration: nil))])
        #expect(buffer.isEmpty)
    }
}
