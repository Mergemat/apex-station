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

    @Test func smallKeysAndShoulderExtrasMatchSpaceStation() throws {
        // Space Station's table: byte 14 Menu(Fn) 0x01, Turbo 0x02, Home 0x08; byte 13 M5 0x40, M6 0x80.
        let s = try #require(FlydigiInputReport.parse(frame(b13: 0xC0, b14: 0x0B)))
        #expect(s.buttons == [.fn, .turbo, .guide, .leftMacro, .rightMacro])
    }

    @Test func triggerPressedFlagsAreNotButtons() throws {
        // Byte 12's 0x10/0x20 mirror the analog triggers; they must not light anything else.
        let s = try #require(FlydigiInputReport.parse(frame(b12: 0x30)))
        #expect(s.buttons.isEmpty)
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

@Suite struct ProfileTests {
    /// Profile 0 read from the user's Apex 5 (2026-10-09), and the raw A3 replies it came from.
    let record = try! [UInt8](Data(contentsOf: Bundle.module.url(forResource: "Fixtures/apex5-profile0", withExtension: "bin")!))
    let replies = try! String(contentsOf: Bundle.module.url(forResource: "Fixtures/apex5-profile0-replies", withExtension: "txt")!, encoding: .utf8)

    @Test func assemblesTheRealReplyChunks() throws {
        var assembler = ProfileAssembler()
        var result: (slot: Int, bytes: [UInt8])?
        for line in replies.split(separator: "\n") where line.hasPrefix("in ") {
            let hex = line.split(separator: ":", maxSplits: 1)[1]
            if let r = assembler.add(bytes(String(hex).trimmingCharacters(in: .whitespaces))) { result = r }
        }
        let r = try #require(result)
        #expect(r.slot == 0)
        #expect(r.bytes == record)
    }

    @Test func decodesTheRealButtonRemaps() throws {
        let p = try #require(Profile(slot: 0, bytes: record))
        #expect(p.formatVersion == "3.1")
        #expect(p.name == "配置1")
        // Matches what the controller sent over Xbox mode on day one: paddles act as triggers/bumpers.
        #expect(p.mapping(for: .m1) == .button(.rt))
        #expect(p.mapping(for: .m2) == .button(.lt))
        #expect(p.mapping(for: .m3) == .button(.rb))
        #expect(p.mapping(for: .m4) == .button(.lb))
        #expect(p.mapping(for: .lm) == .button(.l3))
        #expect(p.mapping(for: .rm) == .button(.r3))
        #expect(p.mapping(for: .a) == .standard)
        #expect(p.remapped.count == 6)
        #expect(p.turbo(for: .a) == nil)
    }

    @Test func remapEncodesLikeSpaceStation() throws {
        var p = try #require(Profile(slot: 0, bytes: record))
        p.setMapping(.button(.b), for: .a)
        #expect(p.mapping(for: .a) == .button(.b))
        #expect(p.bytes[13 + 4 * 3..<13 + 4 * 3 + 3] == [5, 0, 0]) // target B, no turbo
        p.setMapping(.standard, for: .m1)
        #expect(p.bytes[13 + 18 * 3..<13 + 18 * 3 + 3] == [0xFF, 0, 0]) // the controller's own encoding
        // Remapping a button to itself is the same as no remap.
        p.setMapping(.button(.y), for: .y)
        #expect(p.mapping(for: .y) == .standard)
    }

    @Test func turboKeepsTheTarget() throws {
        var p = try #require(Profile(slot: 0, bytes: record))
        p.setTurbo((.hold, 10), for: .a)
        #expect(p.turbo(for: .a)?.mode == .hold && p.turbo(for: .a)?.speed == 10)
        #expect(p.mapping(for: .a) == .standard)
        p.setTurbo(nil, for: .a)
        #expect(p.turbo(for: .a) == nil)
    }

    @Test func writeSendsOnlyChangedChunks() throws {
        let old = try #require(Profile(slot: 1, bytes: record))
        var new = old
        new.setMapping(.button(.b), for: .a) // byte 25: chunk 1 only
        let frames = Flydigi.writeProfile(from: old, to: new).map { [UInt8]($0) }
        #expect(frames.count == 2)
        // Start: A4, len 6, slot 1, first chunk 1, one chunk, size 20, sum (A4+06+01+01+01+14)=C1.
        #expect(frames[0][0..<10] == [0x5A, 0xA5, 0xA4, 0x06, 0x01, 0x01, 0x01, 0x14, 0xC1, 0x00])
        // Chunk: A5, len 23, index 0, then bytes 20-39 of the new record.
        #expect(frames[1][0..<5] == [0x5A, 0xA5, 0xA5, 0x17, 0x00])
        #expect(Array(frames[1][5..<25]) == Array(new.bytes[20..<40]))
        #expect(Flydigi.writeProfile(from: old, to: old).isEmpty)
    }

    @Test func realProfileHasDefaultSticks() throws {
        let p = try #require(Profile(slot: 0, bytes: record))
        // User's profile: curve type 0, dead zone 0, edge 127, rectangle (bytes 109-122, 790-813).
        for left in [true, false] {
            #expect(p.stick(left: left) == StickConfig(curve: .standard, deadZone: 0, edge: 127, circular: false))
        }
    }

    @Test func stickEditsTouchOnlyTheirBytes() throws {
        let old = try #require(Profile(slot: 0, bytes: record))
        var p = old
        p.setStick(StickConfig(curve: .quick, deadZone: 20, edge: 110, circular: true), left: false)
        #expect(p.stick(left: false) == StickConfig(curve: .quick, deadZone: 20, edge: 110, circular: true))
        #expect(p.stick(left: true) == old.stick(left: true))
        let changed = (0..<Profile.size).filter { p.bytes[$0] != old.bytes[$0] }
        #expect(changed == [116, 117, 122, 802, 812]) // type, dead zone, edge, extra type, circularity
    }

    @Test func realProfileHasNormalTriggers() throws {
        let p = try #require(Profile(slot: 0, bytes: record))
        #expect(p.trigger(left: true) == TriggerConfig(start: 0, end: 255, effect: .normal))
        #expect(p.trigger(left: false).effect == .normal)
    }

    /// The controller's own trigger menu writes these blocks (recorded on an Apex 4, same format).
    @Test(arguments: [
        (TriggerEffect.racingDefault, "01 00 0a 32 64 01 ff 46 00 ff 00 1e 00 00 00"),
        (TriggerEffect.recoilDefault, "02 00 0a 32 64 01 ff 46 00 ff 00 01 32 0f 01"),
        (TriggerEffect.sniperDefault, "03 00 0a 0a 64 01 ff 46 00 ff 32 1e 01 00 01"),
        (TriggerEffect.lock(position: 40), "04 00 0a 0a 64 01 ff 46 00 ff 28 fa 01 00 00"),
        (TriggerEffect.vibrationDefault, "05 02 0a 32 01 01 01 5a 00 ff 01 01 01 5a 00"),
    ])
    func triggerModesMatchTheControllersOwnPresets(effect: TriggerEffect, block: String) throws {
        var p = try #require(Profile(slot: 0, bytes: record))
        p.setTrigger(TriggerConfig(start: 0, end: 255, effect: effect), left: false)
        #expect(Array(p.bytes[205..<220]) == bytes(block))
        #expect(p.trigger(left: false).effect == effect)
        #expect(p.trigger(left: true) == TriggerConfig(start: 0, end: 255, effect: .normal)) // left untouched
    }

    @Test func realProfileVibrationAndGyro() throws {
        let p = try #require(Profile(slot: 0, bytes: record))
        // Bytes 145-153: on, both motors strength 40. Bytes 137-144: gyro off, LT activates (toggle), dead zone 4, sensitivity 25.
        #expect(p.vibration == VibrationConfig(enabled: true, left: 40, right: 40))
        #expect(p.gyro == GyroConfig(target: .off, key: .lt, activation: .toggle, deadZone: 4, sensitivity: 25, racing: false))
    }

    @Test func gyroAndVibrationEditsTouchOnlyTheirBytes() throws {
        let old = try #require(Profile(slot: 0, bytes: record))
        var p = old
        p.setGyro(GyroConfig(target: .rightStick, key: .lt, activation: .hold, deadZone: 4, sensitivity: 60, racing: false))
        p.setVibration(VibrationConfig(enabled: true, left: 80, right: 20))
        #expect(p.gyro.target == .rightStick && p.gyro.activation == .hold && p.gyro.sensitivity == 60)
        #expect(p.vibration == VibrationConfig(enabled: true, left: 80, right: 20))
        let changed = Set((0..<Profile.size).filter { p.bytes[$0] != old.bytes[$0] })
        #expect(changed.isSubset(of: Set(137...153)))
    }

    @Test func renameWritesUTF16Name() throws {
        var p = try #require(Profile(slot: 0, bytes: record))
        p.setName("Shooters")
        #expect(p.name == "Shooters")
        p.setName("A very long profile name")
        #expect(p.name == "A very lon") // 10 characters fit
    }

    @Test func realProfileHasNoMacros() throws {
        let p = try #require(Profile(slot: 0, bytes: record))
        #expect(p.macros.isEmpty)
    }

    @Test func macroEncodingMatchesSpaceStationsLayout() throws {
        var p = try #require(Profile(slot: 0, bytes: record))
        // M1 plays A down at 0 ms, up at 50 ms; M2 (toggle) plays B down at 0, up at 1000 ms.
        p.setMacros([
            Macro(key: .m1, mode: .once, steps: [.init(key: .a, press: true, time: 0), .init(key: .a, press: false, time: 50)]),
            Macro(key: .m2, mode: .toggle, steps: [.init(key: .b, press: true, time: 0), .init(key: .b, press: false, time: 1000)]),
        ])
        // Worked out by hand from Space Station's encoder (5 macro slots, 10 ms ticks):
        // count 2; offsets [0, 3, 0, 0, 0] (macro 2 starts after macro 1's header + 2 actions);
        // M1 header 12 02 00 01, actions 00 00 04 01 / 05 00 04 00;
        // M2 header 13 02 00 03, actions 00 00 05 01 / 64 00 05 00.
        let expected = bytes("02 00 03 00 00 00 12 02 00 01 00 00 04 01 05 00 04 00 13 02 00 03 00 00 05 01 64 00 05 00")
        #expect(Array(p.bytes[230..<(230 + expected.count)]) == expected)
        #expect(p.bytes[230 + expected.count] == 0xFF)
        #expect(p.mapping(for: .m1) == .macro && p.mapping(for: .m2) == .macro)
        #expect(p.macros.count == 2 && p.macros[1].mode == .toggle && p.macros[1].steps.last?.time == 1000)
        // Removing a macro hands the button back.
        p.setMacros([p.macros[0]])
        #expect(p.mapping(for: .m2) == .standard && p.macros.count == 1)
    }

    @Test func readFrameMatchesSpaceStation() {
        // A3, len 4, slot 0, chunk size 20, sum 0xBB. This exact frame got the replies above.
        #expect([UInt8](Flydigi.readProfile(0))[0..<7] == [0x5A, 0xA5, 0xA3, 0x04, 0x00, 0x14, 0xBB])
    }

    @Test func activeProfileFromTheRealReply() {
        #expect(Flydigi.activeProfile(bytes("04 5a a5 a1 01 00 00 85 02 ff ff 60 98 ff ff")) == 0)
        #expect(Flydigi.activeProfile(bytes("04 5a a5 a1 01 00 06 85 02")) == 2) // 4-7 mean the same slots
    }
}

@Suite struct LightingTests {
    /// Profile 0's lighting from the user's Apex 5: factory animation, 12 LEDs, 10 frames.
    let record = try! [UInt8](Data(contentsOf: Bundle.module.url(forResource: "Fixtures/apex5-lighting0", withExtension: "bin")!))

    @Test func decodesTheRealLighting() throws {
        let l = try #require(Lighting(slot: 0, bytes: record))
        #expect(record.count == 380)
        #expect(l.mode == .standard)
        #expect(l.brightness == 52 && l.speed == 4)
        #expect(l.ledCount == 12 && l.frameCount == 10)
        #expect(l.color == Lighting.Color(r: 0, g: 0x80, b: 0x80))
    }

    @Test func steadyColorPaintsEveryLED() throws {
        var l = try #require(Lighting(slot: 0, bytes: record))
        l.setColor(.init(r: 255, g: 0, b: 40), mode: .steady)
        #expect(l.mode == .steady && l.color == .init(r: 255, g: 0, b: 40))
        #expect(stride(from: 20, to: 380, by: 3).allSatisfy { l.bytes[$0] == 255 && l.bytes[$0 + 1] == 0 && l.bytes[$0 + 2] == 40 })
        #expect(Array(l.bytes[0..<3]) == Array(record[0..<3])) // header version untouched
    }

    @Test func lightingWriteUsesLightingCommands() throws {
        let old = try #require(Lighting(slot: 2, bytes: record))
        var new = old
        new.setBrightness(80) // byte 6: chunk 0 only
        let frames = Flydigi.writeLighting(from: old, to: new).map { [UInt8]($0) }
        #expect(frames.count == 2)
        #expect(frames[0][0..<8] == [0x5A, 0xA5, 0xA8, 0x06, 0x02, 0x00, 0x01, 0x14])
        #expect(frames[1][2] == 0xA9 && frames[1][11] == 80) // chunk data starts at byte 5; brightness is its byte 6
    }

    @Test func resetFrame() {
        #expect([UInt8](Flydigi.resetProfile(2))[0..<6] == [0x5A, 0xA5, 0xAF, 0x03, 0x02, 0xB4])
    }
}

struct MacroRecorderTests {
    private func state(_ buttons: GamepadButtons, lt: UInt8 = 0) -> GamepadState {
        var s = GamepadState()
        s.buttons = buttons
        s.leftTrigger = lt
        return s
    }

    @Test func recordsPressesAndReleasesFromTheFirstPress() {
        var r = MacroRecorder()
        r.add(state([]), at: 500)
        r.add(state([.a]), at: 1000)
        r.add(state([.a, .x]), at: 1040)
        r.add(state([.x], lt: 200), at: 1100)
        r.add(state([]), at: 1250)
        #expect(r.finish(at: 2000) == [
            .init(key: .a, press: true, time: 0), .init(key: .x, press: true, time: 40),
            .init(key: .a, press: false, time: 100), .init(key: .lt, press: true, time: 100),
            .init(key: .x, press: false, time: 250), .init(key: .lt, press: false, time: 250),
        ])
    }

    @Test func ignoresButtonsAGameNeverSeesAndReleasesHeldKeysAtTheEnd() {
        var r = MacroRecorder()
        r.add(state([.m1, .turbo]), at: 0)
        r.add(state([.m1, .b]), at: 30)
        #expect(r.finish(at: 90) == [.init(key: .b, press: true, time: 0), .init(key: .b, press: false, time: 60)])
    }
}
