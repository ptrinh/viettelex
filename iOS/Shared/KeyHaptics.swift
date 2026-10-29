// KeyHaptics — rung phím bằng Core Haptics, chỉnh được độ mạnh. Dùng CHUNG bàn phím +
// app (nghe/rung thử khi kéo "Độ mạnh rung" — cùng cảm giác thật).
//
// PIN (Phil 28/09 "chọn kiểu rung subtle nào mà đỡ tốn pin nhất"):
// - Mỗi phím đúng MỘT .hapticTransient (≈10–15 ms kéo actuator), không sự kiện continuous,
//   không audio. Năng lượng Taptic ~ tỉ lệ intensity² × thời gian kéo ⇒ 45 % ≈ 20 % năng
//   lượng nhịp 100 %; transient là loại rẻ nhất Core Haptics có.
// - playsHapticsOnly = true: engine KHÔNG dựng đường audio (bớt một IO unit).
// - isAutoShutdownEnabled = true: engine tự tắt phần cứng khi rảnh, tự bật lại lúc player
//   start ⇒ KHÔNG gọi engine.start() mỗi phím (bản cũ gọi mỗi lần — tốn IPC). Chỉ start khi
//   dựng engine, hoặc khi player.start báo lỗi (engine bị hệ thống dừng) thì start rồi thử lại 1 lần.
// - Pattern player dựng sẵn cho độ mạnh hiện tại, đổi độ mạnh mới dựng lại.
// - Lỗi KHÔNG còn khoá vĩnh viễn về 1519 (HapticBackoff); dự phòng theo độ mạnh (1519/1520).
import CoreHaptics
import Foundation

/// Lùi lại sau lỗi Core Haptics (29/10/2026). Bản cũ gặp MỘT lỗi (engine bị hệ thống dừng lúc
/// bàn phím ẩn/hiện, cuộc gọi, ngắt server haptics…) là `broken = true` VĨNH VIỄN cho tới khi
/// iOS giết process extension (sống rất lâu) ⇒ mọi phím rơi về AudioServices 1519 độ mạnh CỐ ĐỊNH:
/// kéo "Độ mạnh rung" không đổi gì, và 1519 mạnh hơn mặc định 45 % (tester 29/10). Nay: lỗi ⇒
/// thử lại sau 0.5 s, 1 s, 2 s… (trần 30 s); thành công ⇒ về 0; mỗi lần hiện bàn phím ⇒ về 0.
struct HapticBackoff: Equatable {
    static let baseDelay: Double = 0.5
    static let maxDelay: Double = 30
    private(set) var failures = 0
    private(set) var retryAt: Double = 0
    func canTry(now: Double) -> Bool { failures == 0 || now >= retryAt }
    mutating func failed(now: Double) {
        failures += 1
        retryAt = now + min(Self.maxDelay, Self.baseDelay * pow(2, Double(failures - 1)))
    }
    mutating func succeeded() { failures = 0; retryAt = 0 }
}

final class KeyHaptics {
    static let shared = KeyHaptics()
    /// Ghi log lỗi (bàn phím gán TouchLog.write; app để im).
    nonisolated(unsafe) static var log: (String) -> Void = { _ in }
    /// Mặc định khi người dùng CHƯA kéo thanh trượt (key vắng). 45 → 30 (29/10/2026, tester:
    /// "mặc định rung quá mạnh"); ai đã lưu giá trị thì giữ nguyên. Android: HapticStrength.DEFAULT.
    static let defaultPercent = 30
    /// Độ mạnh 10…100 % từ thanh trượt.
    private(set) var percent = KeyHaptics.defaultPercent
    private(set) var intensity: Float = KeyHaptics.intensity(forPercent: KeyHaptics.defaultPercent)
    private(set) var sharpness: Float = KeyHaptics.sharpness(forPercent: KeyHaptics.defaultPercent)
    static func intensity(forPercent p: Int) -> Float { Float(max(10, min(100, p))) / 100 }
    /// Độ "sắc" đi theo độ mạnh (0.4…0.7): nhẹ thì êm/tròn hơn, mạnh thì gắt hơn — cảm nhận
    /// khác biệt rõ hơn chỉ đổi intensity với sharpness cố định 0.6.
    static func sharpness(forPercent p: Int) -> Float {
        0.4 + 0.3 * Float(max(10, min(100, p)) - 10) / 90
    }
    /// Dự phòng khi Core Haptics không chạy (không phần cứng / đang lùi sau lỗi): system sound
    /// Taptic — 1519 "Peek" (nhẹ) ≤ 65 %, 1520 "Pop" (mạnh) trên đó. Chỉ 2 nấc nhưng vẫn theo
    /// thanh trượt (UIImpactFeedbackGenerator im lặng trong extension iOS 27).
    static func fallbackSoundID(forPercent p: Int) -> UInt32 { max(10, min(100, p)) <= 65 ? 1519 : 1520 }

    func setStrength(_ p: Int) {
        let c = max(10, min(100, p))
        guard c != percent else { return }
        percent = c
        intensity = Self.intensity(forPercent: c)
        sharpness = Self.sharpness(forPercent: c)
        player = nil   // pattern dựng lại lần rung sau
    }
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private(set) var backoff = HapticBackoff()
    /// Đồng hồ (giây) — test thay.
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    /// capabilitiesForHardware() hỏi hệ thống — đọc MỘT lần, không mỗi phím.
    private lazy var hardwareSupported: Bool = {
        let ok = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        if !ok { Self.log("haptics: máy không hỗ trợ Core Haptics → system sound") }
        return ok
    }()
    /// Số lần gọi engine.start() (test: không start mỗi phím).
    private(set) var engineStarts = 0

    /// Lần hiện bàn phím mới: thử Core Haptics lại ngay dù vừa lỗi.
    func resetFailures() { backoff.succeeded() }

    func play() -> Bool {
        guard hardwareSupported, backoff.canTry(now: clock()) else { return false }
        do {
            if engine == nil {
                let e = try CHHapticEngine()
                e.playsHapticsOnly = true
                e.isAutoShutdownEnabled = true
                e.stoppedHandler = { [weak self] _ in self?.player = nil }
                e.resetHandler = { [weak self] in self?.player = nil }
                try e.start(); engineStarts += 1
                engine = e
            }
            guard let e = engine else { return false }
            if player == nil { player = try makePlayer(e) }
            do {
                try player?.start(atTime: CHHapticTimeImmediate)
            } catch {
                // Engine bị dừng (reset/ngắt) — start lại một lần, dựng lại player, thử lại.
                try e.start(); engineStarts += 1
                player = try makePlayer(e)
                try player?.start(atTime: CHHapticTimeImmediate)
            }
            if backoff.failures > 0 { Self.log("haptics: Core Haptics chạy lại sau \(backoff.failures) lỗi") }
            backoff.succeeded()
            return true
        } catch {
            // Bỏ engine/player hỏng ⇒ lần thử sau dựng mới; trong lúc lùi dùng fallbackSoundID.
            engine = nil; player = nil
            backoff.failed(now: clock())
            if backoff.failures <= 3 || backoff.failures % 20 == 0 {
                Self.log("haptics: Core Haptics lỗi #\(backoff.failures) \(error) → system sound, thử lại sau")
            }
            return false
        }
    }

    private func makePlayer(_ e: CHHapticEngine) throws -> CHHapticPatternPlayer {
        let ev = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: 0)
        return try e.makePlayer(with: CHHapticPattern(events: [ev], parameters: []))
    }
}
