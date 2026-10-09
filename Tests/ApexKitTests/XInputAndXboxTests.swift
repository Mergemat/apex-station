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
