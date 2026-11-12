// "Âm thanh nét vuốt" (Gõ vuốt → Âm thanh nét vuốt) — phần THUẦN, dùng chung app (chọn + nghe thử) và bàn phím (phát).
// Song sinh android/keyboard/.../SwipeSound.kt: cùng khoá `swipeSound`, cùng id, cùng số. Trong lúc ngón đang vuốt một
// từ: tiếng lặp liên tục, nhỏ, như dụng cụ lướt trên giấy/bảng — to/nhỏ theo tốc độ ngón (đứng yên ⇒ im), tắt dần
// ~100 ms khi nhấc tay. Mẫu lặp: KeySoundSynth.swipeLoopSamples (tổng hợp, không file âm thanh). Phát: Keyboard/SwipeSound.swift.
//
// "Tắt" (mặc định) + "Bút chì" miễn phí; còn lại Plus (cùng cổng với Hiệu ứng nét vuốt) — chưa có Plus / Chế độ nguồn
// điện thấp ⇒ phát Bút chì, giá trị lưu giữ nguyên.
// Roi vụt / Tia sét / Plasma / Đũa phép: thêm MỘT tiếng ngắn lúc nhấc tay (không khi huỷ), to theo tốc độ ngón ~80 ms cuối
// (SwipeSoundFx.liftGain — ngón gần như đứng yên ⇒ không kêu). Đũa phép thêm lớp hạt dày (× âm lượng²) ⇒ vuốt nhanh dày hơn.
// "Âm của bạn" (custom): file người dùng chọn, xử lý thành vòng lặp (SwipeSoundCustom) — vắng/hỏng ⇒ Bút chì.
// Nốt nhạc theo phím (notes): KHÔNG vòng lặp — mỗi phím chữ ngón đi qua (vào lõi phím, mỗi phím một nốt — SwipeKeyTracker)
// gảy một nốt ngắn (SwipeNoteMap: trái → phải trầm → cao ngũ cung, hàng lệch bậc), nhạc cụ theo Âm thanh phím nếu là Piano /
// Đàn tranh / Ghi-ta, không thì Đàn tranh; to theo tốc độ (SwipeSoundFx.noteVelocity). Sáo trúc (flute): vòng lặp tiếng sáo
// đọc nhanh/chậm theo vị trí ngón (SwipeSoundFx.fluteRate — ~1,5 quãng tám, kéo nhẹ về ngũ cung), tắt dần 250 ms.
// Sóng biển / Mèo kêu / Chim hót: vòng lặp + tiếng nhấc tay như Roi vụt…; Chim hót thêm lớp tiếng hót dày (× âm lượng²).
import Foundation

enum SwipeSoundStyle: String, CaseIterable {
    case none, pencil, brush, chalk, marker, whip, lightning, plasma, wand, notes, flute, waves, cat, birds, custom

    static let key = "swipeSound"
    static let defaultValue: SwipeSoundStyle = .none
    /// Kiểu miễn phí thay cho kiểu Plus khi chưa có Plus / nguồn điện thấp.
    static let fallback: SwipeSoundStyle = .pencil

    /// Giá trị lạ / thiếu ⇒ Tắt.
    static func parse(_ raw: Any?) -> SwipeSoundStyle {
        (raw as? String).flatMap(SwipeSoundStyle.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?) -> SwipeSoundStyle { parse(d?.object(forKey: key)) }
    /// Kiểu hiện ở dòng cài đặt: kiểu Plus khi chưa có Plus ⇒ Bút chì (giá trị lưu giữ nguyên).
    static func displayed(_ raw: Any?, plus: Bool = SwipeSoundGate.allows) -> SwipeSoundStyle {
        let s = parse(raw)
        return s.isPlus && !plus ? fallback : s
    }

    var title: String {
        switch self {
        case .none: return L("Tắt")
        case .pencil: return L("Bút chì")
        case .brush: return L("Chổi lông")
        case .chalk: return L("Phấn bảng")
        case .marker: return L("Bút dạ")
        case .whip: return L("Roi vụt")
        case .lightning: return L("Tia sét")
        case .plasma: return L("Plasma")
        case .wand: return L("Đũa phép")
        case .notes: return L("Nốt nhạc theo phím")
        case .flute: return L("Sáo trúc")
        case .waves: return L("Sóng biển")
        case .cat: return L("Mèo kêu")
        case .birds: return L("Chim hót")
        case .custom: return L("Âm của bạn")
        }
    }

    /// Tắt + Bút chì miễn phí; còn lại thuộc Plus.
    var isPlus: Bool { self != .none && self != .pencil }
    /// Có tiếng ngắn lúc nhấc tay (KeySoundSynth.swipeLiftSamples).
    var hasLift: Bool {
        switch self {
        case .whip, .lightning, .plasma, .wand, .waves, .cat, .birds: return true
        default: return false
        }
    }
    /// Nốt nhạc theo phím: mỗi phím ngón đi qua một nốt (pool giọng), không vòng lặp, không vỏ âm lượng theo tốc độ.
    var isNotes: Bool { self == .notes }
    /// Sáo trúc: vòng lặp đọc với tốc độ (= cao độ) theo vị trí ngang của ngón.
    var followsX: Bool { self == .flute }
    /// Cần toạ độ tâm phím (SwipeKeyTracker) để phát.
    var needsLayout: Bool { isNotes || followsX }
    /// Kiểu có vòng lặp tổng hợp riêng trong KeySoundSynth — trừ Tắt, Âm của bạn và Nốt nhạc theo phím (không vòng lặp).
    static let synthesized: [SwipeSoundStyle] = allCases.filter { $0 != .none && $0 != .custom && $0 != .notes }
}

/// Cổng Plus: như Hiệu ứng nét vuốt (quyền theme cao cấp).
enum SwipeSoundGate {
    static var allows: Bool { PlusGate.isUnlocked(.premiumThemes) }
    static func allows(_ s: SwipeSoundStyle) -> Bool { !s.isPlus || allows }
}

/// Kiểu thực phát — hàm thuần (test). = Android SwipeSoundPolicy.
enum SwipeSoundPolicy {
    /// Tắt / âm lượng 0 ⇒ Tắt (0 chi phí). Kiểu Plus chưa có Plus / nguồn điện thấp ⇒ Bút chì.
    static func active(setting: SwipeSoundStyle, plus: Bool, lowPower: Bool, volumePercent: Int) -> SwipeSoundStyle {
        if setting == .none || volumePercent <= 0 { return .none }
        if setting.isPlus && (!plus || lowPower) { return SwipeSoundStyle.fallback }
        return setting
    }
}

/// Số + hàm thuần dùng chung hai nền tảng (Android SwipeSoundFx cùng số). Tốc độ: pt/s (iOS) = dp/s (Android).
enum SwipeSoundFx {
    /// Dưới tốc độ này ⇒ im (ngón gần như đứng yên).
    static let speedMin = 40.0
    /// Từ tốc độ này trở lên ⇒ to hết cỡ (trần 1).
    static let speedFull = 1500.0
    /// Làm mượt tốc độ (EMA) — hằng thời gian, giây.
    static let speedTau = 0.05
    /// Bước thời gian tối đa đưa vào EMA.
    static let maxDt = 0.1
    /// Điểm gộp cách nhau dưới chừng này giây ⇒ chờ điểm sau (tránh chia cho ~0).
    static let minDt = 0.001
    /// Không có điểm mới quá chừng này ⇒ ngón đứng yên ⇒ đích = 0.
    static let hold = 0.08
    /// Âm lượng tiến về đích — hằng thời gian, giây.
    static let rampTau = 0.03
    /// Nhấc tay / huỷ: tắt dần TUYẾN TÍNH trong chừng này giây.
    static let fadeOut = 0.1
    /// Android: nhịp đặt âm lượng SoundPool (giây). iOS chạy từng mẫu trong render.
    static let tick = 0.025
    /// Tiếng nhấc tay: đo tốc độ trong chừng này giây cuối trước khi nhấc.
    static let liftWindow = 0.08
    /// Dưới tốc độ này (pt/s, trung bình `liftWindow` cuối) ⇒ không có tiếng nhấc tay (ngón gần như đứng yên).
    static let liftMin = 150.0
    /// Bản nghe thử trong app: độ to tiếng nhấc tay cố định (nét mẫu chậm dần về 0 ở cuối).
    static let previewLiftGain = 0.8
    /// Sáo trúc: nhấc tay / huỷ tắt dần chậm hơn (hơi thở nhả ra), các kiểu khác `fadeOut`.
    static let fluteRelease = 0.25
    /// Sáo trúc: cao độ trượt về đích (portamento) — hằng thời gian, giây.
    static let glideTau = 0.04
    /// Sáo trúc: vòng lặp tổng hợp ở MIDI này (D5 ≈ 587,5 Hz); tốc độ đọc 1 = cao độ gốc.
    static let fluteBase = 74
    /// Sáo trúc: mép trái → mép phải vùng phím chữ = chừng này nửa cung (1,5 quãng tám, giữa = fluteBase).
    static let fluteSpan = 18.0
    /// Sáo trúc: kéo cao độ về nốt ngũ cung gần nhất (0 = trượt tự do, 1 = nhảy hẳn nốt).
    static let flutePull = 0.7
    /// Nốt nhạc theo phím: độ to nốt = noteFloor + (1 − noteFloor) · speedGain(tốc độ) — vuốt chậm vẫn nghe.
    static let noteFloor = 0.4
    /// Nốt nhạc theo phím: số giọng (nốt chồng nhau tối đa; nốt thứ 7 thay nốt cũ nhất).
    static let noteVoices = 6
    /// Nốt nhạc theo phím, bản nghe thử: độ to cố định mỗi nốt.
    static let previewNoteGain = 0.7

    /// Thời gian tắt dần khi nhấc tay / huỷ của kiểu.
    static func release(_ s: SwipeSoundStyle) -> Double { s == .flute ? fluteRelease : fadeOut }

    /// Độ to nốt (Nốt nhạc theo phím) theo tốc độ ngón đã làm mượt.
    static func noteVelocity(_ speed: Double) -> Double { noteFloor + (1 - noteFloor) * speedGain(speed) }

    /// Nốt ngũ cung (C D E G A) gần MIDI thực `m` nhất (hoà ⇒ nốt thấp).
    static func nearestPentatonic(_ m: Double) -> Int {
        let lo = Int(m.rounded(.down))
        var best = lo, bd = Double.infinity
        for k in (lo - 2)...(lo + 3) {
            switch ((k % 12) + 12) % 12 {
            case 0, 2, 4, 7, 9:
                let d = abs(Double(k) - m)
                if d < bd { bd = d; best = k }
            default: break
            }
        }
        return best
    }

    /// Sáo trúc: MIDI (thực) theo vị trí ngang `u` 0…1 của ngón trên vùng phím chữ — tuyến tính fluteSpan nửa cung quanh
    /// fluteBase, kéo `flutePull` về nốt ngũ cung gần nhất.
    static func fluteMidi(_ u: Double) -> Double {
        let x = min(1, max(0, u))
        let m = Double(fluteBase) - fluteSpan / 2 + fluteSpan * x
        return m + flutePull * (Double(nearestPentatonic(m)) - m)
    }

    /// Sáo trúc: tốc độ đọc vòng lặp (= tỉ lệ tần số so với fluteBase) — luôn trong 0,5…2 (giới hạn SoundPool Android).
    static func fluteRate(_ u: Double) -> Double { pow(2, (fluteMidi(u) - Double(fluteBase)) / 12) }

    /// Tốc độ (đã làm mượt) → 0…1: căn bậc hai cho cảm giác đều tay, trần 1.
    static func speedGain(_ speed: Double) -> Double {
        if speed <= speedMin { return 0 }
        return min(1, (speed - speedMin) / (speedFull - speedMin)).squareRoot()
    }

    /// Độ to tiếng nhấc tay 0…1 theo tốc độ ~80 ms cuối: dưới `liftMin` ⇒ 0; căn bậc hai, đủ cỡ từ `speedFull`.
    static func liftGain(_ speed: Double) -> Double {
        if speed <= liftMin { return 0 }
        return min(1, (speed - liftMin) / (speedFull - liftMin)).squareRoot()
    }

    /// Đích âm lượng: ngón đứng yên quá `hold` ⇒ 0.
    static func target(_ gain: Double, sinceMove: Double) -> Double { sinceMove > hold ? 0 : gain }

    /// EMA tốc độ: `inst` = tốc độ tức thời, `dt` = giây kể từ điểm trước.
    static func smooth(_ prev: Double, _ inst: Double, dt: Double) -> Double {
        let a = 1 - exp(-min(dt, maxDt) / speedTau)
        return prev + (inst - prev) * a
    }
}

/// Đo tốc độ ngón (main, mỗi điểm vuốt) — struct, không cấp phát (vòng đệm cấp một lần). = Android SwipeSoundMeter.
struct SwipeSoundMeter {
    private(set) var speed = 0.0
    private var lastX = 0.0, lastY = 0.0, lastT = 0.0
    /// Vòng đệm các đoạn gần nhất (quãng đường, giờ cuối đoạn) — cho tốc độ `liftWindow` cuối lúc nhấc tay.
    static let ring = 32
    private var segD = [Double](repeating: 0, count: Self.ring), segT = [Double](repeating: 0, count: Self.ring)
    private var head = 0, filled = 0

    mutating func reset(x: Double, y: Double, t: Double) { lastX = x; lastY = y; lastT = t; speed = 0; filled = 0 }

    /// Một điểm mới (toạ độ pt, thời gian giây).
    mutating func move(x: Double, y: Double, t: Double) {
        let dt = t - lastT
        guard dt >= SwipeSoundFx.minDt else { return }   // điểm gộp trùng giờ: đo từ điểm cũ ở lần sau
        let dist = hypot(x - lastX, y - lastY)
        speed = SwipeSoundFx.smooth(speed, dist / dt, dt: dt)
        lastX = x; lastY = y; lastT = t
        segD[head] = dist; segT[head] = t
        head = (head + 1) % Self.ring
        filled = min(filled + 1, Self.ring)
    }

    var gain: Double { SwipeSoundFx.speedGain(speed) }

    /// Tốc độ trung bình trong `liftWindow` giây trước `now` (quãng đường các đoạn kết thúc trong cửa sổ / cửa sổ).
    /// Ngón đứng yên lâu hơn cửa sổ trước khi nhấc ⇒ 0.
    func recentSpeed(at now: Double) -> Double {
        let from = now - SwipeSoundFx.liftWindow
        var sum = 0.0
        for k in 0..<filled {
            let j = (head - 1 - k + Self.ring) % Self.ring
            if segT[j] < from { break }
            if segT[j] <= now + 1e-9 { sum += segD[j] }
        }
        return sum / SwipeSoundFx.liftWindow
    }
}

/// Vỏ âm lượng 0…1 theo bước `step` giây (iOS: 1 mẫu; Android: tick). Đang vuốt: tiến về đích (rampTau); nhấc tay
/// (`release`): giảm tuyến tính về 0 trong `fade` (mặc định fadeOut; Sáo trúc fluteRelease). = Android SwipeSoundEnvelope.
struct SwipeSoundEnvelope {
    private let k: Double
    private let fadeFrac: Double
    private(set) var gain = 0.0
    private(set) var releasing = false
    private var fadeStep = 0.0

    init(step: Double, fade: Double = SwipeSoundFx.fadeOut) {
        k = 1 - exp(-step / SwipeSoundFx.rampTau)
        fadeFrac = step / fade
    }

    mutating func begin() { releasing = false }

    mutating func release() {
        guard !releasing else { return }
        releasing = true
        fadeStep = max(gain * fadeFrac, 1e-9)
    }

    @discardableResult
    mutating func next(_ target: Double) -> Double {
        gain = releasing ? max(0, gain - fadeStep) : gain + (target - gain) * k
        return gain
    }

    /// Đã tắt hẳn sau nhấc tay.
    var finished: Bool { releasing && gain <= 0 }

    mutating func reset() { gain = 0; releasing = false; fadeStep = 0 }
}

/// "Âm của bạn": file người dùng chọn → MỘT vòng lặp liền mạch (22,05 kHz mono). Xử lý thuần (= Android SwipeSoundCustom):
/// giải mã ở app (AVAudioFile, KeySoundImport.decode) → `process` → WAV trong App Group (`fileURL`; bàn phím đọc — cần Full
/// Access). Chỉ trên máy này: không tải lên đâu, KHÔNG vào file sao lưu (như âm phím tự chọn — chỉ key `swipeSound` đi theo).
enum SwipeSoundCustom {
    /// Tối đa chừng này giây làm vòng lặp (phần sau bị cắt).
    static let maxDuration = 3.0
    /// Âm ngắn hơn ⇒ lặp lại nối tiếp cho đủ (vòng quá ngắn nghe như rè).
    static let minLoop = 0.5
    /// Cùng đỉnh với vòng lặp tổng hợp (Bút chì / Phấn bảng).
    static let targetPeak: Float = 0.30
    static let fileName = "swipesound-custom.wav"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppFlavor.appGroup)?
            .appendingPathComponent(fileName)
    }

    enum Failure: Error, Equatable { case empty, silent }
    struct Result: Equatable {
        let samples: [Float]
        /// true ⇒ âm gốc (sau khi bỏ lặng) dài hơn `maxDuration`, đã cắt.
        let truncated: Bool
    }

    /// mono ở `rate` → 22,05 kHz, bỏ lặng đầu/cuối, cắt ≤ `maxDuration`, nối đuôi vào đầu bằng trộn công suất đều 80 ms
    /// (như vòng tổng hợp ⇒ không "tách"), chuẩn hoá đỉnh `targetPeak`.
    static func process(_ mono: [Float], sampleRate rate: Double) throws -> Result {
        guard !mono.isEmpty, rate > 0 else { throw Failure.empty }
        let sr = KeySoundSynth.swipeSampleRate
        let x = KeySoundCustom.resample(mono, from: rate, to: sr)
        let peak = x.reduce(Float(0)) { max($0, abs($1)) }
        guard peak >= 0.001 else { throw Failure.silent }
        let thr = max(peak * 0.05, 0.001)
        let first = x.firstIndex { abs($0) >= thr } ?? 0
        let last = x.lastIndex { abs($0) >= thr } ?? (x.count - 1)
        let f = Int((KeySoundSynth.swipeCrossfade * sr).rounded())
        let cap = Int((maxDuration * sr).rounded())
        let avail = last + 1 - first
        let truncated = avail > cap + f
        var y = Array(x[first..<(first + min(avail, cap + f))])
        let need = Int((minLoop * sr).rounded()) + f
        if y.count < need {
            // Âm ngắn: mở/đóng 5 ms rồi lặp lại nối tiếp cho đủ.
            let e = min(y.count / 2, Int((0.005 * sr).rounded()))
            for i in 0..<e {
                let w = Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(e)))
                y[i] *= w; y[y.count - 1 - i] *= w
            }
            var z = [Float]()
            z.reserveCapacity(need + y.count)
            while z.count < need { z += y }
            y = z
        }
        let len = y.count - f
        var out = [Float](repeating: 0, count: len)
        for i in 0..<len {
            if i < f {
                let w = Double(i) / Double(f)
                out[i] = Float(Double(y[i]) * sin(Double.pi / 2 * w) + Double(y[len + i]) * cos(Double.pi / 2 * w))
            } else {
                out[i] = y[i]
            }
        }
        let p2 = out.reduce(Float(0)) { max($0, abs($1)) }
        guard p2 > 0 else { throw Failure.silent }
        let g = targetPeak / p2
        return Result(samples: out.map { $0 * g }, truncated: truncated)
    }

    /// Vòng lặp đã xử lý (WAV 22,05 kHz mono). nil ⇒ vắng/hỏng.
    static func load(_ url: URL?) -> [Float]? {
        guard let url, let d = try? Data(contentsOf: url), let w = KeySoundSynth.parseWav(d), !w.samples.isEmpty,
              w.samples.count <= Int(maxDuration * KeySoundSynth.swipeSampleRate) + 16
        else { return nil }
        return KeySoundCustom.resample(w.samples, from: w.sampleRate, to: KeySoundSynth.swipeSampleRate)
    }

    /// Vòng lặp phát cho "Âm của bạn": file hợp lệ, không thì Bút chì (giá trị lưu giữ nguyên).
    static func resolvedLoop(_ custom: [Float]?) -> [Float] {
        if let c = custom, !c.isEmpty { return c }
        return KeySoundSynth.swipeLoopSamples(.pencil)
    }
}

/// Nốt nhạc theo phím: bảng phím → bậc ngũ cung (thuần, = Android SwipeNoteMap). Trong hàng: trái → phải = trầm → cao
/// (một bậc mỗi phím); hàng trên lệch `rowShift` bậc so với hàng dưới (q-hàng +4, a-hàng +2, z-hàng 0) ⇒ mỗi từ một đường
/// giai điệu riêng ("việt" và "viết" khác đường vuốt ⇒ khác giai điệu). Bậc 0…13 từ G3 (55) theo thang ngũ cung của nhạc cụ
/// (Piano/Ghi-ta G A B D E, Đàn tranh G A C D E) ⇒ G3…D6.
enum SwipeNoteMap {
    static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    static let rowShift = [4, 2, 0]
    static let base = 55
    /// Số bậc khác nhau (0…13) = số nốt dựng sẵn mỗi nhạc cụ.
    static let steps = 14
    /// Bậc của chữ a…z (chỉ số 0…25).
    static let letterSteps: [Int] = (0..<26).map { k in
        for (r, row) in rows.enumerated() {
            if let c = Array(row.unicodeScalars).firstIndex(where: { Int($0.value) - 97 == k }) { return c + rowShift[r] }
        }
        return 0
    }

    static func step(letter k: Int) -> Int { letterSteps[k] }

    static func midi(step: Int, scale: [Int]) -> Int { base + 12 * (step / 5) + scale[step % 5] }
}

/// Phím chữ dưới ngón đang vuốt (thuần, = Android SwipeKeyTracker) — dựng MỘT lần từ tâm phím của layout gõ vuốt (52 số
/// x,y của a…z, như SwipeLayout.centers), mỗi điểm O(1) không cấp phát: chọn hàng gần nhất theo y, đoán cột theo bước
/// phím rồi so 3 tâm lân cận. Chỉ tính là "vào phím" khi điểm nằm trong LÕI phím (`core` = 70 % bề ngang / khoảng hàng)
/// ⇒ ngón rung ở ranh giới hai phím không gảy lặp. `feed` trả phím mới (khác phím vừa gảy) hoặc −1 ⇒ mỗi phím một nốt
/// (quay lại phím đó sau một phím khác ⇒ gảy lại — đúng đường đi).
struct SwipeKeyTracker: Equatable {
    static let core = 0.7
    let keyWidth: Double
    let rowHeight: Double
    /// Mép trái / phải vùng phím chữ (Sáo trúc: vị trí ngang 0…1).
    let minX: Double, maxX: Double
    /// Phẳng (không mảng lồng ⇒ không giữ/nhả tham chiếu mỗi điểm): tâm hàng r ở flatX[rowStart[r]..<rowStart[r+1]].
    private let rowY: [Double]
    private let rowStart: [Int]
    private let flatX: [Double]
    private let flatLetter: [Int]
    private let coreX: Double, coreY: Double
    private(set) var last = -1

    /// nil ⇒ không có phím chữ nào / bước phím ≤ 0.
    init?(centers c: [Float], keyWidth kw: Float) {
        guard kw > 0, c.count == 52 else { return nil }
        let kwd = Double(kw)
        var ys = [Double](), xs = [[Double]](), ls = [[Int]](), all = [Double]()
        for row in SwipeNoteMap.rows {
            var lx = [Double](), ll = [Int](), sy = 0.0
            for ch in row.unicodeScalars {
                let k = Int(ch.value) - 97
                let x = c[2 * k]
                guard x.isFinite else { continue }
                lx.append(Double(x)); ll.append(k); sy += Double(c[2 * k + 1]); all.append(Double(x))
            }
            xs.append(lx); ls.append(ll)
            ys.append(lx.isEmpty ? .infinity : sy / Double(lx.count))
        }
        guard let lo = all.min(), let hi = all.max() else { return nil }
        var rh = Double.infinity
        for r in 0..<2 where ys[r].isFinite && ys[r + 1].isFinite { rh = min(rh, abs(ys[r + 1] - ys[r])) }
        keyWidth = kwd
        rowHeight = rh.isFinite && rh > 0 ? rh : kwd * 1.4
        rowY = ys
        rowStart = [0, xs[0].count, xs[0].count + xs[1].count, xs[0].count + xs[1].count + xs[2].count]
        flatX = xs.flatMap { $0 }; flatLetter = ls.flatMap { $0 }
        coreX = Self.core * kwd / 2; coreY = Self.core * rowHeight / 2
        minX = lo - kwd / 2; maxX = hi + kwd / 2
    }

    /// Chữ (0…25) có LÕI chứa điểm, −1 = không phím nào (khe, hàng số/cách, ngoài vùng).
    func key(x: Double, y: Double) -> Int {
        var best = -1, bd = Double.infinity
        for r in 0..<3 {
            let d = abs(y - rowY[r])
            if d < bd { bd = d; best = r }
        }
        guard best >= 0, bd <= coreY else { return -1 }
        let s0 = rowStart[best], n = rowStart[best + 1] - s0
        let g = min(n - 1, max(0, Int(((x - flatX[s0]) / keyWidth + 0.5).rounded(.down))))
        var bc = -1, bdx = Double.infinity
        var c = max(0, g - 1)
        let cEnd = min(n - 1, g + 1)
        while c <= cEnd {
            let dx = abs(x - flatX[s0 + c])
            if dx < bdx { bdx = dx; bc = c }
            c += 1
        }
        guard bdx <= coreX else { return -1 }
        return flatLetter[s0 + bc]
    }

    /// Một điểm vuốt: chữ VỪA vào (khác chữ đã gảy gần nhất) hoặc −1.
    mutating func feed(x: Double, y: Double) -> Int {
        let k = key(x: x, y: y)
        guard k >= 0, k != last else { return -1 }
        last = k
        return k
    }

    mutating func reset() { last = -1 }

    /// Vị trí ngang 0…1 trên vùng phím chữ (kẹp).
    func unitX(_ x: Double) -> Double { min(1, max(0, (x - minX) / (maxX - minX))) }

    /// Tâm QWERTY chuẩn (= SwipeLayout.qwerty: hàng 2 lệch 0,5 phím, hàng 3 lệch 1,5 phím) — bản nghe thử + test.
    static func qwertyCenters(keyWidth kw: Float, rowHeight rh: Float) -> [Float] {
        var c = [Float](repeating: .infinity, count: 52)
        let rows: [(String, Double)] = [("qwertyuiop", 0.5), ("asdfghjkl", 1.0), ("zxcvbnm", 2.0)]
        for (r, (row, x0)) in rows.enumerated() {
            for (i, ch) in row.unicodeScalars.enumerated() {
                let k = Int(ch.value) - 97
                c[2 * k] = Float((x0 + Double(i)) * Double(kw))
                c[2 * k + 1] = Float((Double(r) + 0.5) * Double(rh))
            }
        }
        return c
    }
}
