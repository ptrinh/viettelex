// Âm phím tự chọn + nghe/rung thử trong app (Phím & cử chỉ → Phản hồi khi chạm).
//
// Nhập: .fileImporter (m4a/mp3/wav/caf/aiff…) → AVAudioFile giải mã (tối đa 10 s đầu) →
// trộn mono → KeySoundCustom.process (44.1 kHz, bỏ lặng đầu/cuối, cắt ≤ 300 ms, mở/đóng
// mềm, chuẩn hoá đỉnh 0.8 + trần RMS) → WAV 16-bit mono (~26 KB) trong App Group
// (KeySoundCustom.fileURL). Bàn phím nạp lười khi kiểu = custom; vắng/hỏng ⇒ "Nhẹ nhàng".
// File KHÔNG vào file sao lưu (chỉ key keySoundStyle).
//
// Nghe thử: AVAudioPlayer từ đúng bộ mẫu bàn phím dùng (KeySoundSynth.bank), âm lượng theo
// cùng đường cong. Session .ambient + mixWithOthers GIỐNG bàn phím ⇒ không ngắt nhạc, và
// IM khi gạt chế độ im lặng — cố ý: nghe thử phải đúng cảm giác lúc gõ (gạt im lặng thì
// bàn phím cũng im); chú thích dưới thanh trượt nhắc điều này.
import AVFoundation
import UIKit

enum KeySoundImport {
    enum Failure: LocalizedError, Equatable {
        case unreadable, tooLarge, silent, noStorage
        var errorDescription: String? {
            switch self {
            case .unreadable: return L("Không đọc được file âm thanh này. Hãy thử m4a, mp3, wav, caf hoặc aiff.")
            case .tooLarge: return L("File quá lớn (tối đa 30 MB).")
            case .silent: return L("File không có tiếng (toàn im lặng).")
            case .noStorage: return L("Không lưu được âm (thiếu App Group).")
            }
        }
    }
    struct Outcome: Equatable { let duration: Double; let truncated: Bool }

    static let maxBytes = 30 * 1024 * 1024
    static let maxDecodeSeconds = 10.0

    /// Giải mã + xử lý + ghi `dest` (nguyên tử). Ném Failure.
    @discardableResult
    static func importFile(_ src: URL, to dest: URL? = KeySoundCustom.fileURL) throws -> Outcome {
        guard let dest else { throw Failure.noStorage }
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        if let size = (try? src.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxBytes { throw Failure.tooLarge }
        let (mono, rate) = try decode(src)
        let r: KeySoundCustom.Result
        do { r = try KeySoundCustom.process(mono, sampleRate: rate) } catch { throw Failure.silent }
        try KeySoundSynth.wav(r.samples).write(to: dest, options: .atomic)
        return Outcome(duration: Double(r.samples.count) / KeySoundSynth.sampleRate, truncated: r.truncated)
    }

    /// AVAudioFile → mono Float ở tần số gốc (≤ 10 s đầu).
    static func decode(_ url: URL) throws -> ([Float], Double) {
        let f: AVAudioFile
        do { f = try AVAudioFile(forReading: url) } catch { throw Failure.unreadable }
        let fmt = f.processingFormat
        let frames = AVAudioFrameCount(min(f.length, AVAudioFramePosition(fmt.sampleRate * maxDecodeSeconds)))
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { throw Failure.unreadable }
        do { try f.read(into: buf, frameCount: frames) } catch { throw Failure.unreadable }
        guard let ch = buf.floatChannelData else { throw Failure.unreadable }
        let n = Int(buf.frameLength), cc = Int(fmt.channelCount)
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<cc {
            let p = ch[c]
            for i in 0..<n { mono[i] += p[i] }
        }
        if cc > 1 { let k = 1 / Float(cc); for i in 0..<n { mono[i] *= k } }
        return (mono, fmt.sampleRate)
    }

    static func remove(_ dest: URL? = KeySoundCustom.fileURL) {
        guard let dest else { return }
        try? FileManager.default.removeItem(at: dest)
    }

    /// Độ dài (s) âm tự chọn đang lưu; nil ⇒ chưa có.
    static func storedDuration(_ url: URL? = KeySoundCustom.fileURL) -> Double? {
        KeySoundCustom.load(url).map { Double($0.count) / KeySoundSynth.sampleRate }
    }
}

/// "Âm thanh nét vuốt" → "Âm của bạn": cùng đường nhập với âm phím tự chọn (giải mã KeySoundImport.decode, cùng lỗi), xử lý
/// thành vòng lặp (SwipeSoundCustom.process: 22,05 kHz mono, ≤ 3 s, nối vòng, đỉnh như vòng tổng hợp) → WAV trong App Group.
/// Chỉ trên máy: không tải lên, KHÔNG vào file sao lưu (như âm phím tự chọn).
enum SwipeSoundImport {
    @discardableResult
    static func importFile(_ src: URL, to dest: URL? = SwipeSoundCustom.fileURL) throws -> KeySoundImport.Outcome {
        guard let dest else { throw KeySoundImport.Failure.noStorage }
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        if let size = (try? src.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > KeySoundImport.maxBytes {
            throw KeySoundImport.Failure.tooLarge
        }
        let (mono, rate) = try KeySoundImport.decode(src)
        let r: SwipeSoundCustom.Result
        do { r = try SwipeSoundCustom.process(mono, sampleRate: rate) } catch { throw KeySoundImport.Failure.silent }
        try KeySoundSynth.wav(r.samples, sampleRate: Int(KeySoundSynth.swipeSampleRate)).write(to: dest, options: .atomic)
        return KeySoundImport.Outcome(duration: Double(r.samples.count) / KeySoundSynth.swipeSampleRate, truncated: r.truncated)
    }

    static func remove(_ dest: URL? = SwipeSoundCustom.fileURL) {
        guard let dest else { return }
        try? FileManager.default.removeItem(at: dest)
    }

    /// Độ dài (s) vòng lặp đang lưu; nil ⇒ chưa có / hỏng.
    static func storedDuration(_ url: URL? = SwipeSoundCustom.fileURL) -> Double? {
        SwipeSoundCustom.load(url).map { Double($0.count) / KeySoundSynth.swipeSampleRate }
    }
}

/// Nghe thử âm phím / rung thử trong app.
final class KeyFeedbackPreview {
    static let shared = KeyFeedbackPreview()
    private var player: AVAudioPlayer?
    private var playerKey: String?
    private var sessionReady = false
    private var impact: UIImpactFeedbackGenerator?

    /// System sound ID của click bàn phím iOS (chữ / xoá / phím chức năng) — chỉ để NGHE THỬ kiểu
    /// "iOS" trong app (playInputClick chỉ kêu trong input view của bàn phím).
    static let systemClickIDs: [SystemSoundID] = [1104, 1155, 1156]

    /// Nghe thử khi chọn kiểu: chữ → xoá → phím chức năng (KeySoundSynth.previewSequence).
    func playStyle(_ raw: String, volume: Int) {
        if !KeySoundStyle.needsEngine(raw) {
            for (i, id) in Self.systemClickIDs.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 * Double(i)) { AudioServicesPlaySystemSound(id) }
            }
            return
        }
        playSound(style: raw, volume: volume, kind: nil)
    }

    /// `kind` nil ⇒ chuỗi nghe thử 3 tiếng; có ⇒ một tiếng (thanh âm lượng).
    func playSound(style raw: String, volume: Int, kind: KeySoundKind? = .letter) {
        if !KeySoundStyle.needsEngine(raw) {   // "iOS": âm lượng theo hệ thống
            AudioServicesPlaySystemSound(Self.systemClickIDs[kind?.rawValue ?? 0]); return
        }
        let key = KeySoundCustom.bankKey(style: raw, customURL: KeySoundCustom.fileURL) + "/\(kind?.rawValue ?? -1)"
        if !sessionReady {
            let s = AVAudioSession.sharedInstance()
            try? s.setCategory(.ambient, options: [.mixWithOthers])
            try? s.setActive(true)
            sessionReady = true
        }
        if key != playerKey || player == nil {
            if let inst = KeyInstrument.of(raw) {   // Piano / Đàn tranh: giai điệu ngắn / một nốt C4 (22.05 kHz)
                let s = kind == nil ? inst.previewMelody() : inst.note(60)
                player = try? AVAudioPlayer(data: KeySoundSynth.wav(s, sampleRate: Int(PianoSynth.sampleRate)))
            } else {
                let custom = raw == KeySoundStyle.custom.rawValue ? KeySoundCustom.load(KeySoundCustom.fileURL) : nil
                let bank = KeySoundSynth.bank(raw, custom: custom)
                let samples = kind.map { bank.samples[$0.rawValue] } ?? KeySoundSynth.previewSequence(bank.samples)
                player = try? AVAudioPlayer(data: KeySoundSynth.wav(samples))
            }
            player?.prepareToPlay()
            playerKey = key
        }
        guard let p = player else { return }
        p.volume = KeySoundSynth.gain(forPercent: volume)
        p.currentTime = 0
        p.play()
    }

    /// "Âm thanh nét vuốt": nghe thử một nét vuốt mẫu (KeySoundSynth.swipePreviewSamples — vòng lặp × vỏ âm lượng theo
    /// tốc độ, tắt dần lúc nhấc tay). Tắt ⇒ dừng. Cùng session .ambient (im khi gạt im lặng) như bàn phím.
    func playSwipe(_ s: SwipeSoundStyle, volume: Int) {
        guard s != .none else { player?.stop(); return }
        if !sessionReady {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.ambient, options: [.mixWithOthers])
            try? session.setActive(true)
            sessionReady = true
        }
        // Âm của bạn: dựng lại mỗi lần (file có thể vừa đổi); vắng/hỏng ⇒ Bút chì như bàn phím.
        // Nốt nhạc theo phím: nhạc cụ của Âm thanh phím (không phải nhạc cụ ⇒ Đàn tranh) — như bàn phím.
        let inst = KeyInstrument.of(UserDefaults(suiteName: AppFlavor.appGroup)?.string(forKey: "keySoundStyle")) ?? .dantranh
        let key = s == .custom ? "swipe/custom/\(UUID())" : "swipe/" + s.rawValue + (s.isNotes ? "/" + inst.rawValue : "")
        if key != playerKey || player == nil {
            let samples = s == .custom
                ? KeySoundSynth.swipePreview(loop: SwipeSoundCustom.resolvedLoop(SwipeSoundCustom.load(SwipeSoundCustom.fileURL)))
                : KeySoundSynth.swipePreviewSamples(s, instrument: inst)
            player = try? AVAudioPlayer(data: KeySoundSynth.wav(samples, sampleRate: Int(KeySoundSynth.swipeSampleRate)))
            player?.prepareToPlay()
            playerKey = key
        }
        guard let p = player else { return }
        p.volume = KeySoundSynth.gain(forPercent: volume)
        p.currentTime = 0
        p.play()
    }

    /// Rung thử đúng như bàn phím (Core Haptics cùng độ mạnh); máy không có ⇒ impact nhẹ.
    func playHaptic(strength: Int) {
        KeyHaptics.shared.setStrength(strength)
        if KeyHaptics.shared.play() { return }
        if impact == nil { impact = UIImpactFeedbackGenerator(style: .light) }
        impact?.impactOccurred(intensity: CGFloat(KeyHaptics.intensity(forPercent: strength)))
    }
}
