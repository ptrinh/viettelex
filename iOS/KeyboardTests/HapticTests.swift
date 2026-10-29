import XCTest

/// Rung phím (28/09/2026): UIImpactFeedbackGenerator im lặng trong extension iOS 27 ⇒
/// Core Haptics với độ mạnh theo thanh trượt 10…100 %. 29/10: mặc định 30 (trước 45), lỗi
/// Core Haptics không còn khoá vĩnh viễn về 1519 cố định, dự phòng theo độ mạnh.
final class HapticTests: XCTestCase {
    func testPercentMapsAndClamps() {
        XCTAssertEqual(KeyHaptics.intensity(forPercent: 45), 0.45, accuracy: 1e-6)
        XCTAssertEqual(KeyHaptics.intensity(forPercent: 0), 0.10, accuracy: 1e-6)
        XCTAssertEqual(KeyHaptics.intensity(forPercent: 250), 1.0, accuracy: 1e-6)
    }

    /// Tester 29/10 "mặc định quá mạnh": key vắng ⇒ 30; ai đã lưu (kể cả 45 cũ) giữ nguyên.
    func testSettingDefaultAndLoadClamp() {
        XCTAssertEqual(KeyHaptics.defaultPercent, 30)
        XCTAssertEqual(KeyboardSettings().hapticStrength, 30)
        let d = UserDefaults(suiteName: "vt-haptic-test")!
        d.removePersistentDomain(forName: "vt-haptic-test")
        let saved = UserDefaultsProvider.shared
        UserDefaultsProvider.shared = d
        defer { UserDefaultsProvider.shared = saved; d.removePersistentDomain(forName: "vt-haptic-test") }
        XCTAssertEqual(KeyboardSettings.load().hapticStrength, 30)
        d.set(45, forKey: "hapticStrength")
        XCTAssertEqual(KeyboardSettings.load().hapticStrength, 45)
        d.set(500, forKey: "hapticStrength")
        XCTAssertEqual(KeyboardSettings.load().hapticStrength, 100)
    }

    /// Hồi quy: MỘT lỗi Core Haptics từng khoá `broken` vĩnh viễn ⇒ thanh trượt vô tác dụng.
    func testBackoffRetriesAfterFailureInsteadOfLatching() {
        var b = HapticBackoff()
        XCTAssertTrue(b.canTry(now: 0))
        b.failed(now: 10)
        XCTAssertFalse(b.canTry(now: 10.2))
        XCTAssertTrue(b.canTry(now: 10.5))            // thử lại sau 0.5 s
        b.failed(now: 10.5)
        XCTAssertFalse(b.canTry(now: 11.4))
        XCTAssertTrue(b.canTry(now: 11.5))            // 1 s
        for i in 0..<20 { b.failed(now: Double(100 + i)) }
        XCTAssertTrue(b.canTry(now: 119 + HapticBackoff.maxDelay))   // trần 30 s, không bao giờ "mãi mãi"
        b.succeeded()
        XCTAssertEqual(b.failures, 0)
        XCTAssertTrue(b.canTry(now: 0))
    }

    func testResetFailuresAllowsImmediateRetry() {
        let h = KeyHaptics()
        h.resetFailures()
        XCTAssertTrue(h.backoff.canTry(now: 0))
    }

    /// Dự phòng không còn cố định 1519: theo thanh trượt, đơn điệu.
    func testFallbackFollowsStrength() {
        XCTAssertEqual(KeyHaptics.fallbackSoundID(forPercent: 10), 1519)
        XCTAssertEqual(KeyHaptics.fallbackSoundID(forPercent: KeyHaptics.defaultPercent), 1519)
        XCTAssertEqual(KeyHaptics.fallbackSoundID(forPercent: 65), 1519)
        XCTAssertEqual(KeyHaptics.fallbackSoundID(forPercent: 70), 1520)
        XCTAssertEqual(KeyHaptics.fallbackSoundID(forPercent: 100), 1520)
    }

    func testStrengthChangesIntensityAndSharpness() {
        let h = KeyHaptics()
        XCTAssertEqual(h.percent, KeyHaptics.defaultPercent)
        h.setStrength(10); let lo = (h.intensity, h.sharpness)
        h.setStrength(100); let hi = (h.intensity, h.sharpness)
        XCTAssertLessThan(lo.0, hi.0); XCTAssertLessThan(lo.1, hi.1)
        h.setStrength(500); XCTAssertEqual(h.percent, 100)
        let s = (10...100).map { KeyHaptics.sharpness(forPercent: $0) }
        XCTAssertTrue(zip(s, s.dropFirst()).allSatisfy { $0 < $1 })
    }
}
