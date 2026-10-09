import Foundation
import Testing
@testable import ApexKit

private func bytes(_ hex: String) -> [UInt8] { hex.split(separator: " ").map { UInt8($0, radix: 16)! } }

@Suite struct FlydigiFrameTests {
    @Test func getInfoFrame() {
        let f = [UInt8](Flydigi.frame(.getInfo))
        #expect(f.count == 31)
        #expect(f[0..<5] == [0x5A, 0xA5, 0x01, 0x02, 0x03])
        #expect(f[5...].allSatisfy { $0 == 0 })
    }

    @Test func streamFrameLeavesUnsetOptionsUnchanged() {
        // Checksum worked out by hand: 0x11 + 0x07 + 0x01 + 4 × 0xFF = 0x415 → 0x15.
        let f = [UInt8](Flydigi.setDataStreams(controllerInput: true))
        #expect(f[0..<10] == [0x5A, 0xA5, 0x11, 0x07, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0x15])
    }

    @Test func recognisesReplyWithOrWithoutReportID() {
        #expect(Flydigi.command(of: bytes("04 5a a5 01 01")) == 0x01)
        #expect(Flydigi.command(of: bytes("5a a5 ef 00")) == 0xEF)
        #expect(Flydigi.command(of: bytes("00 14 00 00")) == nil)
    }
}

@Suite struct DeviceInfoTests {
    /// The actual reply from the user's Apex 5 on the cable (2026-10-09).
    let apex5Reply = bytes("04 5a a5 01 01 00 80 01 00 00 00 00 25 45 01 00 70 45 00 00 45 25 00 00 01 28 00 00 11 31 1f 00")

    @Test func decodesRealApex5Reply() throws {
        let info = try #require(DeviceInfo(reply: apex5Reply))
        #expect(info.deviceID == 128)
        #expect(info.modelName == "Apex 5")
        #expect(info.connection == .wired)
        #expect(info.batteryPercent == 100)
        #expect(info.charging == .charged)
        #expect(info.firmware == "7.0.4.5")
        #expect(info.receiverFirmware == nil)
        #expect(info.sensorFirmware == "4.5.2.5")
        #expect(info.radioFirmware == "1.1.3.1")
    }

    @Test func rejectsOtherReplies() {
        #expect(DeviceInfo(reply: bytes("04 5a a5 ef 00 00")) == nil)
    }
}

@Suite struct FlydigiInputReportTests {
    /// Builds an `EF` frame with chosen button bytes and axes (layout per SDL's Flydigi driver).
    func frame(b11: UInt8 = 0, b12: UInt8 = 0, b13: UInt8 = 0, b14: UInt8 = 0, ly: Int16 = 0, lt: UInt8 = 0) -> [UInt8] {
        var f = [UInt8](repeating: 0, count: 31)
        f[0] = 0x5A; f[1] = 0xA5; f[2] = 0xEF
        let y = UInt16(bitPattern: ly)
        f[5] = UInt8(y & 0xFF); f[6] = UInt8(y >> 8)
        f[11] = b11; f[12] = b12; f[13] = b13; f[14] = b14; f[15] = lt
        return f
    }

    @Test func paddlesAndExtrasAreSeparateButtons() throws {
        let s = try #require(FlydigiInputReport.parse(frame(b13: 0x3F)))
        #expect(s.buttons == [.c, .z, .m1, .m2, .m3, .m4])
    }

    @Test func faceButtonsAndDpadShareByte11() throws {
        let s = try #require(FlydigiInputReport.parse(frame(b11: 0x10 | 0x02, b14: 0x08)))
        #expect(s.buttons == [.a, .dpadRight, .guide])
    }

    @Test func stickYIsAlreadyUpPositive() throws {
        // On the real controller, pushing the left stick up reports a positive Y.
        let s = try #require(FlydigiInputReport.parse(frame(ly: 32767)))
        #expect(s.leftStick.y == 32767)
        #expect(s.motion != nil)
    }
}

@Suite struct TakeoverTests {
    @Test func acquireFrameMatchesWhatTheControllerAccepted() {
        // Sent to the real controller on 2026-10-09 and granted.
        let sent = bytes("5a a5 1c 17 01 41 70 65 78 53 74 61 74 69 6f 6e 00 00 00 00 00 00 00 00 00 a4")
        #expect([UInt8](Flydigi.acquire(true))[0..<sent.count] == sent[...])
    }

    @Test func acquireRepliesFromTheRealController() {
        #expect(Flydigi.acquireGranted(bytes("04 5a a5 1c 01 00 01 41 70 65 78")) == true)
        #expect(Flydigi.acquireGranted(bytes("04 5a a5 1c 01 00 00 00 00 00 00")) == false) // flag off
    }

    @Test func statusRepliesFromTheRealController() {
        #expect(Flydigi.thirdPartyAllowed(bytes("04 5a a5 10 01 00 01 00 00 00 01 00")) == true)
        #expect(Flydigi.thirdPartyAllowed(bytes("04 5a a5 10 01 00 01 00 00 00 00 00")) == false)
        #expect(Flydigi.thirdPartyAllowed(bytes("04 5a a5 01 01 00 01 00 00 00 01 00")) == nil)
    }
}

@Suite struct DeviceSettingsTests {
    /// The user's Apex 5 on 2026-10-09: precision 10-bit, sensitivity middle, sleep 15 min,
    /// stick smoothing/auto-calibration/rebound and Xbox Home on, screen off.
    let reply = bytes("04 5a a5 03 01 00 fb 72 01 01 0f 00 02 11 00 00")

    @Test func decodesRealSettings() throws {
        let s = try #require(DeviceSettings(reply: reply))
        #expect(s.sleepMinutes == 15)
        #expect(s.reportRate == nil)
        #expect(s.precision == .bits10)
        #expect(s.sensitivity == .middle)
        #expect(s.enabled == [.xboxHomeButton, .stickSmoothing, .stickAutoCalibration, .stickRebound, .screenOff])
        #expect(!s.available.contains(.motionSmoothing) && !s.available.contains(.audio))
        #expect(s.available.contains(.screenOff) && s.available.contains(.quickProfileSwitch))
    }

    @Test func switchFrameMatchesSpaceStationLayout() {
        // Space Station: cmd 0x13, len 4, [sub, on], sum. Xbox Home on = 13 04 02 01 → sum 0x1A.
        #expect([UInt8](Flydigi.set(.xboxHomeButton, true))[0..<7] == [0x5A, 0xA5, 0x13, 0x04, 0x02, 0x01, 0x1A])
    }

    @Test func sleepFrameCarriesMinutes() {
        #expect([UInt8](Flydigi.setSleep(minutes: 180))[0..<6] == [0x5A, 0xA5, 0x17, 0x03, 0xB4, 0xCE])
    }
}
