import XCTest
@testable import VietTelex

// "Phát tiếng khi đổi Việt/Anh": chỉ khi người dùng tự đổi, đi lên = VietTelex.
final class SwitchSoundTests: XCTestCase {

    func testOffByDefault() {
        XCTAssertFalse(UserDefaults(suiteName: "switch-sound-\(UUID().uuidString)")!.bool(forKey: "switchSound"))
    }

    func testOnlyForAUserMadeSwitchBetweenVietTelexAndAnother() {
        func play(_ on: Bool, _ was: Bool, _ now: Bool, _ gesture: Bool) -> Bool {
            SwitchSound.shouldPlay(enabled: on, wasVietTelex: was, isVietTelex: now, userGesture: gesture)
        }
        XCTAssertTrue(play(true, false, true, true))
        XCTAssertTrue(play(true, true, false, true))
        XCTAssertFalse(play(false, false, true, true))   // tắt
        XCTAssertFalse(play(true, false, true, false))   // macOS tự đổi theo app/tài liệu
        XCTAssertFalse(play(true, false, false, true))   // ABC → bộ gõ khác: không liên quan
        XCTAssertFalse(play(true, true, true, true))
    }

    func testWavIsValidShortAndRisingForVietnamese() {
        let vi = [UInt8](SwitchSound.wav(vietnamese: true)), en = [UInt8](SwitchSound.wav(vietnamese: false))
        XCTAssertEqual(vi.count, en.count)
        XCTAssertNotEqual(vi, en)
        XCTAssertEqual(String(bytes: vi[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(bytes: vi[8..<12], encoding: .ascii), "WAVE")
        func u32(_ w: [UInt8], _ at: Int) -> Int { Int(w[at]) | Int(w[at+1]) << 8 | Int(w[at+2]) << 16 | Int(w[at+3]) << 24 }
        XCTAssertEqual(u32(vi, 4), vi.count - 8)
        XCTAssertEqual(u32(vi, 40), vi.count - 44)
        XCTAssertEqual(u32(vi, 24), SwitchSound.sampleRate)
        let frames = (vi.count - 44) / 2
        XCTAssertLessThanOrEqual(frames * 1000 / SwitchSound.sampleRate, 120)
        func crossings(_ w: [UInt8], _ r: Range<Int>) -> Int {
            var n = 0; var prev: Int16 = 0
            for i in r {
                let v = Int16(bitPattern: UInt16(w[44 + i*2]) | UInt16(w[45 + i*2]) << 8)
                XCTAssertLessThan(abs(Int(v)), 32767 / 3)   // nhỏ tiếng
                if (prev < 0) != (v < 0) { n += 1 }
                prev = v
            }
            return n
        }
        XCTAssertLessThan(crossings(vi, 0..<frames/2), crossings(vi, frames/2..<frames))
        XCTAssertGreaterThan(crossings(en, 0..<frames/2), crossings(en, frames/2..<frames))
        XCTAssertNotNil(NSSound(data: Data(vi)))   // AppKit đọc được
    }
}
