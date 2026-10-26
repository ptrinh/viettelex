// "Bạn đồng hành" (Keyboard buddy, Plus, Phil 19/10/2026): nhân vật nhỏ ở góc phải thanh gợi ý — gõ thì
// nhảy (gõ càng nhanh càng sung), ngừng gõ thì lắc nhẹ ~8 s rồi ngủ. Phần THUẦN (không UIKit) — song sinh
// android/keyboard/.../KeyboardBuddy.kt: cùng khoá `keyboardBuddy`, cùng id, cùng máy trạng thái, cùng
// bậc tốc độ, cùng hàm dáng nhảy, cùng bảng hình vẽ (test số chung `BuddyRig.checksum`).
//
// Luật hiệu năng (feature-flags-perf-policy):
//  • Tắt (mặc định) / chưa Plus ⇒ KeyboardView không tạo view nào (`buddy == nil`) — đường phím đọc một optional.
//  • Bật: mỗi phím chỉ ghi giờ vào vòng 16 ô + đếm (không cấp phát); đổi trạng thái mới đụng layer, ở lượt
//    runloop sau. Hoạt ảnh = Core Animation trên transform các bộ phận (render server chạy), không timer
//    mỗi khung. Ngủ = dáng tĩnh, "z z" chạy ~2 s rồi gỡ hẳn ⇒ 0 hoạt ảnh.
//  • Chế độ nguồn điện thấp ⇒ chỉ dáng tĩnh (đứng / ngủ), không nhảy.
//
// Hình vẽ là DỮ LIỆU (`BuddyRig`: mảnh hình + điểm xoay) — đổi nét vẽ không đụng code; `BuddyArt.sprites`
// chừa sẵn đường cho bộ khung hình vẽ sẵn (hoạ sĩ) sau này.
import Foundation

// MARK: - Cài đặt

/// Nhân vật (giá trị lưu App Group / sao lưu = rawValue — CHỈ thêm cuối).
enum BuddyCharacter: String, CaseIterable {
    case off, girl, boy, cat, chick, shiba, koi, panda, pig, dragon, eagle

    static let key = "keyboardBuddy"
    static let defaultValue: BuddyCharacter = .off

    static func parse(_ raw: Any?) -> BuddyCharacter {
        (raw as? String).flatMap(BuddyCharacter.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?) -> BuddyCharacter { parse(d?.object(forKey: key)) }

    var title: String {
        switch self {
        case .off: return L("Tắt")
        case .girl: return L("Cô gái")
        case .boy: return L("Chàng trai")
        case .cat: return L("Mèo")
        case .chick: return L("Gà con")
        case .shiba: return L("Chó Shiba")
        case .koi: return L("Cá Koi")
        case .panda: return L("Gấu trúc")
        case .pig: return L("Heo con")
        case .dragon: return L("Rồng con")
        case .eagle: return L("Đại bàng")
        }
    }

    /// Mèo dùng miễn phí (Phil 27/10/2026); các nhân vật khác thuộc Plus.
    var isPlus: Bool { self != .off && self != .cat }
}

/// Kiểu vẽ RIÊNG từng nhân vật (Phil 26/10/2026): Hoạt hình = bộ khung hình PNG vẽ sẵn (BuddySprites, mặc
/// định) / Vẽ nét = khung vector BuddyRig (trang phục mùa lễ, đạo cụ lễ theo từ, thêm điệu nhảy). Lưu App
/// Group `buddyStyle.<id nhân vật>` (cùng khoá + id Android); bàn phím đọc lần hiện kế như đổi nhân vật.
/// Chỉ nạp tài nguyên của kiểu đang chọn (Hoạt hình: ảnh atlas; Vẽ nét: không ảnh nào).
enum BuddyStyle: String, CaseIterable {
    case sprite, vector

    static let defaultValue: BuddyStyle = .sprite

    static func key(_ c: BuddyCharacter) -> String { "buddyStyle.\(c.rawValue)" }
    static func hasAtlas(_ c: BuddyCharacter) -> Bool { [.girl, .boy, .cat, .chick].contains(c) }
    func resolved(for c: BuddyCharacter) -> BuddyStyle { Self.hasAtlas(c) ? self : .vector }
    static func parse(_ raw: Any?) -> BuddyStyle {
        (raw as? String).flatMap(BuddyStyle.init(rawValue:)) ?? defaultValue
    }
    static func load(_ d: UserDefaults?, _ c: BuddyCharacter) -> BuddyStyle { parse(d?.object(forKey: key(c))).resolved(for: c) }

    var title: String {
        switch self {
        case .sprite: return L("Hoạt hình")
        case .vector: return L("Vẽ nét")
        }
    }

    /// Mùa lễ có hiệu lực: Hoạt hình ⇒ không trang phục / đạo cụ lễ (nil) kể cả đang mùa lễ.
    func season(_ s: BuddySeason?) -> BuddySeason? { self == .vector ? s : nil }
}

/// "Vị trí & cỡ" (Phil 26/10/2026) — CHUNG mọi nhân vật, cùng khoá + miền Android: cỡ 1…20 (5 = cỡ gốc; 1…5 mỗi nấc
/// 8 %; 5…20 tăng đều theo cấp số nhân tới cỡ 20 = cao trọn bàn phím), lề phải / lề trên −100…+100 pt.
/// Đọc lúc hiện bàn phím, khung tính một lần lúc layout (0 việc mỗi phím).
struct BuddyPlacement: Equatable {
    static let sizeKey = "buddySize", padRightKey = "buddyPadRight", padTopKey = "buddyPadTop"
    static let sizeRange = 1...20, padRange = -100...100
    /// Nấc chỉnh lề trong trang cài đặt; lề phải chừa thêm trên thanh gợi ý tối đa `zonePadMax` (lề lớn hơn chỉ dời
    /// nhân vật, không bóp thanh gợi ý).
    static let padStep = 5, zonePadMax = 10
    static let defaultSize = 5
    static let standard = BuddyPlacement()

    var size = defaultSize
    /// Dương = cách mép phải thêm (dời trái); âm = dời phải (có thể bị cắt ở mép).
    var padRight = 0
    /// Dương = dời xuống; âm = dời lên.
    var padTop = 0

    /// Hệ số cỡ: 1…5 tuyến tính (1 → 0,68×, 5 → 1×); 5…20 mỗi nấc nhân đều, cỡ 20 = `full` (cao trọn bàn phím /
    /// cao cỡ gốc). `full` ≤ 1 ⇒ không lớn hơn cỡ gốc.
    func scale(full: Double) -> Double {
        let n = Double(size - Self.defaultSize)
        if n <= 0 { return 1 + n * 0.08 }
        return pow(max(full, 1), n / Double(Self.sizeRange.upperBound - Self.defaultSize))
    }

    static func load(_ d: UserDefaults?) -> BuddyPlacement {
        func int(_ k: String, _ def: Int, _ r: ClosedRange<Int>) -> Int {
            guard let v = d?.object(forKey: k) as? Int else { return def }
            return min(max(v, r.lowerBound), r.upperBound)
        }
        return BuddyPlacement(size: int(sizeKey, defaultSize, sizeRange), padRight: int(padRightKey, 0, padRange),
                              padTop: int(padTopKey, 0, padRange))
    }

    /// Ô chừa trên thanh gợi ý (chip / 📋 / 😊 dời trái) theo cỡ + lề phải dương. `base` = ô cỡ gốc. Cỡ lớn chỉ
    /// chừa tối đa 1,4× (cỡ 10 cũ) — nhân vật to hơn thì đè lên chip, không bóp mất thanh gợi ý.
    func zoneWidth(_ base: Double) -> Double {
        (base * min(1 + Double(size - Self.defaultSize) * 0.08, 1.4)).rounded() + Double(min(max(0, padRight), Self.zonePadMax))
    }

    /// Khung vẽ từ khung cỡ gốc `f`: neo ĐÁY-PHẢI như cũ, cao × `scale`, rộng ≥ `minWidth`; to hơn mà đỉnh vượt
    /// đỉnh khung gốc (trần bàn phím — không vẽ được) ⇒ lớn dần xuống phím. Lề × `unit` (iOS pt = 1, Android px/dp).
    /// `fullHeight` = cao bàn phím tính từ đỉnh khung gốc (cỡ 20 phủ trọn); nil ⇒ cỡ 20 = 2,2× cỡ gốc.
    func frame(standard f: BuddyRect, minWidth: Double, unit: Double = 1, fullHeight: Double? = nil) -> BuddyRect {
        let full = fullHeight.map { $0 / max(f.h, 1) } ?? 2.2
        let h = (f.h * scale(full: full)).rounded()
        let w = max(minWidth, h)
        let right = f.x + f.w - Double(padRight) * unit
        let top = max(f.y, f.maxY - h) + Double(padTop) * unit
        return BuddyRect(x: right - w, y: top, w: w, h: h)
    }
}

/// Cổng Plus: đi cùng quyền giao diện cao cấp (như hiệu ứng khi bấm phím).
enum BuddyGate {
    static var allows: Bool { PlusGate.isUnlocked(.premiumThemes) }
    static func allows(_ c: BuddyCharacter) -> Bool { !c.isPlus || allows }
}

enum BuddyPolicy {
    /// Nhân vật thực hiện — hàm thuần: tắt / hết Plus ⇒ `.off` (không tạo view).
    static func active(setting: BuddyCharacter, plus: Bool) -> BuddyCharacter {
        guard setting != .off, plus else { return .off }
        return setting
    }

    /// Đọc lúc hiện bàn phím (applyAppearance) — không mỗi phím.
    static func current(_ d: UserDefaults?) -> BuddyCharacter {
        let s = BuddyCharacter.load(d)
        guard s != .off else { return .off }
        return active(setting: s, plus: BuddyGate.allows(s))
    }

    /// Trạng thái HIỂN THỊ: nguồn điện thấp ⇒ không nhảy / không cổ vũ / không "z z" (chỉ dáng tĩnh).
    static func visual(_ p: BuddyPhase, lowPower: Bool) -> BuddyPhase {
        guard lowPower else { return p }
        switch p {
        case .dancing, .idle, .cheering, .awake, .react: return .awake
        case .asleep: return .asleep(zzz: false)
        }
    }

    /// Trạng thái này có hoạt ảnh chạy không (dáng tĩnh = không).
    static func animates(_ p: BuddyPhase) -> Bool {
        switch p {
        case .dancing, .idle, .cheering, .react, .asleep(zzz: true): return true
        case .awake, .asleep(zzz: false): return false
        }
    }
}

// MARK: - Tốc độ gõ → bậc nhảy

/// Bậc nhảy theo số phím trong `window` giây gần nhất (≈ khoảng cách giữa các phím). Cùng ngưỡng với
/// "Lửa combo" (ComboMeter: 6 / 10 / 14 phím trong 2 s ≈ 3 / 5 / 7 phím mỗi giây). Bậc 0…3; trễ
/// (`hysteresis`) để không nhảy qua lại ở sát ngưỡng.
enum BuddyTempo {
    static let window = 2.0
    static let thresholds = [6, 10, 14]
    static let hysteresis = 2
    static let tiers = 4

    static func raw(_ n: Int, slack: Int = 0) -> Int {
        var lv = 0
        for th in thresholds where n >= th - slack { lv += 1 }
        return lv
    }

    /// Lên bậc ngay; xuống chỉ khi tụt dưới ngưỡng − `hysteresis`.
    static func tier(count n: Int, previous p: Int) -> Int {
        max(raw(n), min(p, raw(n, slack: hysteresis)))
    }
}

// MARK: - Máy trạng thái (thuần, theo dấu giờ)

enum BuddyPhase: Equatable {
    /// Ngủ; `zzz` = đang chạy "z z" (~2 s đầu sau khi thiếp đi).
    case asleep(zzz: Bool)
    /// Thức, đứng yên (chỉ còn ở chế độ nguồn điện thấp — BuddyPolicy.visual).
    case awake
    /// Vừa ngừng gõ (hết đuôi nhảy, chưa tới `BuddyBrain.sleepAfter`): lắc hông nhẹ, chậm rồi mới ngủ.
    case idle
    /// Nhảy bậc 0…3.
    case dancing(Int)
    /// Cổ vũ ngắn (chọn từ gợi ý).
    case cheering
    /// Phản ứng ngắn (BuddyReaction: giận / thả tim / cười / ngạc nhiên / buồn / hoảng khi xoá dồn).
    case react(BuddyReaction)
}

struct BuddyBrain {
    /// Nhảy thêm sau phím cuối.
    static let tail = 0.6
    /// Lắc nhẹ (`.idle`) từng này giây sau đuôi nhảy rồi mới ngủ (Phil 26/10/2026).
    static let idle = 8.0
    /// Không gõ từng này giây ⇒ ngủ (= đuôi nhảy + lắc nhẹ).
    static let sleepAfter = tail + idle
    /// "z z" chạy từng này giây rồi dừng hẳn.
    static let zzz = 2.0
    static let cheer = 0.6
    static let capacity = 16
    /// Xoá dồn: quá từng này phím ⌫ liên tiếp (cách nhau ≤ `deleteGap` s) ⇒ hoảng.
    static let panicAfter = 8
    static let deleteGap = 0.5

    private var times = [Double](repeating: -Double.greatestFiniteMagnitude, count: BuddyBrain.capacity)
    private var head = 0
    private(set) var lastKey = -Double.greatestFiniteMagnitude
    private(set) var tier = 0
    private(set) var cheerUntil = -Double.greatestFiniteMagnitude
    private(set) var reaction: BuddyReaction?
    private(set) var reactUntil = -Double.greatestFiniteMagnitude
    /// Tăng mỗi lần BẮT ĐẦU một phản ứng — phản ứng liên tiếp ⇒ diễn LẠI từ đầu (không chồng).
    private(set) var reactSerial = 0
    private(set) var deleteRun = 0
    private var lastDelete = -Double.greatestFiniteMagnitude

    /// Một phím lúc `t` (giây). Không cấp phát.
    mutating func press(at t: Double) {
        deleteRun = 0
        tap(at: t)
    }

    private mutating func tap(at t: Double) {
        if t - lastKey > BuddyTempo.window { resetRing() }   // lượt gõ mới: bậc tính lại từ đầu
        lastKey = t
        times[head] = t
        head = (head + 1) % Self.capacity
        tier = BuddyTempo.tier(count: count(at: t), previous: tier)
    }

    /// Chọn từ gợi ý: cổ vũ ngắn (cũng tính là "đang gõ" để đánh thức).
    mutating func cheer(at t: Double) {
        if t - lastKey > BuddyTempo.window { resetRing() }
        lastKey = max(lastKey, t)
        cheerUntil = t + Self.cheer
    }

    /// Phản ứng theo từ: diễn `r.duration` giây. KHÔNG tính là phím (đang ngủ thì giật mình thức, diễn xong
    /// ngủ tiếp — mốc ngủ giữ nguyên); gọi lại / phản ứng khác ⇒ mới nhất thắng, diễn lại từ đầu.
    mutating func react(_ r: BuddyReaction, at t: Double) {
        reaction = r
        reactUntil = t + r.duration
        reactSerial &+= 1
    }

    /// Phím ⌫ (cả lặp khi giữ / xoá theo từ): đếm chuỗi; quá `panicAfter` ⇒ hoảng, kéo dài tới 0,8 s sau phím
    /// ⌫ cuối (không diễn lại mỗi phím). Chỉ một bộ đếm — không cấp phát.
    mutating func delete(at t: Double) {
        if t - lastDelete > Self.deleteGap { deleteRun = 0 }
        lastDelete = t
        deleteRun += 1
        tap(at: t)
        guard deleteRun > Self.panicAfter else { return }
        if !(reaction == .panic && t < reactUntil) { reactSerial &+= 1 }
        reaction = .panic
        reactUntil = t + BuddyReaction.panic.duration
    }

    func count(at t: Double) -> Int {
        var n = 0
        for x in times where x <= t && t - x <= BuddyTempo.window { n += 1 }
        return n
    }

    func phase(at t: Double) -> BuddyPhase {
        if t < reactUntil, let r = reaction { return .react(r) }
        guard lastKey > -Double.greatestFiniteMagnitude else { return .asleep(zzz: false) }
        if t < cheerUntil { return .cheering }
        let dt = t - lastKey
        if dt < Self.tail { return .dancing(tier) }
        if dt < Self.sleepAfter { return .idle }
        return .asleep(zzz: dt < Self.sleepAfter + Self.zzz)
    }

    /// Lúc trạng thái tự đổi tiếp (không có phím mới) — nil = đã ngủ hẳn, không cần hẹn giờ.
    func nextDeadline(after t: Double) -> Double? {
        var best: Double? = reactUntil > t ? reactUntil : nil
        guard lastKey > -Double.greatestFiniteMagnitude else { return best }
        for d in [cheerUntil, lastKey + Self.tail, lastKey + Self.sleepAfter, lastKey + Self.sleepAfter + Self.zzz]
            where d > t { best = min(best ?? d, d) }
        return best
    }

    private mutating func resetRing() {
        for i in 0..<Self.capacity { times[i] = -Double.greatestFiniteMagnitude }
        head = 0
        tier = 0
    }
}

// MARK: - Dáng nhảy (hàm thuần, đơn vị thiết kế + radian)

/// Các kênh chuyển động. dx/dy: dời cả người (đơn vị thiết kế); rot: nghiêng quanh chân; sx: xoay
/// vòng (lật ngang); còn lại: góc quay bộ phận quanh điểm xoay (dương = cùng chiều kim đồng hồ, y xuống
/// ⇒ tay TRÁI dương = giơ ra ngoài/lên, tay PHẢI âm = giơ ra ngoài/lên).
struct BuddyPose: Equatable {
    var dx = 0.0, dy = 0.0, rot = 0.0, sx = 1.0
    var head = 0.0, armL = 0.0, armR = 0.0, legL = 0.0, legR = 0.0, tail = 0.0

    static let rest = BuddyPose()

    /// Kênh cộng dồn (mọi kênh trừ sx) theo thứ tự cố định — dùng cho hoạt ảnh nối.
    static let additiveChannels: [WritableKeyPath<BuddyPose, Double>] =
        [\.dx, \.dy, \.rot, \.head, \.armL, \.armR, \.legL, \.legR, \.tail]
}

enum BuddyDance {
    /// Nhịp (giây / phách) theo bậc 0…3; một vòng = 4 phách.
    static let beats: [Double] = [0.62, 0.5, 0.42, 0.36]
    /// Độ sung theo bậc.
    static let energy: [Double] = [0.35, 0.6, 0.85, 1.0]
    static let beatsPerLoop = 4.0
    /// Thời gian nối mượt khi đổi bậc / trạng thái.
    static let blend = 0.25

    static func loopLength(_ tier: Int) -> Double { beats[clamp(tier)] * beatsPerLoop }
    /// Lắc nhẹ sau khi ngừng gõ (`.idle`): lắc hông độ sung bậc 0, một vòng chậm `idleLoop` giây.
    static let idleLoop = 4.0
    static func idle(_ s: Style, p: Double, character: BuddyCharacter = .off) -> BuddyPose {
        var o = pose(s, tier: 0, p: p, move: .hipSway)
        if character == .panda { o.head = 0.08 * sin(8 * Double.pi * p); o.armL = -0.3; o.armR = 0.3 }
        return o
    }
    static func clamp(_ tier: Int) -> Int { min(max(tier, 0), BuddyTempo.tiers - 1) }

    /// Kiểu nhảy riêng từng nhân vật (rad / đơn vị thiết kế), nhân với độ sung của bậc.
    struct Style: Equatable {
        var armL: Double, armR: Double, armAmp: Double, alternate: Bool
        var kick: Double, bounce: Double, step: Double
    }

    /// Dáng nhảy bậc `tier` tại pha `p` (0…1 của một vòng). Bậc cao nhất: xoay một vòng ở phách 4.
    enum Move: Int, CaseIterable { case bounce, hipSway, wave, clap, dab, skip, flossLite, spin, chicken }
    private static let calm: [Move] = [.bounce, .hipSway, .wave, .clap]
    private static let lively: [Move] = [.skip, .flossLite, .dab, .chicken]
    private static let energetic: [Move] = lively + [.spin]
    static func moves(_ tier: Int) -> [Move] {
        if clamp(tier) < 2 { return calm }
        return clamp(tier) == 2 ? lively : energetic
    }
    /// A seeded cyclic permutation; each selection lasts two loops, adjacent groups cannot repeat.
    static func move(_ character: BuddyCharacter, tier: Int, loopIndex: Int, seed: Int) -> Move {
        let pool: [Move] = (character == .koi || character == .eagle)
            ? (clamp(tier) < 2 ? [.wave, .chicken, .bounce, .clap] : [.chicken, .wave, .skip, .spin, .dab])
            : moves(tier)
        let n = pool.count
        let c: Int
        switch character { case .off: c = 0; case .girl: c = 1; case .boy: c = 2; case .cat: c = 3; case .chick: c = 4; case .shiba: c = 5; case .koi: c = 6; case .panda: c = 7; case .pig: c = 8; case .dragon: c = 9; case .eagle: c = 10 }
        let offset = abs(seed % 997) + c * 17
        let group = max(0, loopIndex) / 2 % n
        return pool[(offset + group * (n - 1)) % n]
    }

    static func pose(_ s: Style, tier: Int, p: Double, move: Move = .bounce, character: BuddyCharacter = .off) -> BuddyPose {
        let pp = p - floor(p)
        guard pp > 0 else { return .rest }
        let e = energy[clamp(tier)], two = 2 * Double.pi
        let wave = sin(two * pp), fast = sin(two * pp * 4)
        let beat = pp * 4, bf = beat - floor(beat)
        let hop = abs(sin(Double.pi * bf))
        let gate = min(1, pp / 0.08, (1 - pp) / 0.08)
        var o = BuddyPose()
        switch move {
        case .bounce:
            o = bounceBase(s, tier: tier, p: pp)
            o.sx = 1
        case .hipSway:
            o.dx = s.step * e * wave
            o.rot = 0.18 * e * wave
            o.armL = -0.45 * e; o.armR = 0.45 * e
            o.head = -0.10 * e * wave
        case .wave:
            o.dy = -s.bounce * 0.35 * e * hop
            o.armR = (-2.1 + 0.4 * fast) * e
            o.armL = 0.25 * e
            o.head = 0.12 * e * wave
        case .clap:
            let hit = Int(floor(beat)) % 2 == 1 ? hop : 0
            o.dy = -s.bounce * 0.25 * e * hop
            o.armL = (-0.2 - 0.85 * hit) * e
            o.armR = (0.2 + 0.85 * hit) * e
            o.head = 0.08 * e * hit
        case .dab:
            let hit = beat >= 3 ? hop : 0
            o.dy = -s.bounce * 0.3 * e * hop
            o.rot = -0.18 * e * hit
            o.head = 0.65 * e * hit
            o.armL = 2.5 * e * hit; o.armR = 0.9 * e * hit
        case .skip:
            o.dx = s.step * 0.6 * e * wave
            o.dy = -s.bounce * 1.5 * e * hop
            o.legL = 0.9 * e * max(0, wave)
            o.legR = -0.9 * e * max(0, -wave)
            o.armL = 0.6 * e * wave; o.armR = 0.6 * e * wave
            o.rot = 0.08 * e * wave
        case .flossLite:
            o.dx = -s.step * e * wave
            o.rot = -0.14 * e * wave
            o.armL = 0.85 * e * wave; o.armR = 0.85 * e * wave
            o.head = 0.12 * e * wave
        case .spin:
            o = bounceBase(s, tier: tier, p: pp)
        case .chicken:
            o.dy = -s.bounce * 0.65 * e * hop
            o.armL = (0.9 + 0.55 * fast) * e
            o.armR = -(0.9 + 0.55 * fast) * e
            o.head = 0.25 * e * hop
            o.tail = 0.3 * e * fast
        }
        if character == .boy && move == .spin && tier == 3 {
            if pp < 0.65 { o.head = 2 * Double.pi * pp / 0.65; o.rot = -0.22 * gate; o.dy -= s.bounce * 0.4 * gate }
            else { o.head = 0; o.rot = -0.55 * gate; o.armL = 1.9 * gate; o.armR = -1.9 * gate; o.sx = 1 }
        }
        for channel in BuddyPose.additiveChannels { o[keyPath: channel] *= gate }
        return o
    }

    static func bounce(_ s: Style, tier: Int, p: Double) -> BuddyPose { pose(s, tier: tier, p: p, move: .bounce) }
    static func hipSway(_ s: Style, tier: Int, p: Double) -> BuddyPose { pose(s, tier: tier, p: p, move: .hipSway) }
    static func wave(_ s: Style, tier: Int, p: Double) -> BuddyPose { pose(s, tier: tier, p: p, move: .wave) }
    static func clap(_ s: Style, tier: Int, p: Double) -> BuddyPose { pose(s, tier: tier, p: p, move: .clap) }
    static func dab(_ s: Style, tier: Int, p: Double) -> BuddyPose { pose(s, tier: tier, p: p, move: .dab) }
    static func skip(_ s: Style, tier: Int, p: Double) -> BuddyPose { pose(s, tier: tier, p: p, move: .skip) }
    static func flossLite(_ s: Style, tier: Int, p: Double) -> BuddyPose { pose(s, tier: tier, p: p, move: .flossLite) }
    static func spin(_ s: Style, tier: Int, p: Double) -> BuddyPose { pose(s, tier: tier, p: p, move: .spin) }
    static func chicken(_ s: Style, tier: Int, p: Double) -> BuddyPose { pose(s, tier: tier, p: p, move: .chicken) }
    private static func bounceBase(_ s: Style, tier: Int, p: Double) -> BuddyPose {
        let t = clamp(tier)
        let e = energy[t]
        let pp = p - p.rounded(.down)
        let beats = pp * beatsPerLoop
        let bi = Int(beats.rounded(.down))
        let bf = beats - Double(bi)
        let two = 2 * Double.pi
        let s2 = sin(two * pp * 2)
        var o = BuddyPose()
        o.dy = -s.bounce * e * abs(sin(Double.pi * bf))
        o.dx = s.step * e * sin(two * pp)
        o.rot = 0.1 * e * s2
        o.sx = (t == BuddyTempo.tiers - 1 && bi == 3) ? cos(two * bf) : 1
        o.head = 0.12 * e * s2
        o.armL = s.armL * e + s.armAmp * e * s2
        o.armR = -(s.armR * e + s.armAmp * e * sin(two * pp * 2 + (s.alternate ? Double.pi : 0)))
        o.legL = s.kick * e * max(0, s2)
        o.legR = -s.kick * e * max(0, -s2)
        o.tail = 0.35 * e * sin(two * pp * 4)
        return o
    }

    /// Cổ vũ: nhảy lên, hai tay giơ cao — f 0…1 (về dáng nghỉ ở 0 và 1).
    static func cheer(_ s: Style, f: Double, character: BuddyCharacter = .off) -> BuddyPose {
        let k = sin(Double.pi * min(max(f, 0), 1))
        var o = BuddyPose()
        o.dy = -s.bounce * 1.4 * k
        o.armL = 2.4 * k
        o.armR = -2.4 * k
        o.legL = 0.4 * k
        o.legR = -0.4 * k
        o.tail = 0.5 * k
        if character == .koi { o.rot = 0.18 * k; o.armL = 1.5 * k; o.armR = -1.5 * k; o.dy *= 1.5; o.tail = 0.8 * k }
        if character == .eagle { o.armL = 2.8 * k; o.armR = -2.8 * k }
        if character == .shiba { o.tail = 1.1 * sin(10 * Double.pi * f) * k }
        return o
    }

    /// Dáng phản ứng — f 0…1 của `r.duration` (về nghỉ ở 0 và 1; hoảng: lặp, không về nghỉ ở cuối).
    static func react(_ r: BuddyReaction, _ s: Style, f: Double, character: BuddyCharacter = .off) -> BuddyPose {
        let ff = min(max(f, 0), 1)
        let pi = Double.pi
        let a = r == .panic ? min(1, ff / 0.15 + 1) : min(1, ff / 0.15, (1 - ff) / 0.15)
        var o = BuddyPose()
        switch r {
        case .love, .luckyMoney, .gift, .candy, .mooncake:       // tay khép ôm trái tim trước ngực, nhún ba nhịp, nghiêng đầu
            o.dy = -s.bounce * 0.5 * a * abs(sin(3 * pi * ff))
            o.armL = -0.55 * a; o.armR = 0.55 * a
            o.head = 0.18 * a * sin(2 * pi * ff)
            o.tail = 0.4 * a * sin(4 * pi * ff)
        case .angry:      // dậm chân, nắm tay hai bên, lắc đầu, đuôi dựng
            let st = sin(6 * pi * ff)
            o.dy = -s.bounce * 0.25 * a * abs(st)
            o.legL = 0.35 * a * max(0, st); o.legR = -0.35 * a * max(0, -st)
            o.armL = 0.35 * a; o.armR = -0.35 * a
            o.head = 0.12 * a * sin(10 * pi * ff)
            o.tail = -0.4 * a
        case .laugh:      // ôm bụng cười, rung người
            o.dx = 2 * a * sin(16 * pi * ff)
            o.dy = -s.bounce * 0.2 * a * abs(sin(8 * pi * ff))
            o.armL = -0.7 * a; o.armR = 0.7 * a
            o.head = 0.1 * a * sin(8 * pi * ff)
            o.tail = 0.3 * a * sin(8 * pi * ff)
        case .greet:
            o.dy = -s.bounce * 0.45 * a * abs(sin(3 * pi * ff))
            o.armR = (-2.35 + 0.35 * sin(8 * pi * ff)) * a
            o.head = -0.08 * a * sin(4 * pi * ff)
        case .surprised:  // bật nhảy, giang tay
            o.dy = ff < 0.4 ? -s.bounce * 1.6 * sin(pi * ff / 0.4) : 0
            o.armL = 1.3 * a; o.armR = -1.3 * a
            o.legL = 0.3 * a; o.legR = -0.3 * a
            o.tail = -0.5 * a
        case .sad:        // chùng xuống, cúi đầu, tay khép, đuôi cụp
            o.dy = s.bounce * 0.6 * a
            o.head = 0.3 * a
            o.armL = -0.35 * a; o.armR = 0.35 * a
            o.tail = 0.6 * a
        case .panic:      // ôm đầu, rung lắc
            o.dx = 1.5 * a * sin(20 * pi * ff)
            o.armL = 2.6 * a; o.armR = -2.6 * a
            o.head = 0.08 * a * sin(20 * pi * ff)
            o.dy = -s.bounce * 0.15 * a * abs(sin(10 * pi * ff))
        }
        if character == .panda && r == .laugh { o.rot = 2 * pi * ff * a; o.dy -= s.bounce * 0.4 * a }
        if character == .pig && r == .laugh { o.rot = 2 * pi * ff * a; o.dx += 4 * sin(2 * pi * ff) * a }
        if character == .girl && r == .love { o.head = -0.25 * a; o.armR = -1.0 * a }
        if character == .shiba && r == .love { o.tail = sin(12 * pi * ff) * a }
        return o
    }

    /// Mắt khi phản ứng: true = mắt cười (cung), false = mắt tròn.
    static func happyEyes(_ r: BuddyReaction) -> Bool { r == .love || r == .laugh || r.isHoliday }
}

/// Selection is pure so previews, keyboard animations and fixtures use the same triggers.
enum BuddySignature: String {
    case kiss, breakdance, yarn, egg, bone, splash, bamboo, mud, snort, fire, laser

    static func cheer(_ c: BuddyCharacter, seed: Int) -> BuddySignature? {
        switch c {
        case .girl: return .kiss
        case .chick: return seed % 3 == 0 ? .egg : nil
        case .shiba: return .bone
        case .koi: return .splash
        case .dragon: return .fire
        case .eagle: return .laser
        default: return nil
        }
    }
    static func reaction(_ c: BuddyCharacter, _ r: BuddyReaction) -> BuddySignature? {
        switch (c, r) {
        case (.girl, .love): return .kiss
        case (.cat, .panic): return .yarn
        case (.panda, .laugh): return .bamboo
        case (.pig, .laugh): return .mud
        case (.pig, .angry): return .snort
        case (.dragon, .angry), (.dragon, .laugh): return .fire
        case (.eagle, .angry), (.eagle, .surprised): return .laser
        default: return nil
        }
    }
    static func idle(_ c: BuddyCharacter) -> BuddySignature? { c == .panda ? .bamboo : nil }
    static func dance(_ c: BuddyCharacter, tier: Int, group: Int, seed: Int) -> BuddySignature? {
        guard tier == 3 else { return nil }
        if c == .boy && (group + seed % 5) % 5 == 0 { return .breakdance }
        if c == .cat && (group + seed % 4) % 4 == 0 { return .yarn }
        return nil
    }
    private static let shibaWords: Set<String> = ["gioi qua", "good boy", "good dog", "ngoan"]
    static func word(_ c: BuddyCharacter, _ word: String) -> BuddySignature? {
        if BuddyWords.signatureEmoji(word, character: c) {
            switch c {
            case .shiba: return .bone
            case .koi: return .splash
            case .panda: return .bamboo
            case .pig: return .snort
            case .dragon: return .fire
            case .eagle: return .laser
            default: return nil
            }
        }
        guard c == .shiba else { return nil }
        let w = BuddyWords.fold(BuddyWords.clean(word))
        return shibaWords.contains(w) ? .bone : nil
    }
}

// MARK: - Phản ứng theo từ (ranh giới từ, tra O(1))

/// Phản ứng ngắn (~1–1,5 s) rồi về trạng thái cũ. Mới nhất thắng, không chồng. Thứ tự ƯU TIÊN khi một từ
/// khớp nhiều bảng = thứ tự case: tục (giận) > yêu thương > cười > ngạc nhiên > buồn ("wtf" = giận).
/// `panic` (xoá dồn) không theo từ — bộ đếm phím ⌫ trong BuddyBrain.
enum BuddyReaction: Int, CaseIterable {
    case angry, love, laugh, surprised, sad, greet, panic, luckyMoney, gift, candy, mooncake

    var isHoliday: Bool { self == .luckyMoney || self == .gift || self == .candy || self == .mooncake }

    /// Thời gian diễn (giây). Hoảng: kéo dài tới `duration` sau phím ⌫ cuối.
    var duration: Double {
        switch self {
        case .angry, .love: return 1.2
        case .laugh: return 1.3
        case .surprised, .greet: return 1.0
        case .sad: return 1.5
        case .panic: return 0.8
        case .luckyMoney, .gift, .candy, .mooncake: return 1.5
        }
    }
}

/// Bảng từ DÙNG CHUNG hai nền tảng (Android BuddyWords y hệt). Khớp bằng từ vừa chốt (và cụm "từ trước +
/// từ"), không phân biệt hoa/thường; từ không dấu khớp mọi dạng có dấu — trừ từ `strict` (bỏ dấu thành từ
/// khác hẳn: nhớ → "nho", chán → "chan", á → "a") chỉ khớp đúng dấu. Chữ lặp ("hahaha", "kkkkk", "woww")
/// khớp theo mẫu, không liệt kê.
enum BuddyWords {
    static let greet: [(String, Bool)] = [
        ("hi", false), ("hello", false), ("hey", false), ("hế lô", false), ("hê lô", false),
        ("helo", false), ("chào", true), ("xin chào", true), ("chào bạn", true), ("alo", false),
        ("yo", false), ("sup", false), ("good morning", false), ("chào buổi sáng", true),
    ]
    static let love: [(String, Bool)] = [
        ("yêu", false), ("iu", false), ("thương", false), ("nhớ", true), ("love", false), ("luv", false),
        ("lub", false), ("miss", false), ("cưng", true), ("thích", false), ("crush", false), ("tim", false),
        ("hun", false), ("thơm", true), ("honey", false), ("baby", false), ("anh yêu", false), ("em yêu", false),
        ("thương thương", false), ("nhớ nhớ", true), ("muah", false), ("chụt", true), ("xoxo", false),
        ("darling", false), ("lovely", false),
    ]
    static let laugh: [(String, Bool)] = [
        ("haha", false), ("hihi", false), ("hehe", false), ("hoho", false), ("kkk", false), ("kaka", false),
        ("keke", false), ("hjhj", false), ("lol", false), ("lmao", false), ("rofl", false), ("=))", false),
        (":))", false), ("😂", false), ("🤣", false), ("cười", true),
    ]
    static let surprised: [(String, Bool)] = [
        ("wow", false), ("ôi", true), ("trời ơi", false), ("omg", false), ("ủa", true),
        ("hả", true), ("what", false), ("wtf", false), ("ồ", true), ("á", true), ("woa", false), ("whoa", false),
    ]
    static let sad: [(String, Bool)] = [
        ("buồn", false), ("khóc", false), ("huhu", false), ("hic", false), ("hix", false), ("sad", false),
        (":(", false), ("chán", true), ("mệt mỏi", false), ("😢", false), ("😭", false),
    ]

    static func normalizeEmoji(_ text: String) -> String {
        String(text.unicodeScalars.filter { $0.value != 0xFE0F && !(0x1F3FB...0x1F3FF).contains($0.value) })
    }
    private static let emojiMap: [String: BuddyReaction] = {
        var out: [String: BuddyReaction] = [:]
        for (reaction, group) in [
            (BuddyReaction.greet, "👋 🙋 🙋‍♀️ 🙋‍♂️ 🤗"),
            (BuddyReaction.love, "❤️ ♥️ 💕 💖 💗 😍 🥰 😘 😻 💋"),
            (BuddyReaction.laugh, "😂 🤣 😆 😄 😁 😹 😅 😝 😜"),
            (BuddyReaction.surprised, "😮 😲 😱 🤯 😳 ‼️ ⁉️"),
            (BuddyReaction.sad, "😢 😭 😞 😔 🥺 💔 😿"),
            (BuddyReaction.angry, "😡 🤬 😠 👿 💢"),
            (BuddyReaction.luckyMoney, "🧧 🧨"),
            (BuddyReaction.gift, "🎁 🎄 🎅 🤶 ⛄"),
            (BuddyReaction.candy, "🎃 🍬 🍭 👻 🦇"),
            (BuddyReaction.mooncake, "🥮 🏮 🌕"),
        ] { for symbol in group.split(separator: " ") { out[normalizeEmoji(String(symbol))] = reaction } }
        return out
    }()
    static func emoji(_ text: String) -> BuddyReaction? {
        let normalized = normalizeEmoji(text)
        if let direct = emojiMap[normalized] { return direct }
        for c in normalized where !c.isLetter && !c.isNumber {
            if let found = emojiMap[String(c)] { return found }
        }
        return nil
    }
    private static let signatureSymbols: [BuddyCharacter: Set<String>] = [
        .shiba: ["🐶", "🐕", "🦴"], .panda: ["🐼", "🎋"], .pig: ["🐷", "🐖"],
        .koi: ["🐟", "🎏"], .dragon: ["🐉", "🐲", "🔥"], .eagle: ["🦅"],
    ]
    static func signatureEmoji(_ text: String, character: BuddyCharacter) -> Bool {
        guard let values = signatureSymbols[character],
              text.unicodeScalars.contains(where: { $0.value >= 0x203C }) else { return false }
        let normalized = normalizeEmoji(text)
        if values.contains(normalized) { return true }
        return normalized.contains { values.contains(String($0)) }
    }

    private struct Table {
        let exact: Set<String>, folded: Set<String>, squeezed: Set<String>
        init(_ e: [(String, Bool)]) {
            exact = Set(e.map(\.0))
            let loose = e.filter { !$0.1 }.map { BuddyWords.fold($0.0) }
            folded = Set(loose)
            squeezed = Set(loose.map(BuddyWords.squeeze).filter { $0.count >= 3 })
        }
        func has(_ k: String) -> Bool {
            guard !k.isEmpty else { return false }
            if exact.contains(k) { return true }
            let f = BuddyWords.fold(k)
            if folded.contains(f) { return true }
            let q = BuddyWords.squeeze(f)
            return q.count >= 3 && squeezed.contains(q)
        }
    }
    private static let tables: [(BuddyReaction, Table)] = [
        (.love, Table(love)), (.laugh, Table(laugh)), (.surprised, Table(surprised)), (.sad, Table(sad)),
        (.greet, Table(greet)),
    ]

    /// Chữ thường, bỏ dấu (đ → d).
    static func fold(_ s: String) -> String { EmojiWords.fold(s) }

    /// Gộp chữ lặp liên tiếp: "woooow" → "wow", "omggg" → "omg".
    static func squeeze(_ s: String) -> String {
        var out = ""
        var last: Character?
        for c in s where c != last { out.append(c); last = c }
        return out
    }

    /// Bỏ dấu câu bao quanh — giữ nguyên chuỗi toàn ký hiệu (":))", "=))", emoji).
    static func clean(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let letters = t.trimmingCharacters(in: CharacterSet.letters.inverted)
        return letters.isEmpty ? t : letters
    }

    /// Cười theo mẫu chữ lặp: k…k (≥ 3), ha/he/hi/ho/hj/ka/ke lặp ≥ 2 lần (cho dư một chữ cuối), =)))…
    static func isLaughPattern(_ f: String) -> Bool {
        let c = Array(f)
        if c.count >= 3, c.allSatisfy({ $0 == "k" }) { return true }
        if c.count >= 3, (f.hasPrefix("=)") || f.hasPrefix(":)")), c.dropFirst(2).allSatisfy({ $0 == ")" }) { return true }
        let units: Set<String> = ["ha", "he", "hi", "ho", "hj", "ka", "ke"]
        guard c.count >= 4 else { return false }
        var i = 0, n = 0
        while i + 1 < c.count, units.contains(String(c[i...(i + 1)])) { i += 2; n += 1 }
        return n >= 2 && c.count - i <= 1
    }

    static func isGreetPattern(_ f: String) -> Bool {
        if f.hasPrefix("hi"), f.count >= 3, f.dropFirst(2).allSatisfy({ $0 == "i" }) { return true }
        if f.hasPrefix("hey"), f.count >= 4, f.dropFirst(3).allSatisfy({ $0 == "y" }) { return true }
        return false
    }

    /// Buồn theo mẫu: hu lặp ≥ 2 ("huhuhu"), hic/hix lặp, ":(((".
    static func isSadPattern(_ f: String) -> Bool {
        let c = Array(f)
        if c.count >= 2, f.hasPrefix(":("), c.dropFirst(2).allSatisfy({ $0 == "(" }) { return true }
        for u in ["hu", "hic", "hix"] {
            let uc = Array(u)
            guard c.count >= uc.count * 2, c.count % uc.count == 0 else { continue }
            if stride(from: 0, to: c.count, by: uc.count).allSatisfy({ Array(c[$0..<($0 + uc.count)]) == uc }) { return true }
        }
        return false
    }

    /// Phản ứng cho từ vừa chốt `word` (từ trước `prev`, `prev2`) — nil = không. Tục / cặp / bộ ba tục
    /// (CÙNG bảng của bộ lọc gợi ý) ⇒ giận, KHÔNG phụ thuộc công tắc "Lọc từ nhạy cảm" (công tắc chỉ cho gợi ý).
    private static let holidays: [(BuddyReaction, BuddySeason, Table, Table)] = [
        (.luckyMoney, .tet, Table([("lì xì", false), ("mừng tuổi", false), ("tết", false), ("năm mới", false), ("chúc mừng năm mới", false), ("vạn sự như ý", false), ("happy new year", false)]), Table([("an khang", false), ("phát tài", false)])),
        (.gift, .christmas, Table([("giáng sinh", false), ("noel", false), ("merry christmas", false), ("xmas", false), ("ông già noel", false)]), Table([("quà", true)])),
        (.candy, .halloween, Table([("halloween", false), ("trick or treat", false)]), Table([("kẹo", true), ("bí ngô", false)])),
        (.mooncake, .midAutumn, Table([("trung thu", false), ("bánh trung thu", false), ("rước đèn", false), ("đèn ông sao", false), ("chị hằng", false)]), Table([("cuội", true)])),
    ]

    /// Pure gating: names work year-round; ambiguous everyday words require the matching season.
    /// prev3 handles four-token wishes ("vạn sự như ý", "chúc mừng năm mới").
    static func holiday(word: String, prev: String?, prev2: String? = nil, prev3: String? = nil,
                        season: BuddySeason? = nil) -> BuddyReaction? {
        let w = clean(word)
        guard !w.isEmpty, w.count <= 24 else { return nil }
        var candidates = [w]
        var phrase = w
        for previous in [prev, prev2, prev3] {
            guard let previous, !clean(previous).isEmpty else { break }
            phrase = clean(previous) + " " + phrase
            candidates.append(phrase)
        }
        for (r, active, names, generic) in holidays {
            if candidates.contains(where: { names.has($0) || (season == active && generic.has($0)) }) { return r }
        }
        return nil
    }

    static func reaction(word: String, prev: String?, prev2: String? = nil, prev3: String? = nil, season: BuddySeason? = nil) -> BuddyReaction? {
        if let direct = emoji(word) { return direct }
        let w = clean(word)
        guard !w.isEmpty, w.count <= 24 else { return nil }
        let p = prev.map(clean).flatMap { $0.isEmpty ? nil : $0 }
        let p2 = prev2.map(clean).flatMap { $0.isEmpty ? nil : $0 }
        if SensitiveWords.set.contains(w) || SensitiveWords.isPair(p, w) || SensitiveWords.isTriple(p2, p, w) {
            return .angry
        }
        if let r = holiday(word: w, prev: p, prev2: p2, prev3: prev3, season: season) { return r }
        let f = fold(w)
        for (r, t) in tables {
            if let p, let p2, t.has(p2 + " " + p + " " + w) { return r }
            if let p, t.has(p + " " + w) { return r }
            if t.has(w) { return r }
            if r == .laugh, isLaughPattern(f) { return r }
            if r == .sad, isSadPattern(f) { return r }
            if r == .greet, isGreetPattern(f) { return r }
        }
        return nil
    }

    /// Ký hiệu chửi thề kiểu truyện tranh (#$%&*!) — chỉ các ký hiệu này, thứ tự theo `seed` (tất định).
    static let grawlixSymbols: [Character] = ["#", "$", "%", "&", "*", "!", "@"]
    static func grawlix(seed: Int, count: Int = 4) -> String {
        var r = FxRandom(seed: seed)
        var out = ""
        var last: Character?
        while out.count < count {
            let c = grawlixSymbols[min(Int(r.next() * Double(grawlixSymbols.count)), grawlixSymbols.count - 1)]
            if c == last { continue }
            out.append(c); last = c
        }
        return out
    }
}

/// Hiệu ứng phụ của phản ứng — hạt nhỏ bay (pool ≤ `maxParticles`) + một "biển" cố định (bong bóng chửi,
/// "!", mây mưa). Toạ độ pt trong ô nhân vật (gốc trên trái): luôn TRỌN trong ô — ô cắt theo strip nên
/// không bao giờ ra vùng phím / chữ gợi ý. Hàm thuần (Android y hệt).
enum BuddyFX {
    static let maxParticles = 8
    static let particleSize = 7.0
    static let particleDuration = 1.0
    static let heartColor: UInt32 = 0xFF5C8A
    static let tearColor: UInt32 = 0x6EC6FF
    static let rainColor: UInt32 = 0x7FA7D9
    static let cloudColor: UInt32 = 0xA9B1BD
    static let angryRed: UInt32 = 0xFF3B30
    /// Chữ bay khi xoá dồn.
    static let panicGlyphs: [String] = ["a", "b", "c", "x", "?"]

    struct Particle: Equatable {
        var x0: Double, y0: Double, x1: Double, y1: Double, delay: Double
    }

    /// Số hạt mỗi phản ứng (≤ maxParticles).
    static func count(_ r: BuddyReaction) -> Int {
        switch r {
        case .love: return 5
        case .laugh: return 4
        case .sad: return 3
        case .panic: return 3
        case .angry, .greet, .surprised, .luckyMoney, .gift, .candy, .mooncake: return 0
        }
    }

    /// Quỹ đạo hạt thứ i của phản ứng `r` trong ô `w`×`h`.
    static func particle(_ r: BuddyReaction, _ i: Int, width w: Double, height h: Double) -> Particle {
        let n = count(r)
        let rad = particleSize / 2
        let t = n > 1 ? Double(i) / Double(n - 1) : 0.5            // 0…1 trái → phải
        var p: Particle
        switch r {
        case .love:      // tim bay lên, toả ra
            p = Particle(x0: w / 2 + (t - 0.5) * w * 0.3, y0: h * 0.55,
                         x1: rad + (w - 2 * rad) * (0.1 + 0.8 * t), y1: rad + (h * 0.35) * Double((i * 7) % 3) / 2,
                         delay: Double(i) * 0.08)
        case .laugh:     // nước mắt văng hai bên đầu, rơi nhẹ
            let side = i % 2 == 0 ? -1.0 : 1.0
            p = Particle(x0: w / 2 + side * w * 0.12, y0: h * 0.25,
                         x1: w / 2 + side * w * (0.36 + 0.06 * Double(i / 2)), y1: h * (0.35 + 0.12 * Double(i / 2)),
                         delay: Double(i) * 0.15)
        case .sad:       // giọt mưa rơi từ mây trên đầu
            p = Particle(x0: w * (0.3 + 0.2 * Double(i)), y0: h * 0.18, x1: w * (0.3 + 0.2 * Double(i)), y1: h * 0.5,
                         delay: Double(i) * 0.3)
        case .panic:     // chữ bay khỏi người, lên + ra hai bên
            p = Particle(x0: w / 2, y0: h * 0.6, x1: rad + (w - 2 * rad) * t, y1: rad + h * 0.1 * Double(i % 2),
                         delay: Double(i) * 0.1)
        case .angry, .greet, .surprised, .luckyMoney, .gift, .candy, .mooncake:
            p = Particle(x0: w / 2, y0: h / 2, x1: w / 2, y1: h / 2, delay: 0)
        }
        func cx(_ x: Double) -> Double { min(max(x, rad), w - rad) }
        func cy(_ y: Double) -> Double { min(max(y, rad), h - rad) }
        return Particle(x0: cx(p.x0), y0: cy(p.y0), x1: cx(p.x1), y1: cy(p.y1), delay: p.delay)
    }

    /// Khung "biển" cố định (pt): bong bóng chửi (giận), "!" (ngạc nhiên), mây (buồn); nil = không có.
    static func badge(_ r: BuddyReaction, width w: Double, height h: Double) -> BuddyRect? {
        switch r {
        case .angry: return BuddyRect(x: 0, y: 0, w: w, h: min(13, h * 0.32))
        case .surprised: return BuddyRect(x: w - 9, y: 1, w: 8, h: min(14, h * 0.36))
        case .sad: return BuddyRect(x: w * 0.18, y: 0, w: w * 0.64, h: min(10, h * 0.24))
        default: return nil
        }
    }

    /// Đường trái tim tâm (cx, cy), nửa bề ngang ~k (đơn vị bất kỳ).
    static func heartPath(cx: Double, cy: Double, k: Double) -> String {
        func f(_ v: Double) -> String { String(format: "%.2f", v) }
        return "M\(f(cx)) \(f(cy + k * 0.9)) Q\(f(cx - k * 1.4)) \(f(cy + k * 0.1)) \(f(cx - k * 0.8)) \(f(cy - k * 0.6)) "
            + "Q\(f(cx - k * 0.3)) \(f(cy - k * 1.1)) \(f(cx)) \(f(cy - k * 0.4)) "
            + "Q\(f(cx + k * 0.3)) \(f(cy - k * 1.1)) \(f(cx + k * 0.8)) \(f(cy - k * 0.6)) "
            + "Q\(f(cx + k * 1.4)) \(f(cy + k * 0.1)) \(f(cx)) \(f(cy + k * 0.9)) Z"
    }

    /// Giọt nước (nước mắt / mưa) tâm (cx, cy) cỡ k.
    static func dropPath(cx: Double, cy: Double, k: Double) -> String {
        func f(_ v: Double) -> String { String(format: "%.2f", v) }
        return "M\(f(cx)) \(f(cy - k)) Q\(f(cx + k * 0.9)) \(f(cy + k * 0.2)) \(f(cx)) \(f(cy + k * 0.8)) "
            + "Q\(f(cx - k * 0.9)) \(f(cy + k * 0.2)) \(f(cx)) \(f(cy - k)) Z"
    }

    /// Mây trong khung (x, y, w, h).
    static func cloudPath(_ b: BuddyRect) -> String {
        func f(_ v: Double) -> String { String(format: "%.2f", v) }
        let x = b.x, y = b.y, w = b.w, h = b.h
        return "M\(f(x + w * 0.1)) \(f(y + h)) Q\(f(x - w * 0.05)) \(f(y + h * 0.5)) \(f(x + w * 0.2)) \(f(y + h * 0.45)) "
            + "Q\(f(x + w * 0.3)) \(f(y)) \(f(x + w * 0.55)) \(f(y + h * 0.25)) "
            + "Q\(f(x + w * 0.85)) \(f(y)) \(f(x + w * 0.85)) \(f(y + h * 0.5)) "
            + "Q\(f(x + w * 1.05)) \(f(y + h * 0.6)) \(f(x + w * 0.9)) \(f(y + h)) Z"
    }
}

// MARK: - Hình vẽ (dữ liệu)

/// Bộ phận — thứ tự vẽ (sau đè trước) = thứ tự case.
enum BuddyPart: Int, CaseIterable {
    case tail, legL, legR, body, armL, armR, head
    /// Dáng ngủ: nhóm tĩnh riêng.
    case sleep
}

/// Một mảnh hình (một màu tô / một nét).
struct BuddyPiece {
    enum Shape {
        /// Đường SVG rút gọn: M L H V Q Z (hoa = tuyệt đối, thường = tương đối).
        case path(String)
        case circle(Double, Double, Double)
        case ellipse(Double, Double, Double, Double)
        case rrect(Double, Double, Double, Double, Double)
    }
    enum Stroke: Equatable {
        case none
        /// Viền nhân vật: nâu đậm ở nền sáng, kem ở nền tối (luôn tách khỏi nền).
        case outline
        /// Nét mặt (mắt, miệng): luôn đậm.
        case ink
        case color(UInt32)
    }
    /// Mắt mở khi đứng / mắt cười khi nhảy; còn lại luôn hiện.
    enum Show { case always, rest, dance }

    let part: BuddyPart
    let shape: Shape
    let fill: UInt32?
    let alpha: Double
    let stroke: Stroke
    let width: Double
    let show: Show
    /// Xoay mảnh (độ, quanh cx, cy) — chỉ dáng ngủ (đầu nghiêng).
    let turn: (deg: Double, cx: Double, cy: Double)?

    init(_ part: BuddyPart, _ shape: Shape, fill: UInt32? = nil, alpha: Double = 1, stroke: Stroke = .outline,
         width: Double = BuddyRig.outlineWidth, show: Show = .always, turn: (Double, Double, Double)? = nil) {
        self.part = part; self.shape = shape; self.fill = fill; self.alpha = alpha
        self.stroke = stroke; self.width = width; self.show = show
        self.turn = turn.map { (deg: $0.0, cx: $0.1, cy: $0.2) }
    }
}

/// Cách hiển thị: thanh gợi ý (nhân vật dáng cao ⇒ cắt ngang eo cho đầu đủ lớn) hay cả người (xem trước /
/// "sân khấu" cao hơn nếu Phil chọn). Đổi một chỗ: `BuddyRig.viewport(_:)`.
enum BuddyFraming { case bar, full }

struct BuddyRect: Equatable {
    var x: Double, y: Double, w: Double, h: Double
    var maxY: Double { y + h }
}

/// Bộ khung một nhân vật — toàn bộ là dữ liệu (đơn vị thiết kế, y xuống).
struct BuddyRig {
    static let outlineWidth = 6.0

    let pieces: [BuddyPiece]
    let pivots: [BuddyPart: (x: Double, y: Double)]
    /// Khung cả người.
    let full: BuddyRect
    /// Đáy khung khi hiện ở thanh gợi ý (nil = cả người — nhân vật chibi).
    let barBottom: Double?
    /// Điểm chân (tâm nghiêng / xoay vòng).
    let feet: (x: Double, y: Double)
    /// Đáy hình dáng ngủ (toạ độ nhóm ngủ) — nhóm ngủ được dời cho đáy chạm đáy khung.
    let sleepBottom: Double
    /// "z z Z": (x, y góc trên trái, cỡ) trong toạ độ nhóm ngủ.
    let zzz: [(x: Double, y: Double, size: Double)]
    let style: BuddyDance.Style
    /// Trái tim ôm trước ngực khi thả tim (tâm, nửa bề ngang).
    var heart: (x: Double, y: Double, size: Double) = (0, 46, 11)
    /// Giận: vùng mặt đỏ bừng (elip) + lông mày cau (đường).
    var face: (x: Double, y: Double, rx: Double, ry: Double) = (0, -6, 24, 18)
    var brows = "M-16 -25 L-6 -21 M16 -25 L6 -21"
    /// Mũ (giữa đáy mũ trên đỉnh đầu, bề ngang) — đứng / ngủ; cổ (nơ); tay phải lúc nghỉ (lồng đèn).
    var hat: (x: Double, y: Double, size: Double) = (0, -42, 34)
    var sleepHat: (x: Double, y: Double, size: Double) = (-34, -2, 26)
    var neck: (x: Double, y: Double) = (0, 18)
    var hand: (x: Double, y: Double) = (23, 64)

    var hasTail: Bool { pieces.contains { $0.part == .tail } }

    func viewport(_ f: BuddyFraming) -> BuddyRect {
        guard f == .bar, let b = barBottom else { return full }
        return BuddyRect(x: full.x, y: full.y, w: full.w, h: b - full.y)
    }

    /// Dời nhóm ngủ (đơn vị thiết kế) để đáy hình ngủ chạm đáy khung đang dùng.
    func sleepOffset(_ f: BuddyFraming) -> Double { viewport(f).maxY - 4 - sleepBottom }

    static let zColor: UInt32 = 0x8AA6E8
    /// Màu viền nền sáng / nền tối.
    static let outlineLight: UInt32 = 0x3A2A2A
    static let outlineDark: UInt32 = 0x4A3A38
    static let ink: UInt32 = 0x3A2A2A

    /// Nét chữ "z" cỡ `k` tại (x, y).
    static func zPath(x: Double, y: Double, size k: Double) -> String {
        "M\(x) \(y) h\(k) l\(-k) \(k) h\(k)"
    }

    static func rig(_ c: BuddyCharacter) -> BuddyRig? {
        switch c {
        case .off: return nil
        case .girl: return girl
        case .boy: return boy
        case .cat: return cat
        case .chick: return chick
        case .shiba: return shiba
        case .koi: return koi
        case .panda: return panda
        case .pig: return pig
        case .dragon: return dragon
        case .eagle: return eagle
        }
    }

    /// Tổng mọi số trong bảng hình (toạ độ, cỡ, màu, điểm xoay) — Android tính y hệt (test chung):
    /// sửa hình một bên mà quên bên kia thì test đỏ.
    static func checksum(_ c: BuddyCharacter) -> Double {
        guard let r = rig(c) else { return 0 }
        var s = 0.0
        func nums(_ str: String) -> [Double] { BuddySVG.numbers(str) }
        for p in r.pieces {
            s += Double(p.part.rawValue) + p.width + p.alpha + Double(p.fill ?? 0) / 65536
            switch p.stroke {
            case .none: s += 1
            case .outline: s += 2
            case .ink: s += 3
            case .color(let v): s += 4 + Double(v) / 65536
            }
            switch p.show { case .always: break; case .rest: s += 5; case .dance: s += 7 }
            if let t = p.turn { s += t.deg + t.cx + t.cy }
            switch p.shape {
            case .path(let d): s += nums(d).reduce(0, +)
            case .circle(let a, let b, let r): s += a + b + r
            case .ellipse(let a, let b, let rx, let ry): s += a + b + rx + ry
            case .rrect(let x, let y, let w, let h, let rr): s += x + y + w + h + rr
            }
        }
        for part in BuddyPart.allCases { if let v = r.pivots[part] { s += v.x * 3 + v.y * 5 } }
        s += r.full.x + r.full.y + r.full.w + r.full.h + (r.barBottom ?? 0) + r.feet.x + r.feet.y + r.sleepBottom
        for z in r.zzz { s += z.x + z.y + z.size }
        s += r.heart.x + r.heart.y * 2 + r.heart.size * 3
        s += r.face.x + r.face.y + r.face.rx + r.face.ry + nums(r.brows).reduce(0, +)
        s += r.hat.x + r.hat.y + r.hat.size + r.sleepHat.x + r.sleepHat.y + r.sleepHat.size
        s += r.neck.x + r.neck.y + r.hand.x * 2 + r.hand.y * 2
        return s
    }
}

/// Viền sáng / tối bao quanh CẢ dáng nhân vật (vẽ dưới mọi bộ phận) + màu viền nét — chọn theo nền thanh gợi ý,
/// MỘT lần lúc đổi theme. Nền tối ⇒ quầng sáng; nền sáng ⇒ quầng đậm. Chọn theo tỉ lệ tương phản WCAG (bên nào
/// cao hơn) nên mọi nền đều ≥ 4,5:1 về lý thuyết; test giữ ≥ 3:1 cho mọi theme dựng sẵn. Android BuddyHalo y hệt.
enum BuddyHalo {
    static let light: UInt32 = 0xF4F4F4
    static let dark: UInt32 = 0x3A2A2A
    /// Bề rộng quầng (pt / dp) ngoài nét viền.
    static let width = 1.75
    /// Nền thanh khi theme để trong suốt (Hệ thống / Kính): xám bàn phím iOS sáng / tối.
    static let systemLight: UInt32 = 0xD1D3D9
    static let systemDark: UInt32 = 0x2C2C2E

    static func luminance(_ c: UInt32) -> Double {
        func ch(_ v: UInt32) -> Double {
            let x = Double(v & 0xFF) / 255
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * ch(c >> 16) + 0.7152 * ch(c >> 8) + 0.0722 * ch(c)
    }
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    struct Colors: Equatable {
        var halo: UInt32, outline: UInt32, darkBar: Bool
    }

    /// Màu quầng + viền nét cho nền thanh `bar` (RGB đục).
    static func colors(bar: UInt32) -> Colors {
        let darkBar = contrast(light, bar) >= contrast(dark, bar)
        return Colors(halo: darkBar ? light : dark, outline: darkBar ? BuddyRig.outlineDark : BuddyRig.outlineLight,
                      darkBar: darkBar)
    }
}

/// Nghệ thuật của nhân vật: khung vector (mặc định) hoặc bộ khung hình vẽ sẵn (hoạ sĩ vẽ — chưa có).
enum BuddyArt {
    case rig(BuddyRig)
    case sprites(BuddySprites)
}

/// Bộ khung hình (tên ảnh) — mỗi bậc nhảy một chuỗi khung chạy hết trong một vòng (`BuddyDance.loopLength`).
struct BuddySprites {
    // Every companion uses the same 4 × 2 atlas and eight-pose state mapping.
    static func columns(_ c: BuddyCharacter) -> Int { 4 }
    static func rows(_ c: BuddyCharacter) -> Int { 2 }
    static func rest(_ c: BuddyCharacter) -> Int { 0 }
    static func sleep(_ c: BuddyCharacter) -> Int { 7 }
    /// Khung lật gương = ô + `mirror` (nhấc chân trái ↔ chân phải): gấp đôi số dáng, không thêm ảnh.
    static let mirror = 100
    @inline(__always) static func cell(_ frame: Int) -> Int { frame % mirror }
    @inline(__always) static func isMirrored(_ frame: Int) -> Bool { frame >= mirror }
    private static let gentle = [0, 1, 0, 1 + mirror]
    /// Lắc hông: qua lại giữa khung 5 và 6 (ảnh thứ 6 / 7) vài lần.
    private static let sway = [0, 1, 0, 1 + mirror, 5, 6, 5, 6]
    /// Thứ tự ảnh khi xoay trọn một vòng (từ chính diện, quay sang trái). Mèo / gà / chàng trai: 2…6 theo
    /// thứ tự; cô gái vẽ khác thứ tự (6 ¾ trước, 3 nghiêng, 4 lưng, 2 ¾ lưng, 5 nghiêng bên kia).
    static func turnOrder(_ c: BuddyCharacter) -> [Int] { c == .girl ? [6, 3, 4, 2, 5] : [2, 3, 4, 5, 6] }
    /// Bậc cao: nhảy, xoay trọn vòng trái, rồi trọn vòng phải (bản lật gương), rồi lắc hông.
    private static func turn(_ c: BuddyCharacter) -> [Int] {
        let o = turnOrder(c)
        return [0, 1, 0, 1 + mirror] + o + [0] + o.map { $0 + mirror } + [0, 5, 6, 5, 6, 0]
    }
    static let cheer = [0, 1, 6, 1 + mirror, 0]
    static let react = [0, 1, 6, 6 + mirror]
    /// Lắc nhẹ sau khi ngừng gõ (`.idle`): qua lại khung 5 ↔ 6, chậm.
    static let idle = [5, 6]
    static let idleDuration = 1.6
    static func dance(_ c: BuddyCharacter, _ tier: Int) -> [Int] { tier >= 2 ? turn(c) : tier == 1 ? sway : gentle }
    /// Vòng dài theo số khung (giữ nhịp mỗi khung như bộ cũ: 10 khung ở bậc cao, 4 khung ở bậc thấp).
    static func duration(_ c: BuddyCharacter, _ tier: Int) -> Double {
        BuddyDance.loopLength(tier) * Double(dance(c, tier).count) / (tier >= 2 ? 10 : 4)
    }

    var sleep: String
    var rest: String
    var dance: [[String]]
    var cheer: [String]

    /// Khung thứ mấy tại pha `p` (0…1) của chuỗi `count` khung — hàm thuần (Android y hệt).
    static func frameIndex(p: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let pp = p - p.rounded(.down)
        return min(Int(pp * Double(count)), count - 1)
    }
}

// MARK: - Bảng hình 4 nhân vật

extension BuddyRig {
    private static func P(_ part: BuddyPart, _ d: String, fill: UInt32? = nil, alpha: Double = 1,
                          stroke: BuddyPiece.Stroke = .outline, width: Double = outlineWidth,
                          show: BuddyPiece.Show = .always, turn: (Double, Double, Double)? = nil) -> BuddyPiece {
        BuddyPiece(part, .path(d), fill: fill, alpha: alpha, stroke: stroke, width: width, show: show, turn: turn)
    }
    private static func C(_ part: BuddyPart, _ cx: Double, _ cy: Double, _ r: Double, fill: UInt32,
                          stroke: BuddyPiece.Stroke = .outline, alpha: Double = 1,
                          show: BuddyPiece.Show = .always, turn: (Double, Double, Double)? = nil) -> BuddyPiece {
        BuddyPiece(part, .circle(cx, cy, r), fill: fill, alpha: alpha, stroke: stroke, show: show, turn: turn)
    }
    private static func E(_ part: BuddyPart, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, fill: UInt32,
                          stroke: BuddyPiece.Stroke = .outline, alpha: Double = 1,
                          turn: (Double, Double, Double)? = nil) -> BuddyPiece {
        BuddyPiece(part, .ellipse(cx, cy, rx, ry), fill: fill, alpha: alpha, stroke: stroke, turn: turn)
    }
    private static func R(_ part: BuddyPart, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double,
                          fill: UInt32, turn: (Double, Double, Double)? = nil) -> BuddyPiece {
        BuddyPiece(part, .rrect(x, y, w, h, r), fill: fill, turn: turn)
    }
    /// Nét đơn (không tô).
    private static func L(_ part: BuddyPart, _ d: String, _ stroke: BuddyPiece.Stroke, _ w: Double,
                          show: BuddyPiece.Show = .always, turn: (Double, Double, Double)? = nil) -> BuddyPiece {
        BuddyPiece(part, .path(d), fill: nil, stroke: stroke, width: w, show: show, turn: turn)
    }
    /// Chi có viền: nét viền dày + nét màu mảnh hơn đè lên.
    private static func limb(_ part: BuddyPart, _ d: String, _ color: UInt32, _ w: Double) -> [BuddyPiece] {
        [L(part, d, .outline, w + 5), L(part, d, .color(color), w)]
    }

    // Pink-haired cat girl: hoodie, pleated skirt and soft flowing locks.
    static let girl: BuddyRig = {
        let p: [BuddyPiece] = [
            P(.tail, "M14 63 Q44 71 49 49 Q53 34 44 29 Q38 27 37 33 Q47 42 39 53 Q31 61 15 56 Z", fill: 0xE996B2, stroke: .outline, width: 3.2),
            P(.tail, "M43 34 Q48 43 43 50", stroke: .color(0xFFD4E2), width: 3),
            P(.legL, "M -2 72 Q -8 68 -14 73 L -16 102 L -15 137 Q -10 143 -5 137 L -4 105 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.legL, "M -4 109 Q -10 112 -16 109 L -15 137 Q -10 143 -5 137 Z", fill: 0xFFF7F4, stroke: .outline, width: 3.2),
            P(.legL, "M -5 134 Q -10 131 -16 135 L -19 140 Q -21 146 -13 146 L -4 145 Q 0 142 -5 134 Z", fill: 0xFF6F91, stroke: .outline, width: 3.2),
            P(.legL, "M -6 139 L -14 139", stroke: .color(0xFFF7F4), width: 2.5),
            P(.legR, "M 2 72 Q 8 68 14 73 L 16 102 L 15 137 Q 10 143 5 137 L 4 105 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.legR, "M 4 109 Q 10 112 16 109 L 15 137 Q 10 143 5 137 Z", fill: 0xFFF7F4, stroke: .outline, width: 3.2),
            P(.legR, "M 5 134 Q 10 131 16 135 L 19 140 Q 21 146 13 146 L 4 145 Q 0 142 5 134 Z", fill: 0xFF6F91, stroke: .outline, width: 3.2),
            P(.legR, "M 6 139 L 14 139", stroke: .color(0xFFF7F4), width: 2.5),
            P(.body, "M-17 59 L-26 79 Q0 88 26 79 L17 59 Z", fill: 0xFFF7F4, stroke: .outline, width: 3.2),
            P(.body, "M-13 68 L-16 79 M-4 70 L-5 81 M5 70 L6 81 M14 68 L17 79", stroke: .color(0xD9CADA), width: 1.8),
            P(.body, "M-16 22 Q0 14 16 22 Q23 41 22 62 Q25 69 18 72 Q0 78 -22 70 Q-21 44 -16 22 Z", fill: 0xFFB3C7, stroke: .outline, width: 3.2),
            P(.body, "M14 25 Q18 46 13 60 Q1 66 -20 62 L-22 70 Q0 78 18 72 Q25 69 22 62 Q23 42 14 25 Z", fill: 0xDF8EAB, stroke: .none, width: 0),
            P(.body, "M-10 26 Q0 35 10 26 M-8 34 L-9 43 M8 34 L9 43 M-9 55 Q0 61 9 55", stroke: .color(0xFFF0F4), width: 2),
            P(.armL, "M -10 25 Q -18 22 -22 32 Q -28 45 -29 57 Q -27 65 -19 62 Q -15 50 -9 36 Z", fill: 0xFFB3C7, stroke: .outline, width: 3.2),
            P(.armL, "M -21 37 Q -29 49 -29 57 Q -27 65 -19 62 L -18 56 Q -25 57 -21 37 Z", fill: 0xDF8EAB, stroke: .none, width: 0),
            P(.armL, "M -19 60 Q -24 57 -28 61 Q -32 67 -26 70 Q -20 72 -18 67 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.armR, "M 10 25 Q 18 22 22 32 Q 28 45 29 57 Q 27 65 19 62 Q 15 50 9 36 Z", fill: 0xFFB3C7, stroke: .outline, width: 3.2),
            P(.armR, "M 21 37 Q 29 49 29 57 Q 27 65 19 62 L 18 56 Q 25 57 21 37 Z", fill: 0xDF8EAB, stroke: .none, width: 0),
            P(.armR, "M 19 60 Q 24 57 28 61 Q 32 67 26 70 Q 20 72 18 67 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.head, "M-31 -28 Q-45 6 -40 43 L-46 54 Q-29 54 -22 35 L-24 8 Z M31 -28 Q45 6 40 43 L46 54 Q29 54 22 35 L24 8 Z", fill: 0xE996B2, stroke: .outline, width: 3.2),
            P(.head, "M-33 -36 Q-39 -55 -31 -72 Q-20 -70 -10 -51 M10 -51 Q23 -71 32 -73 Q39 -54 34 -35 Z", fill: 0xFFF7F4, stroke: .outline, width: 3.2),
            P(.head, "M-29 -62 L-26 -43 L-17 -50 Z M28 -63 L18 -50 L29 -43 Z", fill: 0xE996B2, stroke: .none, width: 0),
            P(.head, "M-36 -20 Q-38 -53 0 -54 Q38 -53 36 -20 L34 -4 Q28 19 0 20 Q-28 19 -34 -4 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.head, "M-33 -7 Q-21 17 5 15 Q24 15 34 -4 Q28 19 0 20 Q-28 19 -33 -7 Z", fill: 0xF4BEAB, stroke: .none, width: 0),
            P(.head, "M-36 -10 Q-45 -45 -19 -53 Q4 -65 25 -49 Q43 -40 35 -8 L27 -18 L22 -36 Q14 -22 0 -20 L5 -35 Q-6 -22 -22 -23 L-27 -9 L-30 32 Q-39 19 -36 -10 Z", fill: 0xF3ACC4, stroke: .outline, width: 3.2),
            P(.head, "M-29 -38 Q-15 -53 2 -49 Q-14 -42 -22 -32 Z M11 -49 Q27 -48 30 -31 Q22 -42 11 -44 Z", fill: 0xFFD6E3, stroke: .none, width: 0),
            P(.head, "M-34 4 Q-35 26 -39 39 M32 0 Q38 25 34 40", stroke: .color(0xFFD6E3), width: 2),
            P(.head, "M-18 -9 Q-18 -16 -13 -16 Q-8 -16 -8 -9 Q-8 -2 -13 -2 Q-18 -2 -18 -9 Z M8 -9 Q8 -16 13 -16 Q18 -16 18 -9 Q18 -2 13 -2 Q8 -2 8 -9 Z", fill: 0x75445D, stroke: .ink, width: 1.6, show: .rest),
            P(.head, "M-14 -4 h2 M12 -4 h2", stroke: .color(0xDFA284), width: 1.8, show: .rest),
            P(.head, "M-15.7 -12 Q-15.7 -14.5 -13.5 -14.5 Q-11.3 -14.5 -11.3 -12 Q-11.3 -9.5 -13.5 -9.5 Q-15.7 -9.5 -15.7 -12 Z M10.3 -12 Q10.3 -14.5 12.5 -14.5 Q14.7 -14.5 14.7 -12 Q14.7 -9.5 12.5 -9.5 Q10.3 -9.5 10.3 -12 Z", fill: 0xFFFFFF, stroke: .none, width: 0, show: .rest),
            P(.head, "M-18 -9 q5 -7 10 0 M8 -9 q5 -7 10 0", stroke: .ink, width: 3, show: .dance),
            E(.head, -24, 3, 6, 3, fill: 0xF3A0AC, stroke: .none),
            E(.head, 24, 3, 6, 3, fill: 0xF3A0AC, stroke: .none),
            P(.head, "M-6 5 Q0 8 6 5 Q4 15 0 14 Q-4 15 -6 5 Z", fill: 0xA94C60, stroke: .ink, width: 1.6),
            P(.head, "M-2 11 Q0 10 2 11", stroke: .color(0xFFB3C7), width: 2.4),
            P(.sleep, "M-12 28 Q18 14 46 26 Q65 31 67 47 Q54 59 15 57 L-14 50 Z", fill: 0xFFB3C7, stroke: .outline, width: 3.2),
            P(.sleep, "M12 47 Q41 53 61 39 L67 47 Q54 59 15 57 L-14 50 Z", fill: 0xDF8EAB, stroke: .none, width: 0),
            P(.sleep, "M56 37 Q69 34 77 40 L78 49 Q68 53 58 48 Z", fill: 0xFFF7F4, stroke: .outline, width: 3.2),
            P(.sleep, "M73 39 Q83 36 84 44 Q84 51 76 51 L72 48 Z", fill: 0xFF6F91, stroke: .outline, width: 3.2),
            P(.sleep, "M-60 12 Q-63 -10 -35 -13 Q-7 -13 -5 15 Q4 24 16 39 Q8 56 -24 55 L-57 45 Z", fill: 0xE996B2, stroke: .outline, width: 3.2),
            P(.sleep, "M-60 8 Q-69 -11 -63 -23 Q-50 -21 -42 -8 M-28 -8 Q-21 -31 -15 -30 Q-6 -15 -8 5 Z", fill: 0xFFF7F4, stroke: .outline, width: 3.2),
            P(.sleep, "M-60 -14 L-56 0 L-48 -6 Z M-18 -21 L-24 -7 L-14 -4 Z", fill: 0xF3ACC4, stroke: .none, width: 0),
            P(.sleep, "M-63 22 Q-64 -5 -34 -6 Q-5 -5 -5 23 Q-8 49 -34 51 Q-61 49 -63 22 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.sleep, "M-62 23 Q-68 -5 -42 -12 Q-12 -18 -5 12 L-8 24 Q-17 8 -24 9 L-30 16 L-31 5 Q-43 17 -54 13 Z", fill: 0xF3ACC4, stroke: .outline, width: 3.2),
            P(.sleep, "M-56 3 Q-45 -7 -32 -6", stroke: .color(0xFFD6E3), width: 3),
            P(.sleep, "M-51 27 Q-46 33 -40 27 M-29 27 Q-24 33 -18 27", stroke: .ink, width: 2.5),
            P(.sleep, "M-37 39 Q-33 42 -29 38", stroke: .ink, width: 1.8),
            E(.sleep, -52, 37, 5, 3, fill: 0xF3A0AC, stroke: .none),
            E(.sleep, -16, 37, 5, 3, fill: 0xF3A0AC, stroke: .none),
            P(.sleep, "M-22 44 Q-8 37 3 44 Q6 50 -2 53 L-22 53 Q-28 49 -22 44 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.sleep, "M54 53 Q81 57 83 42 Q81 37 85 35 Q93 34 93 44 Q93 72 55 69 L29 66 Q25 60 31 59 Z", fill: 0xF3ACC4, stroke: .outline, width: 3.2),
        ]
        return BuddyRig(
            pieces: p,
            pivots: [.tail: (14, 66), .legL: (-8, 72), .legR: (8, 72), .body: (0, 72), .armL: (-12, 30),
                     .armR: (12, 30), .head: (0, 18)],
            full: BuddyRect(x: -96, y: -84, w: 196, h: 234), barBottom: nil, feet: (0, 146), sleepBottom: 72,
            zzz: [(0, -30, 12), (16, -46, 15), (36, -64, 19)],
            style: .init(armL: 2.3, armR: 2.3, armAmp: 0.3, alternate: true, kick: 0.6, bounce: 9, step: 8),
            face: (0, -2, 28, 19), brows: "M-20 -20 L-8 -17 M20 -20 L8 -17",
            hat: (0, -49, 26), sleepHat: (-34, -10, 26), neck: (0, 22), hand: (24, 66))
    }()

    // Tousled-haired boy: navy vest, ivory tee and denim sneakers.
    static let boy: BuddyRig = {
        let p: [BuddyPiece] = [
            P(.legL, "M -2 68 L -17 65 Q -21 91 -20 108 L -23 132 Q -16 139 -9 132 L -5 106 Z", fill: 0x83ACCA, stroke: .outline, width: 3.2),
            P(.legL, "M -14 70 L -17 65 Q -21 91 -20 108 L -23 132 L -17 134 L -13 105 Z", fill: 0x5F88AB, stroke: .none, width: 0),
            P(.legL, "M -9 130 Q -17 126 -23 131 L -29 137 Q -32 143 -24 144 L -8 143 Q -4 139 -9 130 Z", fill: 0xFFF9F3, stroke: .outline, width: 3.2),
            P(.legL, "M -11 135 L -20 135 M -9 141 L -26 141", stroke: .color(0xB8C6D7), width: 1.7),
            P(.legR, "M 2 68 L 17 65 Q 21 91 20 108 L 23 132 Q 16 139 9 132 L 5 106 Z", fill: 0x83ACCA, stroke: .outline, width: 3.2),
            P(.legR, "M 14 70 L 17 65 Q 21 91 20 108 L 23 132 L 17 134 L 13 105 Z", fill: 0x5F88AB, stroke: .none, width: 0),
            P(.legR, "M 9 130 Q 17 126 23 131 L 29 137 Q 32 143 24 144 L 8 143 Q 4 139 9 130 Z", fill: 0xFFF9F3, stroke: .outline, width: 3.2),
            P(.legR, "M 11 135 L 20 135 M 9 141 L 26 141", stroke: .color(0xB8C6D7), width: 1.7),
            P(.body, "M-18 20 Q0 14 18 20 L23 69 Q0 76 -23 69 Z", fill: 0xFFF9F3, stroke: .outline, width: 3.2),
            P(.body, "M8 32 Q10 52 19 62 L23 69 Q0 76 -23 69 L-21 64 Q2 70 8 59 Z", fill: 0xDFE6EE, stroke: .none, width: 0),
            P(.body, "M-19 20 L-9 18 Q-12 38 -9 57 L-10 73 L-26 73 L-22 36 Z M9 18 L19 20 L22 36 L26 73 L10 73 L9 57 Q12 38 9 18 Z", fill: 0x304563, stroke: .outline, width: 3.2),
            P(.body, "M-18 28 L-19 59 M18 28 L19 59", stroke: .color(0x536B8C), width: 2),
            P(.body, "M-7 23 Q0 28 7 23", stroke: .color(0xB8C6D7), width: 2),
            P(.armL, "M -14 28 Q -20 23 -25 31 L -32 53 Q -36 63 -29 67 Q -22 69 -20 60 L -15 45 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.armL, "M -14 23 Q -21 19 -26 27 L -30 39 Q -24 45 -16 40 L -11 31 Z", fill: 0xFFF9F3, stroke: .outline, width: 3.2),
            P(.armL, "M -24 45 Q -30 56 -27 61", stroke: .color(0xF0BCA3), width: 2),
            P(.armR, "M 14 28 Q 20 23 25 31 L 32 53 Q 36 63 29 67 Q 22 69 20 60 L 15 45 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.armR, "M 14 23 Q 21 19 26 27 L 30 39 Q 24 45 16 40 L 11 31 Z", fill: 0xFFF9F3, stroke: .outline, width: 3.2),
            P(.armR, "M 24 45 Q 30 56 27 61", stroke: .color(0xF0BCA3), width: 2),
            P(.head, "M-32 -16 Q-45 -21 -42 -7 Q-40 2 -31 2 M32 -16 Q45 -21 42 -7 Q40 2 31 2 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.head, "M-36 -24 Q-35 -53 0 -53 Q36 -53 36 -24 L33 -2 Q26 19 0 20 Q-26 19 -33 -2 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.head, "M-33 -3 Q-20 15 6 14 Q22 13 33 -2 Q26 19 0 20 Q-26 19 -33 -3 Z", fill: 0xF0BCA3, stroke: .none, width: 0),
            P(.head, "M-34 -5 L-40 -22 L-37 -33 L-43 -34 Q-35 -51 -19 -53 L-24 -60 Q-7 -62 3 -57 Q18 -64 28 -52 Q42 -45 39 -27 L35 -8 L28 -17 L25 -35 Q14 -24 5 -25 L9 -38 Q-3 -23 -16 -22 L-12 -33 L-27 -22 L-29 -7 Z", fill: 0x303141, stroke: .outline, width: 3.2),
            P(.head, "M-31 -37 Q-18 -52 -4 -48 Q-16 -43 -22 -33 Z M6 -49 Q22 -56 30 -39 Q18 -46 6 -43 Z", fill: 0x4C5066, stroke: .none, width: 0),
            P(.head, "M-20 -20 Q-14 -23 -8 -20 M8 -20 Q14 -23 20 -20", stroke: .ink, width: 1.8),
            P(.head, "M-17.8 -8 Q-17.8 -14.8 -13 -14.8 Q-8.2 -14.8 -8.2 -8 Q-8.2 -1.2 -13 -1.2 Q-17.8 -1.2 -17.8 -8 Z M8.2 -8 Q8.2 -14.8 13 -14.8 Q17.8 -14.8 17.8 -8 Q17.8 -1.2 13 -1.2 Q8.2 -1.2 8.2 -8 Z", fill: 0x4B485C, stroke: .ink, width: 1.6, show: .rest),
            P(.head, "M-14 -3.2 h2 M12 -3.2 h2", stroke: .color(0xDFA284), width: 1.8, show: .rest),
            P(.head, "M-15.7 -11 Q-15.7 -13.5 -13.5 -13.5 Q-11.3 -13.5 -11.3 -11 Q-11.3 -8.5 -13.5 -8.5 Q-15.7 -8.5 -15.7 -11 Z M10.3 -11 Q10.3 -13.5 12.5 -13.5 Q14.7 -13.5 14.7 -11 Q14.7 -8.5 12.5 -8.5 Q10.3 -8.5 10.3 -11 Z", fill: 0xFFFFFF, stroke: .none, width: 0, show: .rest),
            P(.head, "M-18 -8 q5 -7 10 0 M8 -8 q5 -7 10 0", stroke: .ink, width: 3, show: .dance),
            E(.head, -24, 4, 6, 3, fill: 0xF2B1A7, stroke: .none),
            E(.head, 24, 4, 6, 3, fill: 0xF2B1A7, stroke: .none),
            P(.head, "M-8 5 Q0 9 8 5 Q6 16 0 16 Q-6 16 -8 5 Z", fill: 0xA7525B, stroke: .ink, width: 1.8),
            P(.head, "M-5 7 Q0 9 5 7 L4 10 L-4 10 Z", fill: 0xFFF9F3, stroke: .none, width: 0),
            P(.sleep, "M-10 27 Q14 15 41 25 L61 35 L59 50 Q35 58 -8 53 Z", fill: 0x304563, stroke: .outline, width: 3.2),
            P(.sleep, "M26 29 Q49 25 68 38 L70 48 Q54 58 30 49 Z", fill: 0x83ACCA, stroke: .outline, width: 3.2),
            P(.sleep, "M40 36 Q52 44 61 43", stroke: .color(0x5F88AB), width: 3),
            P(.sleep, "M66 38 Q76 33 81 42 Q84 49 76 51 L67 49 Z", fill: 0xFFF9F3, stroke: .outline, width: 3.2),
            P(.sleep, "M-64 21 Q-64 -8 -34 -8 Q-4 -8 -4 22 Q-7 48 -34 51 Q-60 48 -64 21 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
            P(.sleep, "M-61 32 Q-36 54 -7 31 Q-10 49 -34 51 Q-55 48 -61 32 Z", fill: 0xF0BCA3, stroke: .none, width: 0),
            P(.sleep, "M-62 24 L-68 9 L-65 -3 L-69 -7 Q-54 -18 -41 -14 Q-18 -24 -7 -8 Q2 3 -5 21 L-13 11 L-17 2 Q-28 15 -40 13 L-35 3 Q-48 15 -58 11 Z", fill: 0x303141, stroke: .outline, width: 3.2),
            P(.sleep, "M-57 -2 Q-42 -13 -28 -9 L-42 1 Z", fill: 0x4C5066, stroke: .none, width: 0),
            P(.sleep, "M-51 26 Q-46 32 -40 26 M-29 26 Q-24 32 -18 26", stroke: .ink, width: 2.5),
            E(.sleep, -51, 36, 5, 3, fill: 0xF2B1A7, stroke: .none),
            E(.sleep, -17, 36, 5, 3, fill: 0xF2B1A7, stroke: .none),
            P(.sleep, "M-37 38 Q-33 42 -29 38", stroke: .ink, width: 1.8),
            P(.sleep, "M-22 44 Q-9 38 2 44 Q6 50 -3 53 L-22 53 Q-28 49 -22 44 Z", fill: 0xFFE0C7, stroke: .outline, width: 3.2),
        ]
        return BuddyRig(
            pieces: p,
            pivots: [.legL: (-9, 68), .legR: (9, 68), .body: (0, 70), .armL: (-18, 26), .armR: (18, 26),
                     .head: (0, 16)],
            full: BuddyRect(x: -92, y: -76, w: 184, h: 226), barBottom: nil, feet: (0, 142), sleepBottom: 57,
            zzz: [(0, -30, 12), (16, -46, 15), (36, -64, 19)],
            style: .init(armL: -1.3, armR: 2.3, armAmp: 0.2, alternate: false, kick: 0.3, bounce: 8, step: 10),
            face: (0, -2, 28, 19), brows: "M-20 -20 L-8 -17 M20 -20 L8 -17",
            hat: (2, -48, 26), sleepHat: (-34, -12, 26), neck: (0, 22), hand: (27, 60))
    }()

    // Round tabby: cream cheeks, tiny paw pads and a striped tail.
    static let cat: BuddyRig = {
        let p: [BuddyPiece] = [
            P(.tail, "M18 75 Q45 82 47 61 Q44 39 54 30 Q60 24 64 30 Q68 36 61 43 Q58 48 61 61 Q64 94 20 88 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.tail, "M48 43 Q46 35 54 30 Q60 24 64 30 Q68 36 61 43 L57 48 Z", fill: 0xFFF0D5, stroke: .none, width: 0),
            P(.tail, "M50 55 L60 53 M46 73 L56 78", stroke: .color(0xDC8736), width: 5),
            P(.legL, "M -7 85 Q -14 80 -21 87 L -24 103 Q -29 115 -17 116 L -8 115 Q -2 112 -5 103 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.legL, "M -5 103 Q -14 108 -24 103 Q -29 115 -17 116 L -8 115 Q -2 112 -5 103 Z", fill: 0xFFF0D5, stroke: .none, width: 0),
            P(.legL, "M -10 109 L -10 113 M -16 110 L -16 114", stroke: .color(0xD4AE8D), width: 1.4),
            P(.legR, "M 7 85 Q 14 80 21 87 L 24 103 Q 29 115 17 116 L 8 115 Q 2 112 5 103 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.legR, "M 5 103 Q 14 108 24 103 Q 29 115 17 116 L 8 115 Q 2 112 5 103 Z", fill: 0xFFF0D5, stroke: .none, width: 0),
            P(.legR, "M 10 109 L 10 113 M 16 110 L 16 114", stroke: .color(0xD4AE8D), width: 1.4),
            P(.body, "M-20 28 Q-32 42 -30 70 Q-32 101 0 102 Q32 101 30 70 Q32 42 20 28 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.body, "M21 42 Q39 94 10 101 L-5 101 Q25 88 21 42 Z", fill: 0xEA9B41, stroke: .none, width: 0),
            P(.body, "M0 43 Q-20 44 -20 71 Q-22 93 0 94 Q22 93 20 71 Q20 44 0 43 Z", fill: 0xFFF0D5, stroke: .none, width: 0),
            P(.body, "M-29 61 L-24 64 M-29 77 L-24 79 M29 61 L24 64 M29 77 L24 79", stroke: .color(0xDC8736), width: 3),
            P(.armL, "M -18 48 Q -24 43 -29 49 L -39 70 Q -43 80 -34 85 Q -25 87 -23 76 L -17 59 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.armL, "M -24 73 Q -31 68 -39 73 Q -43 80 -34 85 Q -25 87 -24 73 Z", fill: 0xFFF0D5, stroke: .none, width: 0),
            E(.armL, -31, 78, 3.5, 3.5, fill: 0xF4A0A1, stroke: .none),
            P(.armR, "M 18 48 Q 24 43 29 49 L 39 70 Q 43 80 34 85 Q 25 87 23 76 L 17 59 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.armR, "M 24 73 Q 31 68 39 73 Q 43 80 34 85 Q 25 87 24 73 Z", fill: 0xFFF0D5, stroke: .none, width: 0),
            E(.armR, 31, 78, 3.5, 3.5, fill: 0xF4A0A1, stroke: .none),
            P(.head, "M-40 -17 Q-44 -39 -34 -57 Q-26 -59 -10 -39 L10 -39 Q26 -59 34 -57 Q44 -39 40 -17 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.head, "M-35 -46 Q-38 -32 -31 -25 L-18 -36 Z M35 -46 Q38 -32 31 -25 L18 -36 Z", fill: 0xF4A0A1, stroke: .none, width: 0),
            P(.head, "M-38 -21 Q-28 -39 0 -39 Q28 -39 38 -21 L43 -8 L39 -7 L46 2 L41 4 Q47 17 32 29 Q17 40 0 40 Q-17 40 -32 29 Q-47 17 -41 4 L-46 2 L-39 -7 L-43 -8 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.head, "M-40 9 Q-25 -3 -12 6 Q0 -2 12 6 Q25 -3 40 9 Q41 27 18 35 Q0 43 -18 35 Q-41 27 -40 9 Z", fill: 0xFFF0D5, stroke: .none, width: 0),
            P(.head, "M-14 -36 L-10 -21 Q-6 -20 -7 -35 Z M-3 -39 L-2 -22 Q1 -17 4 -38 Z M11 -36 L7 -22 Q11 -20 16 -34 Z", fill: 0xDC8736, stroke: .none, width: 0),
            P(.head, "M-22.5 -4 Q-22.5 -11 -17 -11 Q-11.5 -11 -11.5 -4 Q-11.5 3 -17 3 Q-22.5 3 -22.5 -4 Z M11.5 -4 Q11.5 -11 17 -11 Q22.5 -11 22.5 -4 Q22.5 3 17 3 Q11.5 3 11.5 -4 Z", fill: 0x654532, stroke: .ink, width: 1.6, show: .rest),
            P(.head, "M-18 1 h2 M16 1 h2", stroke: .color(0xDFA284), width: 1.8, show: .rest),
            P(.head, "M-19.7 -7 Q-19.7 -9.5 -17.5 -9.5 Q-15.3 -9.5 -15.3 -7 Q-15.3 -4.5 -17.5 -4.5 Q-19.7 -4.5 -19.7 -7 Z M14.3 -7 Q14.3 -9.5 16.5 -9.5 Q18.7 -9.5 18.7 -7 Q18.7 -4.5 16.5 -4.5 Q14.3 -4.5 14.3 -7 Z", fill: 0xFFFFFF, stroke: .none, width: 0, show: .rest),
            P(.head, "M-22 -4 q5 -7 10 0 M12 -4 q5 -7 10 0", stroke: .ink, width: 3, show: .dance),
            E(.head, -29, 14, 6, 3, fill: 0xF4B09A, stroke: .none),
            E(.head, 29, 14, 6, 3, fill: 0xF4B09A, stroke: .none),
            P(.head, "M-4 8 Q0 6 4 8 Q3 12 0 13 Q-3 12 -4 8 Z", fill: 0xE7878B, stroke: .none, width: 0),
            P(.head, "M-7 17 Q0 21 7 17 Q5 29 0 29 Q-5 29 -7 17 Z", fill: 0xA65350, stroke: .ink, width: 1.8),
            P(.head, "M-3 25 Q0 23 3 25", stroke: .color(0xF4A0A1), width: 3),
            P(.head, "M0 13 L0 17 Q-4 21 -8 16 M0 17 Q4 21 8 16 M-32 11 L-44 8 M-32 18 L-44 20 M32 11 L44 8 M32 18 L44 20", stroke: .ink, width: 1.8),
            P(.sleep, "M-20 32 Q-3 9 29 16 Q62 19 64 45 Q64 65 28 65 L-22 58 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.sleep, "M26 23 Q45 29 43 54 Q29 64 3 57 Q10 42 26 23 Z", fill: 0xFFF0D5, stroke: .none, width: 0),
            P(.sleep, "M13 18 L10 27 M28 19 L24 30 M44 24 L39 34", stroke: .color(0xDC8736), width: 4),
            P(.sleep, "M-61 12 Q-68 -7 -61 -15 Q-49 -13 -40 0 L-26 0 Q-15 -14 -7 -13 L-10 16 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.sleep, "M-59 -7 L-55 9 L-45 3 Z M-13 -5 L-25 5 L-14 11 Z", fill: 0xF4A0A1, stroke: .none, width: 0),
            P(.sleep, "M-65 25 Q-65 -2 -34 -3 Q-3 -2 -3 25 Q-6 54 -34 55 Q-62 54 -65 25 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.sleep, "M-63 32 Q-48 21 -34 30 Q-20 21 -5 32 Q-10 53 -34 55 Q-58 53 -63 32 Z", fill: 0xFFF0D5, stroke: .none, width: 0),
            P(.sleep, "M-42 1 L-40 11 M-32 0 L-32 10 M-22 2 L-24 11", stroke: .color(0xDC8736), width: 3),
            P(.sleep, "M-54 26 Q-48 33 -41 26 M-28 26 Q-21 33 -15 26", stroke: .ink, width: 2.5),
            P(.sleep, "M-38 34 Q-34 31 -30 34 L-34 38 Z", fill: 0xE7878B, stroke: .none, width: 0),
            P(.sleep, "M-34 38 Q-38 43 -42 39 M-34 38 Q-30 43 -26 39", stroke: .ink, width: 1.6),
            E(.sleep, -54, 37, 5, 3, fill: 0xF4B09A, stroke: .none),
            E(.sleep, -14, 37, 5, 3, fill: 0xF4B09A, stroke: .none),
            P(.sleep, "M56 45 Q64 40 67 48 Q72 66 44 67 Q13 70 -6 60 Q-12 55 -7 51 Q-3 47 5 51 Q35 62 54 56 Q60 53 56 45 Z", fill: 0xFFB957, stroke: .outline, width: 3.2),
            P(.sleep, "M12 54 Q7 64 -3 62 Q-13 58 -7 51 Q-3 47 5 51 Z", fill: 0xFFF0D5, stroke: .none, width: 0),
            P(.sleep, "M28 59 L26 66 M43 60 L43 67", stroke: .color(0xDC8736), width: 4),
        ]
        return BuddyRig(
            pieces: p,
            pivots: [.tail: (18, 80), .legL: (-14, 88), .legR: (14, 88), .body: (0, 96), .armL: (-22, 52),
                     .armR: (22, 52), .head: (0, 32)],
            full: BuddyRect(x: -80, y: -66, w: 160, h: 188), barBottom: nil, feet: (0, 116), sleepBottom: 68,
            zzz: [(0, -30, 12), (16, -46, 15), (36, -64, 19)],
            style: .init(armL: 1.2, armR: 1.2, armAmp: 0.6, alternate: true, kick: 0.2, bounce: 10, step: 8),
            heart: (0, 68, 13), face: (0, 10, 33, 22), brows: "M-24 -17 L-11 -13 M24 -17 L11 -13",
            hat: (0, -36, 24), sleepHat: (-34, -2, 28), neck: (0, 40), hand: (31, 78))
    }()

    // Butter-yellow chick: swept crest, downy belly and scalloped wings.
    static let chick: BuddyRig = {
        let p: [BuddyPiece] = [
            P(.legL, "M -8 85 L -17 85 L -17 101 Q -27 102 -26 108 Q -23 113 -17 109 Q -11 115 -7 109 Q 0 111 0 106 Q -1 102 -8 101 Z", fill: 0xF6A13A, stroke: .outline, width: 3.2),
            P(.legL, "M -11 102 L -11 108 M -17 103 L -19 107", stroke: .color(0xD78129), width: 1.5),
            P(.legR, "M 8 85 L 17 85 L 17 101 Q 27 102 26 108 Q 23 113 17 109 Q 11 115 7 109 Q 0 111 0 106 Q 1 102 8 101 Z", fill: 0xF6A13A, stroke: .outline, width: 3.2),
            P(.legR, "M 11 102 L 11 108 M 17 103 L 19 107", stroke: .color(0xD78129), width: 1.5),
            P(.body, "M-27 31 Q-42 50 -36 74 Q-30 96 0 96 Q30 96 36 74 Q42 50 27 31 Z", fill: 0xFFE17A, stroke: .outline, width: 3.2),
            P(.body, "M28 47 Q44 84 14 94 Q-2 100 -22 89 Q24 93 28 47 Z", fill: 0xF5C35D, stroke: .none, width: 0),
            P(.body, "M0 48 Q-22 48 -23 70 Q-23 89 0 90 Q23 89 23 70 Q22 48 0 48 Z", fill: 0xFFF1BE, stroke: .none, width: 0),
            P(.armL, "M -30 47 Q -39 44 -48 53 Q -61 64 -54 68 L -49 67 Q -59 77 -49 78 L -45 76 Q -50 87 -40 84 Q -29 79 -25 59 Z", fill: 0xFFE17A, stroke: .outline, width: 3.2),
            P(.armL, "M -35 64 Q -40 71 -46 72 M -34 72 Q -38 78 -41 79", stroke: .color(0xF0BC55), width: 2),
            P(.armR, "M 30 47 Q 39 44 48 53 Q 61 64 54 68 L 49 67 Q 59 77 49 78 L 45 76 Q 50 87 40 84 Q 29 79 25 59 Z", fill: 0xFFE17A, stroke: .outline, width: 3.2),
            P(.armR, "M 35 64 Q 40 71 46 72 M 34 72 Q 38 78 41 79", stroke: .color(0xF0BC55), width: 2),
            P(.head, "M-39 -6 Q-38 -34 -8 -39 Q-19 -49 -11 -53 Q-5 -53 -4 -44 Q-3 -61 13 -61 Q24 -59 14 -49 L7 -41 Q24 -52 28 -44 Q30 -38 18 -34 Q40 -25 40 -3 L43 6 L39 8 Q38 35 0 39 Q-38 35 -39 8 L-43 6 Z", fill: 0xFFE17A, stroke: .outline, width: 3.2),
            P(.head, "M-33 14 Q-13 38 14 29 Q31 25 38 13 Q35 37 0 39 Q-28 36 -33 14 Z", fill: 0xF5C35D, stroke: .none, width: 0),
            P(.head, "M-27 -20 Q-18 -34 -4 -33 Q-17 -25 -20 -15 Z M0 -47 Q4 -57 13 -56 L7 -50 Z", fill: 0xFFF1AE, stroke: .none, width: 0),
            P(.head, "M-23 -15 Q-18 -19 -13 -16 M13 -16 Q18 -19 23 -15", stroke: .color(0xC49139), width: 1.8),
            P(.head, "M-21 0 Q-21 -6.5 -16 -6.5 Q-11 -6.5 -11 0 Q-11 6.5 -16 6.5 Q-21 6.5 -21 0 Z M11 0 Q11 -6.5 16 -6.5 Q21 -6.5 21 0 Q21 6.5 16 6.5 Q11 6.5 11 0 Z", fill: 0x6A482B, stroke: .ink, width: 1.6, show: .rest),
            P(.head, "M-17 4.5 h2 M15 4.5 h2", stroke: .color(0xDFA284), width: 1.8, show: .rest),
            P(.head, "M-18.7 -3 Q-18.7 -5.5 -16.5 -5.5 Q-14.3 -5.5 -14.3 -3 Q-14.3 -0.5 -16.5 -0.5 Q-18.7 -0.5 -18.7 -3 Z M13.3 -3 Q13.3 -5.5 15.5 -5.5 Q17.7 -5.5 17.7 -3 Q17.7 -0.5 15.5 -0.5 Q13.3 -0.5 13.3 -3 Z", fill: 0xFFFFFF, stroke: .none, width: 0, show: .rest),
            P(.head, "M-21 0 q5 -7 10 0 M11 0 q5 -7 10 0", stroke: .ink, width: 3, show: .dance),
            E(.head, -27, 14, 6, 3, fill: 0xF5AF71, stroke: .none),
            E(.head, 27, 14, 6, 3, fill: 0xF5AF71, stroke: .none),
            P(.head, "M-8 14 Q0 10 8 14 Q6 27 0 27 Q-6 27 -8 14 Z", fill: 0xC46A36, stroke: .ink, width: 1.8),
            P(.head, "M-10 12 Q-4 4 0 5 Q4 4 10 12 Q0 19 -10 12 Z", fill: 0xF6A13A, stroke: .ink, width: 1.8),
            P(.head, "M-2 23 L2 23", stroke: .color(0xF5AF71), width: 2.5),
            P(.sleep, "M-21 28 Q6 9 33 21 Q56 31 53 51 Q50 69 10 68 Q-23 67 -31 49 Z", fill: 0xFFE17A, stroke: .outline, width: 3.2),
            P(.sleep, "M10 48 Q28 42 45 52 Q35 66 10 65 Q-9 65 -18 56 Z", fill: 0xFFF1BE, stroke: .none, width: 0),
            P(.sleep, "M41 60 Q47 57 53 62 L57 66 Q49 70 42 66 Z", fill: 0xF6A13A, stroke: .outline, width: 3.2),
            P(.sleep, "M13 31 Q32 25 42 38 Q48 48 41 48 L36 46 Q41 54 33 53 Q20 50 13 31 Z", fill: 0xFFE17A, stroke: .outline, width: 3.2),
            P(.sleep, "M24 37 Q29 43 34 44", stroke: .color(0xF0BC55), width: 2),
            P(.sleep, "M-59 24 Q-59 3 -39 -1 Q-48 -10 -42 -14 Q-36 -16 -31 -6 Q-27 -23 -17 -18 Q-11 -13 -24 -4 Q-1 1 0 24 Q-1 52 -30 55 Q-59 52 -59 24 Z", fill: 0xFFE17A, stroke: .outline, width: 3.2),
            P(.sleep, "M-56 35 Q-32 55 -3 34 Q-8 52 -30 55 Q-50 52 -56 35 Z", fill: 0xF5C35D, stroke: .none, width: 0),
            P(.sleep, "M-49 10 Q-42 2 -33 4 L-43 14 Z", fill: 0xFFF1AE, stroke: .none, width: 0),
            P(.sleep, "M-49 25 Q-43 32 -37 25 M-25 25 Q-19 32 -13 25", stroke: .ink, width: 2.5),
            P(.sleep, "M-57 32 Q-68 33 -68 38 Q-62 43 -55 40 Z", fill: 0xF6A13A, stroke: .ink, width: 1.8),
            E(.sleep, -47, 37, 5, 3, fill: 0xF5AF71, stroke: .none),
            E(.sleep, -12, 37, 5, 3, fill: 0xF5AF71, stroke: .none),
        ]
        return BuddyRig(
            pieces: p,
            pivots: [.legL: (-12, 86), .legR: (12, 86), .body: (0, 94), .armL: (-32, 50), .armR: (32, 50),
                     .head: (0, 34)],
            full: BuddyRect(x: -80, y: -66, w: 160, h: 188), barBottom: nil, feet: (0, 110), sleepBottom: 68,
            zzz: [(0, -34, 12), (16, -50, 15), (36, -68, 19)],
            style: .init(armL: 1.0, armR: 1.0, armAmp: 0.7, alternate: false, kick: 0.3, bounce: 12, step: 8),
            heart: (0, 66, 13), face: (0, 10, 30, 21), brows: "M-23 -15 L-11 -11 M23 -15 L11 -11",
            hat: (0, -36, 24), sleepHat: (-30, 0, 26), neck: (0, 39), hand: (43, 79))
    }()
    static let shiba: BuddyRig = {
        let p: [BuddyPiece] = [
            P(.tail, "M29 58 Q63 66 62 34 Q62 18 48 18 Q36 19 39 34 Q42 39 49 35 Q45 54 24 44 Z", fill: 0xDA8345, stroke: .outline, width: 3.2),
            P(.tail, "M48 21 Q62 20 59 36 Q58 43 51 47 Q56 34 48 32 Z", fill: 0xFFF2D7, stroke: .none, width: 0),
            P(.legL, "M-27 76 Q-31 86 -30 103 Q-29 112 -16 111 Q-6 110 -8 102 L-12 77 Z", fill: 0xF4B267, stroke: .outline, width: 3.2),
            P(.legR, "M13 77 L28 77 Q31 91 31 103 Q31 112 18 111 Q8 110 8 103 Z", fill: 0xF4B267, stroke: .outline, width: 3.2),
            P(.body, "M-28 28 Q-43 44 -38 75 Q-34 96 0 97 Q35 98 39 72 Q43 46 27 28 Z", fill: 0xE99B58, stroke: .outline, width: 3.2),
            P(.body, "M27 48 Q42 83 12 95 Q-14 100 -28 86 Q22 92 27 48 Z", fill: 0xD47D43, stroke: .none, width: 0),
            P(.body, "M-20 49 Q0 39 20 49 Q28 76 0 89 Q-28 77 -20 49 Z", fill: 0xFFF2D7, stroke: .none, width: 0),
            P(.armL, "M-30 45 Q-49 47 -46 70 Q-43 84 -29 79 L-21 58 Z", fill: 0xE99B58, stroke: .outline, width: 3.2),
            P(.armR, "M30 45 Q49 47 46 70 Q43 84 29 79 L21 58 Z", fill: 0xE99B58, stroke: .outline, width: 3.2),
            P(.head, "M-36 -15 L-37 -55 Q-23 -53 -12 -34 Q0 -39 12 -34 Q23 -53 37 -55 L36 -15 Q44 3 33 22 Q19 40 0 40 Q-20 40 -34 22 Q-44 2 -36 -15 Z", fill: 0xE99B58, stroke: .outline, width: 3.2),
            P(.head, "M-34 15 Q-28 38 0 40 Q28 39 34 15 Q19 23 13 14 Q0 24 -13 14 Q-19 23 -34 15 Z", fill: 0xFFF2D7, stroke: .none, width: 0),
            P(.head, "M-33 -48 L-29 -22 Q-24 -30 -20 -36 Z M33 -48 L29 -22 Q24 -30 20 -36 Z", fill: 0xD87570, stroke: .none, width: 0),
            E(.head, -15, -5, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, 15, -5, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, -16, -8, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            E(.head, 14, -8, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            P(.head, "M-20 -5 q5 -7 10 0 M10 -5 q5 -7 10 0", stroke: .ink, width: 2.6, show: .dance),
            E(.head, -29, 17, 7, 3, fill: 0xF2A1A1, stroke: .none),
            E(.head, 29, 17, 7, 3, fill: 0xF2A1A1, stroke: .none),
            P(.head, "M-6 12 Q0 8 6 12 Q4 18 0 18 Q-4 18 -6 12 Z", fill: 0x453532, stroke: .ink, width: 1.5),
            P(.head, "M0 19 Q-8 27 -13 20 M0 19 Q8 27 13 20", stroke: .ink, width: 2.2),
            P(.sleep, "M-30 30 Q-10 14 23 20 Q57 22 58 47 Q59 68 27 69 L-20 68 Q-49 64 -47 45 Z", fill: 0xE99B58, stroke: .outline, width: 3.2),
            P(.sleep, "M14 50 Q43 45 54 52 Q47 68 21 67 Q-5 68 -24 60 Q-6 64 14 50 Z", fill: 0xD47D43, stroke: .none, width: 0),
            P(.sleep, "M-59 28 Q-58 -5 -29 -7 Q-5 -5 0 25 Q2 52 -28 55 Q-57 54 -59 28 Z", fill: 0xE99B58, stroke: .outline, width: 3.2),
            P(.sleep, "M-49 27 Q-43 34 -37 27 M-25 27 Q-19 34 -13 27", stroke: .ink, width: 2.5),
            E(.sleep, -49, 39, 5, 3, fill: 0xF2A1A1, stroke: .none),
            E(.sleep, -13, 39, 5, 3, fill: 0xF2A1A1, stroke: .none),
            P(.sleep, "M-37 36 Q-30 32 -25 36 Q-30 41 -37 36 Z", fill: 0x433331, stroke: .ink, width: 1.6),
            P(.sleep, "M-55 1 L-54 -16 L-38 -3 M-15 -5 L-3 -19 L-3 7", fill: 0xE99B58, stroke: .outline, width: 3.2),
        ]
        return BuddyRig(
            pieces: p,
            pivots: [.tail: (31, 58), .legL: (-18, 78), .legR: (18, 78), .body: (0, 92), .armL: (-30, 46), .armR: (30, 46), .head: (0, 34)],
            full: BuddyRect(x: -80, y: -66, w: 160, h: 188), barBottom: nil, feet: (0, 111), sleepBottom: 69,
            zzz: [(0, -34, 12), (16, -50, 15), (36, -68, 19)],
            style: .init(armL: 1.2, armR: 1.2, armAmp: 0.55, alternate: true, kick: 0.3, bounce: 9, step: 8),
            heart: (0, 64, 12), face: (0, 4, 29, 20), brows: "M-23 -15 L-11 -11 M23 -15 L11 -11",
            hat: (0, -38, 31), sleepHat: (-30, -7, 26), neck: (0, 37), hand: (40, 76))
    }()
    static let koi: BuddyRig = {
        let p: [BuddyPiece] = [
            P(.tail, "M-11 82 Q-27 97 -23 113 Q-9 108 0 101 Q9 108 23 113 Q27 97 11 82 Z", fill: 0xEF8A55, stroke: .outline, width: 3.2),
            P(.tail, "M0 87 L0 105 M-16 107 Q0 94 16 107", stroke: .color(0xD65D4E), width: 1.7),
            P(.body, "M0 20 Q-35 30 -35 62 Q-34 91 0 96 Q34 91 35 62 Q35 30 0 20 Z", fill: 0xFFF8EE, stroke: .outline, width: 3.2),
            P(.body, "M24 38 Q40 73 10 93 Q-4 99 -20 86 Q17 91 24 38 Z", fill: 0xE9E0DB, stroke: .none, width: 0),
            P(.body, "M-24 42 Q-10 30 -2 44 Q8 53 -2 61 Q-15 65 -21 55 Z M10 68 Q28 57 29 73 Q26 84 12 87 Q3 80 10 68 Z", fill: 0xEF8654, stroke: .none, width: 0),
            P(.armL, "M-27 46 Q-56 39 -59 57 Q-46 74 -26 66 Z", fill: 0xFFF5E8, stroke: .outline, width: 3.2),
            P(.armL, "M-51 56 Q-42 54 -33 60", stroke: .color(0xE7A492), width: 1.8),
            P(.armR, "M27 46 Q56 39 59 57 Q46 74 26 66 Z", fill: 0xFFF5E8, stroke: .outline, width: 3.2),
            P(.armR, "M51 56 Q42 54 33 60", stroke: .color(0xE7A492), width: 1.8),
            P(.head, "M-37 17 Q-44 -10 -27 -29 Q-11 -47 9 -42 Q34 -37 40 -10 Q46 17 26 34 Q0 47 -28 32 Q-35 27 -37 17 Z", fill: 0xFFF8EE, stroke: .outline, width: 3.2),
            P(.head, "M-28 -31 Q-9 -53 12 -41 Q27 -36 30 -22 Q14 -28 11 -16 Q-7 -12 -16 -22 Z", fill: 0xED7450, stroke: .none, width: 0),
            P(.head, "M20 30 Q35 21 40 4 Q45 33 17 38 Q-8 47 -28 32 Q0 40 20 30 Z", fill: 0xE9E0DB, stroke: .none, width: 0),
            E(.head, -19, -4, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, 19, -4, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, -20, -7, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            E(.head, 18, -7, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            P(.head, "M-24 -4 q5 -7 10 0 M14 -4 q5 -7 10 0", stroke: .ink, width: 2.6, show: .dance),
            E(.head, -31, 13, 6, 3, fill: 0xF4ABA4, stroke: .none),
            E(.head, 31, 13, 6, 3, fill: 0xF4ABA4, stroke: .none),
            P(.head, "M-5 15 Q0 20 5 15", stroke: .ink, width: 2.2),
            P(.head, "M-38 16 Q-50 14 -47 26 Q-40 27 -34 22 M38 16 Q50 14 47 26 Q40 27 34 22", fill: 0xFFF8EE, stroke: .outline, width: 3.2),
            P(.sleep, "M-30 30 Q-10 14 23 20 Q57 22 58 47 Q59 68 27 69 L-20 68 Q-49 64 -47 45 Z", fill: 0xFFF8EE, stroke: .outline, width: 3.2),
            P(.sleep, "M14 50 Q43 45 54 52 Q47 68 21 67 Q-5 68 -24 60 Q-6 64 14 50 Z", fill: 0xE9E0DB, stroke: .none, width: 0),
            P(.sleep, "M-59 28 Q-58 -5 -29 -7 Q-5 -5 0 25 Q2 52 -28 55 Q-57 54 -59 28 Z", fill: 0xFFF8EE, stroke: .outline, width: 3.2),
            P(.sleep, "M-49 27 Q-43 34 -37 27 M-25 27 Q-19 34 -13 27", stroke: .ink, width: 2.5),
            E(.sleep, -49, 39, 5, 3, fill: 0xF4ABA4, stroke: .none),
            E(.sleep, -13, 39, 5, 3, fill: 0xF4ABA4, stroke: .none),
            P(.sleep, "M-57 11 Q-42 -18 -23 -3 L-15 6 Q-34 3 -42 17 Z", fill: 0xED7450, stroke: .none, width: 0),
            P(.sleep, "M36 45 Q59 34 67 48 Q61 61 39 60 Z", fill: 0xFFF2E8, stroke: .outline, width: 3.2),
        ]
        return BuddyRig(
            pieces: p,
            pivots: [.tail: (0, 85), .body: (0, 88), .armL: (-28, 53), .armR: (28, 53), .head: (0, 31)],
            full: BuddyRect(x: -80, y: -66, w: 160, h: 188), barBottom: nil, feet: (0, 110), sleepBottom: 69,
            zzz: [(0, -34, 12), (16, -50, 15), (36, -68, 19)],
            style: .init(armL: 1.8, armR: 1.8, armAmp: 0.8, alternate: true, kick: 0, bounce: 14, step: 10),
            heart: (0, 62, 11), face: (0, 3, 30, 20), brows: "M-23 -15 L-11 -11 M23 -15 L11 -11",
            hat: (0, -43, 28), sleepHat: (-32, -9, 25), neck: (0, 35), hand: (46, 60))
    }()
    static let panda: BuddyRig = {
        let p: [BuddyPiece] = [
            P(.legL, "M-25 77 Q-35 87 -32 105 Q-28 115 -11 110 Q-6 102 -11 77 Z", fill: 0x333238, stroke: .outline, width: 3.2),
            P(.legR, "M25 77 Q35 87 32 105 Q28 115 11 110 Q6 102 11 77 Z", fill: 0x333238, stroke: .outline, width: 3.2),
            P(.body, "M-29 30 Q-44 48 -38 80 Q-30 100 0 99 Q30 100 38 80 Q44 48 29 30 Z", fill: 0xFFF8EE, stroke: .outline, width: 3.2),
            P(.body, "M24 47 Q42 80 14 96 Q-10 104 -29 89 Q22 94 24 47 Z", fill: 0xE6E1DF, stroke: .none, width: 0),
            P(.armL, "M-29 44 Q-48 43 -49 65 Q-45 86 -30 79 L-21 57 Z", fill: 0x333238, stroke: .outline, width: 3.2),
            P(.armR, "M29 44 Q48 43 49 65 Q45 86 30 79 L21 57 Z", fill: 0x333238, stroke: .outline, width: 3.2),
            E(.head, -31, -30, 14, 15, fill: 0x333238, stroke: .none),
            E(.head, 31, -30, 14, 15, fill: 0x333238, stroke: .none),
            P(.head, "M-38 -13 Q-35 -42 0 -44 Q35 -42 38 -13 Q43 16 26 31 Q0 45 -26 31 Q-43 16 -38 -13 Z", fill: 0xFFF8EE, stroke: .outline, width: 3.2),
            P(.head, "M25 17 Q12 37 -12 34 Q-30 29 -37 11 Q-32 37 0 40 Q32 37 36 10 Z", fill: 0xE6E1DF, stroke: .none, width: 0),
            E(.head, -17, -2, 13, 16, fill: 0x333238, stroke: .none),
            E(.head, 17, -2, 13, 16, fill: 0x333238, stroke: .none),
            E(.head, -17, -1, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, 17, -1, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, -18, -4, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            E(.head, 16, -4, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            P(.head, "M-22 -1 q5 -7 10 0 M12 -1 q5 -7 10 0", stroke: .ink, width: 2.6, show: .dance),
            E(.head, -30, 19, 6, 3, fill: 0xF4B6B8, stroke: .none),
            E(.head, 30, 19, 6, 3, fill: 0xF4B6B8, stroke: .none),
            P(.head, "M-7 16 Q0 12 7 16 Q5 23 0 23 Q-5 23 -7 16 Z", fill: 0x333238, stroke: .ink, width: 1.5),
            P(.head, "M0 23 Q-6 29 -10 24 M0 23 Q6 29 10 24", stroke: .ink, width: 1.8),
            P(.sleep, "M-30 30 Q-10 14 23 20 Q57 22 58 47 Q59 68 27 69 L-20 68 Q-49 64 -47 45 Z", fill: 0xFFF8EE, stroke: .outline, width: 3.2),
            P(.sleep, "M14 50 Q43 45 54 52 Q47 68 21 67 Q-5 68 -24 60 Q-6 64 14 50 Z", fill: 0xE6E1DF, stroke: .none, width: 0),
            P(.sleep, "M-59 28 Q-58 -5 -29 -7 Q-5 -5 0 25 Q2 52 -28 55 Q-57 54 -59 28 Z", fill: 0xFFF8EE, stroke: .outline, width: 3.2),
            P(.sleep, "M-49 27 Q-43 34 -37 27 M-25 27 Q-19 34 -13 27", stroke: .ink, width: 2.5),
            E(.sleep, -49, 39, 5, 3, fill: 0xF4B6B8, stroke: .none),
            E(.sleep, -13, 39, 5, 3, fill: 0xF4B6B8, stroke: .none),
            P(.sleep, "M-37 37 Q-30 33 -24 37 Q-30 42 -37 37 Z", fill: 0x433331, stroke: .ink, width: 1.6),
            E(.sleep, -52, 0, 10, 10, fill: 0x333238, stroke: .none),
            E(.sleep, -6, 0, 10, 10, fill: 0x333238, stroke: .none),
            P(.sleep, "M2 35 Q15 32 25 47 M-8 41 Q5 34 18 42", stroke: .ink, width: 5),
        ]
        return BuddyRig(
            pieces: p,
            pivots: [.legL: (-20, 79), .legR: (20, 79), .body: (0, 94), .armL: (-31, 48), .armR: (31, 48), .head: (0, 34)],
            full: BuddyRect(x: -80, y: -66, w: 160, h: 188), barBottom: nil, feet: (0, 111), sleepBottom: 69,
            zzz: [(0, -34, 12), (16, -50, 15), (36, -68, 19)],
            style: .init(armL: 1.0, armR: 1.0, armAmp: 0.5, alternate: true, kick: 0.2, bounce: 7, step: 7),
            heart: (0, 66, 12), face: (0, 5, 29, 20), brows: "M-23 -15 L-11 -11 M23 -15 L11 -11",
            hat: (0, -43, 30), sleepHat: (-30, -8, 26), neck: (0, 37), hand: (42, 77))
    }()
    static let pig: BuddyRig = {
        let p: [BuddyPiece] = [
            P(.tail, "M30 64 Q52 51 52 65 Q51 76 44 74 Q37 72 43 66 Q46 64 47 68", stroke: .color(0xEA8FA2), width: 6),
            P(.legL, "M-24 78 Q-33 92 -30 107 Q-24 114 -12 109 L-9 81 Z", fill: 0xF5AABB, stroke: .outline, width: 3.2),
            P(.legR, "M24 78 Q33 92 30 107 Q24 114 12 109 L9 81 Z", fill: 0xF5AABB, stroke: .outline, width: 3.2),
            P(.body, "M-30 32 Q-44 45 -39 77 Q-34 99 0 98 Q34 99 39 77 Q44 45 30 32 Z", fill: 0xFFC5CF, stroke: .outline, width: 3.2),
            P(.body, "M25 46 Q42 79 14 96 Q-9 102 -28 87 Q20 94 25 46 Z", fill: 0xF2A6B7, stroke: .none, width: 0),
            P(.armL, "M-31 46 Q-49 44 -50 67 Q-47 83 -30 79 L-23 57 Z", fill: 0xFFC5CF, stroke: .outline, width: 3.2),
            P(.armR, "M31 46 Q49 44 50 67 Q47 83 30 79 L23 57 Z", fill: 0xFFC5CF, stroke: .outline, width: 3.2),
            P(.head, "M-37 -19 L-45 -45 Q-32 -50 -20 -32 Q0 -43 20 -32 Q32 -50 45 -45 L37 -19 Q44 10 29 30 Q0 47 -29 30 Q-44 10 -37 -19 Z", fill: 0xFFC5CF, stroke: .outline, width: 3.2),
            P(.head, "M-41 -42 Q-30 -44 -25 -30 L-35 -27 Z M41 -42 Q30 -44 25 -30 L35 -27 Z", fill: 0xF08FA6, stroke: .none, width: 0),
            P(.head, "M29 18 Q13 36 -12 34 Q-31 30 -37 13 Q-33 39 0 41 Q32 39 37 13 Z", fill: 0xF2A6B7, stroke: .none, width: 0),
            E(.head, -15, -8, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, 15, -8, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, -16, -11, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            E(.head, 14, -11, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            P(.head, "M-20 -8 q5 -7 10 0 M10 -8 q5 -7 10 0", stroke: .ink, width: 2.6, show: .dance),
            E(.head, -29, 13, 7, 3, fill: 0xEF8EA5, stroke: .none),
            E(.head, 29, 13, 7, 3, fill: 0xEF8EA5, stroke: .none),
            E(.head, 0, 15, 16, 11, fill: 0xF190A7, stroke: .outline),
            E(.head, -6, 16, 2, 3, fill: 0xA94C65, stroke: .none),
            E(.head, 6, 16, 2, 3, fill: 0xA94C65, stroke: .none),
            P(.sleep, "M-30 30 Q-10 14 23 20 Q57 22 58 47 Q59 68 27 69 L-20 68 Q-49 64 -47 45 Z", fill: 0xFFC5CF, stroke: .outline, width: 3.2),
            P(.sleep, "M14 50 Q43 45 54 52 Q47 68 21 67 Q-5 68 -24 60 Q-6 64 14 50 Z", fill: 0xF2A6B7, stroke: .none, width: 0),
            P(.sleep, "M-59 28 Q-58 -5 -29 -7 Q-5 -5 0 25 Q2 52 -28 55 Q-57 54 -59 28 Z", fill: 0xFFC5CF, stroke: .outline, width: 3.2),
            P(.sleep, "M-49 27 Q-43 34 -37 27 M-25 27 Q-19 34 -13 27", stroke: .ink, width: 2.5),
            E(.sleep, -49, 39, 5, 3, fill: 0xEF8EA5, stroke: .none),
            E(.sleep, -13, 39, 5, 3, fill: 0xEF8EA5, stroke: .none),
            E(.sleep, -31, 39, 10, 7, fill: 0xF190A7, stroke: .outline),
            E(.sleep, -34, 40, 1.5, 2, fill: 0xA94C65, stroke: .none),
            E(.sleep, -27, 40, 1.5, 2, fill: 0xA94C65, stroke: .none),
        ]
        return BuddyRig(
            pieces: p,
            pivots: [.tail: (29, 64), .legL: (-20, 79), .legR: (20, 79), .body: (0, 94), .armL: (-30, 48), .armR: (30, 48), .head: (0, 34)],
            full: BuddyRect(x: -80, y: -66, w: 160, h: 188), barBottom: nil, feet: (0, 111), sleepBottom: 69,
            zzz: [(0, -34, 12), (16, -50, 15), (36, -68, 19)],
            style: .init(armL: 1.1, armR: 1.1, armAmp: 0.65, alternate: true, kick: 0.25, bounce: 10, step: 8),
            heart: (0, 66, 12), face: (0, 4, 30, 21), brows: "M-23 -15 L-11 -11 M23 -15 L11 -11",
            hat: (0, -40, 29), sleepHat: (-30, -8, 25), neck: (0, 38), hand: (44, 77))
    }()
    static let dragon: BuddyRig = {
        let p: [BuddyPiece] = [
            P(.tail, "M25 73 Q52 75 62 48 L67 62 L75 59 Q66 91 29 91 Z", fill: 0x48B9A8, stroke: .outline, width: 3.2),
            P(.tail, "M43 79 L47 67 L54 74 L59 58 L64 66", stroke: .color(0xF7D48A), width: 3),
            P(.legL, "M-22 78 Q-34 90 -29 108 Q-18 116 -10 108 L-9 81 Z", fill: 0x4FC2B0, stroke: .outline, width: 3.2),
            P(.legR, "M22 78 Q34 90 29 108 Q18 116 10 108 L9 81 Z", fill: 0x4FC2B0, stroke: .outline, width: 3.2),
            P(.body, "M-29 28 Q-42 48 -37 77 Q-30 99 0 99 Q30 99 37 77 Q42 48 29 28 Z", fill: 0x50C7B2, stroke: .outline, width: 3.2),
            P(.body, "M26 46 Q40 84 12 97 Q-10 103 -27 87 Q19 93 26 46 Z", fill: 0x329B93, stroke: .none, width: 0),
            P(.body, "M-16 44 Q0 38 16 44 Q23 77 0 92 Q-23 77 -16 44 Z", fill: 0xFFE4A1, stroke: .none, width: 0),
            P(.armL, "M-30 44 Q-53 37 -54 59 L-42 58 L-48 72 Q-36 76 -26 64 Z", fill: 0x45B5A9, stroke: .outline, width: 3.2),
            P(.armR, "M30 44 Q53 37 54 59 L42 58 L48 72 Q36 76 26 64 Z", fill: 0x45B5A9, stroke: .outline, width: 3.2),
            P(.head, "M-38 -16 Q-43 -42 -27 -44 Q-18 -45 -13 -35 Q0 -42 13 -35 Q18 -45 27 -44 Q43 -42 38 -16 Q43 10 29 28 Q0 44 -29 28 Q-43 10 -38 -16 Z", fill: 0x50C7B2, stroke: .outline, width: 3.2),
            P(.head, "M-28 -39 L-31 -58 Q-23 -63 -16 -39 M28 -39 L31 -58 Q23 -63 16 -39", fill: 0xFFE4A1, stroke: .outline, width: 3.2),
            P(.head, "M-17 -42 L-12 -51 L-5 -42 L0 -55 L7 -42 L13 -48 L18 -38", fill: 0xF5CE80, stroke: .none, width: 0),
            P(.head, "M30 15 Q12 36 -10 33 Q-29 30 -38 14 Q-31 40 0 40 Q32 38 38 12 Z", fill: 0x329B93, stroke: .none, width: 0),
            E(.head, -15, -4, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, 15, -4, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, -16, -7, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            E(.head, 14, -7, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            P(.head, "M-20 -4 q5 -7 10 0 M10 -4 q5 -7 10 0", stroke: .ink, width: 2.6, show: .dance),
            E(.head, -28, 15, 6, 3, fill: 0xF0A6A0, stroke: .none),
            E(.head, 28, 15, 6, 3, fill: 0xF0A6A0, stroke: .none),
            P(.head, "M-8 17 Q0 23 8 17", stroke: .ink, width: 2.2),
            P(.head, "M-24 21 Q-36 21 -45 28 M24 21 Q36 21 45 28", stroke: .color(0xD3A76A), width: 1.7),
            P(.sleep, "M-30 30 Q-10 14 23 20 Q57 22 58 47 Q59 68 27 69 L-20 68 Q-49 64 -47 45 Z", fill: 0x50C7B2, stroke: .outline, width: 3.2),
            P(.sleep, "M14 50 Q43 45 54 52 Q47 68 21 67 Q-5 68 -24 60 Q-6 64 14 50 Z", fill: 0x329B93, stroke: .none, width: 0),
            P(.sleep, "M-59 28 Q-58 -5 -29 -7 Q-5 -5 0 25 Q2 52 -28 55 Q-57 54 -59 28 Z", fill: 0x50C7B2, stroke: .outline, width: 3.2),
            P(.sleep, "M-49 27 Q-43 34 -37 27 M-25 27 Q-19 34 -13 27", stroke: .ink, width: 2.5),
            E(.sleep, -49, 39, 5, 3, fill: 0xF0A6A0, stroke: .none),
            E(.sleep, -13, 39, 5, 3, fill: 0xF0A6A0, stroke: .none),
            P(.sleep, "M-53 4 L-49 -13 L-39 3 M-19 -5 L-15 -20 L-5 1", fill: 0xFFE4A1, stroke: .outline, width: 3.2),
        ]
        return BuddyRig(
            pieces: p,
            pivots: [.tail: (27, 79), .legL: (-20, 79), .legR: (20, 79), .body: (0, 94), .armL: (-30, 46), .armR: (30, 46), .head: (0, 34)],
            full: BuddyRect(x: -82, y: -70, w: 164, h: 192), barBottom: nil, feet: (0, 111), sleepBottom: 69,
            zzz: [(0, -34, 12), (16, -50, 15), (36, -68, 19)],
            style: .init(armL: 1.5, armR: 1.5, armAmp: 0.7, alternate: true, kick: 0.3, bounce: 10, step: 9),
            heart: (0, 65, 12), face: (0, 5, 29, 21), brows: "M-23 -15 L-11 -11 M23 -15 L11 -11",
            hat: (0, -47, 27), sleepHat: (-30, -11, 25), neck: (0, 38), hand: (42, 69))
    }()
    static let eagle: BuddyRig = {
        let p: [BuddyPiece] = [
            P(.tail, "M-20 80 L-28 105 L-9 96 L0 112 L9 96 L28 105 L20 80 Z", fill: 0x815D48, stroke: .outline, width: 3.2),
            P(.legL, "M-18 84 L-18 102 Q-34 105 -32 111 Q-21 113 -15 108 Q-8 115 0 111 Q2 105 -10 103 L-9 84 Z", fill: 0xF6C45D, stroke: .outline, width: 3.2),
            P(.legR, "M18 84 L18 102 Q34 105 32 111 Q21 113 15 108 Q8 115 0 111 Q-2 105 10 103 L9 84 Z", fill: 0xF6C45D, stroke: .outline, width: 3.2),
            P(.body, "M-27 30 Q-42 49 -37 77 Q-31 98 0 99 Q31 98 37 77 Q42 49 27 30 Z", fill: 0x8C6048, stroke: .outline, width: 3.2),
            P(.body, "M27 49 Q37 81 13 96 Q-10 101 -28 87 Q19 92 27 49 Z", fill: 0x694835, stroke: .none, width: 0),
            P(.body, "M-17 51 Q0 43 17 51 Q20 77 0 91 Q-20 77 -17 51 Z", fill: 0xBD9272, stroke: .none, width: 0),
            P(.armL, "M-27 42 Q-56 34 -60 55 L-53 61 L-57 68 L-43 66 L-44 77 Q-28 77 -20 55 Z", fill: 0x8C6048, stroke: .outline, width: 3.2),
            P(.armL, "M-54 57 Q-40 58 -29 65", stroke: .color(0xB68265), width: 1.8),
            P(.armR, "M27 42 Q56 34 60 55 L53 61 L57 68 L43 66 L44 77 Q28 77 20 55 Z", fill: 0x8C6048, stroke: .outline, width: 3.2),
            P(.armR, "M54 57 Q40 58 29 65", stroke: .color(0xB68265), width: 1.8),
            P(.head, "M-39 -12 Q-37 -43 0 -43 Q37 -43 39 -12 Q42 18 25 32 Q0 45 -25 32 Q-42 18 -39 -12 Z", fill: 0xFFF7ED, stroke: .outline, width: 3.2),
            P(.head, "M-37 8 Q-27 33 0 39 Q27 33 37 8 Q33 37 0 40 Q-33 37 -37 8 Z", fill: 0xE5DCD5, stroke: .none, width: 0),
            P(.head, "M-34 -22 Q-28 -43 0 -43 Q26 -43 34 -22 Q15 -34 4 -25 Q-10 -37 -34 -22 Z", fill: 0xFFFFFF, stroke: .none, width: 0),
            E(.head, -17, -4, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, 17, -4, 5, 7, fill: 0x352B2B, stroke: .ink),
            E(.head, -18, -7, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            E(.head, 16, -7, 1.8, 2, fill: 0xFFFFFF, stroke: .none),
            P(.head, "M-22 -4 q5 -7 10 0 M12 -4 q5 -7 10 0", stroke: .ink, width: 2.6, show: .dance),
            E(.head, -30, 15, 6, 3, fill: 0xEAB0A0, stroke: .none),
            E(.head, 30, 15, 6, 3, fill: 0xEAB0A0, stroke: .none),
            P(.head, "M-10 12 Q0 9 10 12 L0 29 Z", fill: 0xF5C35D, stroke: .ink, width: 2),
            P(.head, "M-3 24 L3 24", stroke: .color(0xD89541), width: 1.7),
            P(.sleep, "M-30 30 Q-10 14 23 20 Q57 22 58 47 Q59 68 27 69 L-20 68 Q-49 64 -47 45 Z", fill: 0x8C6048, stroke: .outline, width: 3.2),
            P(.sleep, "M14 50 Q43 45 54 52 Q47 68 21 67 Q-5 68 -24 60 Q-6 64 14 50 Z", fill: 0x694835, stroke: .none, width: 0),
            P(.sleep, "M-59 28 Q-58 -5 -29 -7 Q-5 -5 0 25 Q2 52 -28 55 Q-57 54 -59 28 Z", fill: 0xFFF7ED, stroke: .outline, width: 3.2),
            P(.sleep, "M-49 27 Q-43 34 -37 27 M-25 27 Q-19 34 -13 27", stroke: .ink, width: 2.5),
            E(.sleep, -49, 39, 5, 3, fill: 0xEAB0A0, stroke: .none),
            E(.sleep, -13, 39, 5, 3, fill: 0xEAB0A0, stroke: .none),
            P(.sleep, "M-39 37 L-30 48 L-22 36 Z", fill: 0xF5C35D, stroke: .ink, width: 1.5),
            P(.sleep, "M11 27 Q40 19 48 42 Q27 51 11 42 Z", fill: 0x8C6048, stroke: .outline, width: 3.2),
        ]
        return BuddyRig(
            pieces: p,
            pivots: [.tail: (0, 85), .legL: (-18, 86), .legR: (18, 86), .body: (0, 94), .armL: (-27, 45), .armR: (27, 45), .head: (0, 34)],
            full: BuddyRect(x: -82, y: -66, w: 164, h: 188), barBottom: nil, feet: (0, 111), sleepBottom: 69,
            zzz: [(0, -34, 12), (16, -50, 15), (36, -68, 19)],
            style: .init(armL: 1.9, armR: 1.9, armAmp: 0.9, alternate: true, kick: 0.25, bounce: 11, step: 8),
            heart: (0, 66, 12), face: (0, 5, 30, 20), brows: "M-23 -15 L-11 -11 M23 -15 L11 -11",
            hat: (0, -43, 30), sleepHat: (-30, -8, 26), neck: (0, 38), hand: (48, 66))
    }()
}

// MARK: - Trang phục theo mùa lễ (không theo phím — giải MỘT lần lúc hiện bàn phím)

/// Mùa lễ: theme lễ đang dùng (Tết / Tết mai vàng, Giáng sinh / Giáng sinh tuyết, Halloween, Trung Thu) HOẶC
/// ngày rơi vào cửa sổ mùa. Âm lịch tra bảng nhúng 2026–2035 (không mạng).
enum BuddySeason: String, CaseIterable {
    case tet, christmas, halloween, midAutumn

    /// Theme lễ ⇒ mùa (theme thắng ngày).
    static func of(themeID: String?) -> BuddySeason? {
        switch themeID {
        case "tet", "tetMai": return .tet
        case "xmas", "xmasSnow": return .christmas
        case "halloween": return .halloween
        case "trungthu": return .midAutumn
        default: return nil
        }
    }

    /// Mùng 1 Tết (năm → (tháng, ngày) dương lịch), 2026–2035.
    /// LƯU Ý: bảng nhúng theo lịch âm Việt Nam (UTC+7) — cần đối chiếu nguồn chính thức trước khi phát hành.
    static let lunarNewYear: [Int: (Int, Int)] = [
        2026: (2, 17), 2027: (2, 6), 2028: (1, 26), 2029: (2, 13), 2030: (2, 3),
        2031: (1, 23), 2032: (2, 11), 2033: (1, 31), 2034: (2, 19), 2035: (2, 8),
    ]
    /// Rằm tháng Tám (Trung Thu), 2026–2035 — cùng lưu ý như trên.
    static let midAutumnDay: [Int: (Int, Int)] = [
        2026: (9, 25), 2027: (9, 15), 2028: (10, 3), 2029: (9, 22), 2030: (9, 12),
        2031: (10, 1), 2032: (9, 19), 2033: (9, 8), 2034: (9, 27), 2035: (9, 16),
    ]

    /// Số ngày từ 1/1/1970 (lịch Gregory) — hàm thuần, không phụ thuộc múi giờ.
    static func dayNumber(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let a = (14 - m) / 12
        let yy = y + 4800 - a
        let mm = m + 12 * a - 3
        let jdn = d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045
        return jdn - 2_440_588
    }

    /// Mùa theo ngày (năm, tháng, ngày) — Tết −10…+7 ngày, Giáng sinh 15–26/12, Halloween 25/10–1/11,
    /// Trung Thu ±5 ngày.
    static func of(year y: Int, month m: Int, day d: Int) -> BuddySeason? {
        let today = dayNumber(y, m, d)
        for yy in [y, y + 1] {   // Tết đầu năm sau có thể bắt đầu từ cuối tháng 1 — chỉ cần năm này + năm sau
            if let t = lunarNewYear[yy] {
                let n = dayNumber(yy, t.0, t.1)
                if today >= n - 10 && today <= n + 7 { return .tet }
            }
        }
        if m == 12 && d >= 15 && d <= 26 { return .christmas }
        if (m == 10 && d >= 25) || (m == 11 && d == 1) { return .halloween }
        if let t = midAutumnDay[y] {
            let n = dayNumber(y, t.0, t.1)
            if abs(today - n) <= 5 { return .midAutumn }
        }
        return nil
    }

    /// Theme lễ thắng; không thì theo ngày.
    static func resolve(themeID: String?, year: Int, month: Int, day: Int) -> BuddySeason? {
        of(themeID: themeID) ?? of(year: year, month: month, day: day)
    }
}

/// Trang phục: mảnh thêm (mũ, nơ, lồng đèn…) + đổi màu (áo dài đỏ ngày Tết). Hình là DỮ LIỆU như BuddyRig.
enum BuddyAccessory {
    static let santa: [BuddyPiece] = [
        BuddyPiece(.body, .path("M-17 0 Q-17 -16 -5 -22 Q10 -29 19 -14 Q11 -18 9 -8 L15 0 Z"), fill: 0xDE5263, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M2 -22 Q10 -25 19 -14 Q11 -18 9 -8 L15 0 L4 0 Q8 -12 2 -22 Z"), fill: 0xB93650, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M-11 -10 Q-10 -17 -5 -18"), fill: nil, alpha: 1, stroke: .color(0xFFB1BB), width: 2),
        BuddyPiece(.body, .path("M-16 -4 L15 -4 Q20 -4 20 1 Q20 6 15 6 L-16 6 Q-21 6 -21 1 Q-21 -4 -16 -4 Z"), fill: 0xFFF7ED, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M-17 2 Q0 5 17 1 L17 4 L-17 4 Z"), fill: 0xE4D8D5, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M16 -18 Q23 -21 25 -14 Q27 -7 20 -6 Q13 -6 13 -12 Q12 -16 16 -18 Z"), fill: 0xFFF7ED, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M20 -16 L22 -14"), fill: nil, alpha: 1, stroke: .color(0xFFFFFF), width: 2),
    ]
    static let witch: [BuddyPiece] = [
        BuddyPiece(.body, .path("M-22 0 Q0 -8 22 0 Q27 4 18 7 Q0 11 -20 6 Q-27 3 -22 0 Z"), fill: 0x695185, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M-15 0 Q-12 -14 -6 -23 Q-2 -31 12 -24 Q5 -25 4 -18 L14 0 Z"), fill: 0x8C72AF, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M-1 -25 Q4 -28 12 -24 Q5 -25 4 -18 L14 0 L5 0 Q0 -13 -1 -25 Z"), fill: 0x695185, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M-12 -6 L11 -6 L13 0 L-15 0 Z"), fill: 0xF5A65B, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M-3 -7 L4 -7 L4 0 L-3 0 Z"), fill: 0xF8D77B, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M-7 -16 L-5 -20"), fill: nil, alpha: 1, stroke: .color(0xC9AFE3), width: 2),
    ]
    static let pumpkin: [BuddyPiece] = [
        BuddyPiece(.body, .path("M-2 -19 L-3 -28 Q1 -31 4 -27 L3 -18 Z"), fill: 0x799656, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M3 -24 Q13 -32 15 -23 Q8 -19 3 -24 Z"), fill: 0xA9C879, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M0 -21 Q-15 -26 -18 -13 Q-22 1 -10 4 Q0 7 12 3 Q23 -1 18 -14 Q14 -25 0 -21 Z"), fill: 0xF5A65B, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M9 -20 Q18 -18 18 -9 Q20 3 9 4 Q15 -9 9 -20 Z"), fill: 0xD97B46, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M-7 -17 Q-11 -14 -11 -10"), fill: nil, alpha: 1, stroke: .color(0xFFDA91), width: 2.5),
        BuddyPiece(.body, .path("M-9 -7 Q-6 -13 -3 -7 Z M3 -7 Q6 -13 9 -7 Z M-7 -2 Q0 4 7 -2 Q0 0 -7 -2 Z"), fill: 0x563D3C, alpha: 1, stroke: .none, width: 3.2),
    ]
    static let khanDong: [BuddyPiece] = [
        BuddyPiece(.body, .path("M-18 0 L-18 -8 Q-17 -20 0 -20 Q17 -20 18 -8 L18 0 Q0 7 -18 0 Z"), fill: 0xDE5263, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M8 -18 Q17 -16 18 -8 L18 0 Q0 7 -18 0 L-18 -4 Q9 2 8 -18 Z"), fill: 0xB93650, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M-14 -9 Q0 -16 14 -9 M-14 -3 Q0 -9 14 -3"), fill: nil, alpha: 1, stroke: .color(0xF8D77B), width: 2),
        BuddyPiece(.body, .path("M-10 -13 L-6 -15"), fill: nil, alpha: 1, stroke: .color(0xFFABB6), width: 2),
    ]
    static let bow: [BuddyPiece] = [
        BuddyPiece(.body, .path("M0 0 Q-18 -17 -19 -6 L-19 6 Q-18 17 0 0 Q18 -17 19 -6 L19 6 Q18 17 0 0 Z"), fill: 0xDE5263, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M-18 7 L-3 0 L-7 7 Q-18 15 -18 7 Z M18 7 L3 0 L7 7 Q18 15 18 7 Z"), fill: 0xB93650, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M-12 -5 L-8 -3 M8 -3 L12 -5"), fill: nil, alpha: 1, stroke: .color(0xFFB1BB), width: 2),
        BuddyPiece(.body, .path("M-4 -4 Q0 -7 4 -4 L4 4 Q0 7 -4 4 Z"), fill: 0xF8D77B, alpha: 1, stroke: .outline, width: 3.2),
    ]
    static let pattern: [BuddyPiece] = [
        BuddyPiece(.body, .path("M0 4 Q9 9 0 14 Q-9 9 0 4 Z M-7 20 Q0 14 5 23 Q-4 29 -7 20 Z M7 31 Q14 36 7 41 Q0 36 7 31 Z"), fill: 0xF8D77B, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M0 9 L0 28 Q0 33 7 36"), fill: nil, alpha: 1, stroke: .color(0xF8D77B), width: 1.5),
    ]
    static let lantern: [BuddyPiece] = [
        BuddyPiece(.body, .path("M0 0 L13 -8 L18 1"), fill: nil, alpha: 1, stroke: .color(0x8B6655), width: 3.2),
        BuddyPiece(.body, .path("M18 -2 Q37 -2 37 17 Q37 36 18 36 Q-1 36 -1 17 Q-1 -2 18 -2 Z"), fill: 0xF8D77B, alpha: 0.16, stroke: .none, width: 0),
        BuddyPiece(.body, .path("M18 0 L22 10 L33 11 L25 19 L28 30 L18 24 L8 30 L11 19 L3 11 L14 10 Z"), fill: 0xDE5263, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M18 4 L21 13 L29 13 L23 18 L25 26 L18 21 L11 26 L13 18 L7 13 L15 13 Z"), fill: 0xF8D77B, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M18 9 L20 15 L18 20 L16 15 Z"), fill: 0xFFF0B3, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M18 25 L18 36 M14 34 L14 38 M22 34 L22 38"), fill: nil, alpha: 1, stroke: .color(0xF5A65B), width: 2),
    ]
    static let luckyMoney: [BuddyPiece] = [
        BuddyPiece(.body, .path("M-11 -8 L-10 -20 L10 -20 L11 -8 Z"), fill: 0xA9C879, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M-6 -16 L5 -16"), fill: nil, alpha: 1, stroke: .color(0xE7EFC7), width: 2),
        BuddyPiece(.body, .path("M-14 -11 Q0 -8 14 -11 L14 15 Q0 20 -14 15 Z"), fill: 0xDE5263, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M8 -10 L14 -11 L14 15 Q0 20 -14 15 L-14 11 Q8 16 8 -10 Z"), fill: 0xB93650, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M-14 -11 L0 -1 L14 -11"), fill: nil, alpha: 1, stroke: .color(0xF8D77B), width: 2),
        BuddyPiece(.body, .path("M0 1 L6 7 L0 13 L-6 7 Z"), fill: 0xF8D77B, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M19 -15 L19 -7 M15 -11 L23 -11"), fill: nil, alpha: 1, stroke: .color(0xF8D77B), width: 2),
    ]
    static let gift: [BuddyPiece] = [
        BuddyPiece(.body, .path("M-15 -6 L15 -6 L15 15 Q0 19 -15 15 Z"), fill: 0x83B9A4, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M8 -6 L15 -6 L15 15 Q0 19 -15 15 L-15 11 L8 11 Z"), fill: 0x5B9686, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M-16 -12 L16 -12 L16 -4 L-16 -4 Z"), fill: 0xA9D5BF, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M-3 -12 L3 -12 L3 16 L-3 16 Z"), fill: 0xF8D77B, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M0 -12 Q-17 -12 -10 -21 Q-4 -25 0 -12 Q4 -25 10 -21 Q17 -12 0 -12 Z"), fill: 0xDE5263, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M-10 -8 L-6 -8"), fill: nil, alpha: 1, stroke: .color(0xE6F4DC), width: 2),
    ]
    static let candy: [BuddyPiece] = [
        BuddyPiece(.body, .path("M-11 -7 Q-13 -27 0 -27 Q13 -27 11 -7"), fill: nil, alpha: 1, stroke: .color(0x8C72AF), width: 3.2),
        BuddyPiece(.body, .path("M-12 -12 L-16 -19 L-8 -21 L-5 -12 M5 -12 L7 -23 L15 -20 L13 -10"), fill: 0xF8D77B, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M-16 -10 Q0 -5 16 -10 L14 11 Q0 21 -14 11 Z"), fill: 0xF5A65B, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M9 -8 L16 -10 L14 11 Q0 21 -14 11 L-13 7 Q7 15 9 -8 Z"), fill: 0xD97B46, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M-10 -1 L-5 -6 L-2 -1 Z M2 -1 L5 -6 L10 -1 Z M-7 5 Q0 13 7 5 Q0 8 -7 5 Z"), fill: 0x563D3C, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M-11 -7 L-7 -6"), fill: nil, alpha: 1, stroke: .color(0xFFDA91), width: 2),
    ]
    static let mooncake: [BuddyPiece] = [
        BuddyPiece(.body, .path("M-15 -9 Q-20 -5 -16 0 Q-20 5 -14 8 Q-15 15 -8 15 Q-4 20 1 16 Q6 20 10 15 Q17 15 16 8 Q22 4 17 -1 Q20 -7 14 -10 Q13 -16 6 -15 Q0 -20 -6 -15 Q-13 -17 -15 -9 Z"), fill: 0xD99450, alpha: 1, stroke: .outline, width: 3.2),
        BuddyPiece(.body, .path("M-14 5 Q0 16 16 5 L16 9 Q17 15 10 15 Q6 20 1 16 Q-4 20 -8 15 Q-15 15 -14 8 Z"), fill: 0xB97245, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M-12 -7 Q0 -17 12 -7 L12 5 Q0 14 -12 5 Z"), fill: 0xF5C778, alpha: 1, stroke: .none, width: 3.2),
        BuddyPiece(.body, .path("M0 -9 Q8 -9 5 -3 Q12 1 5 5 Q0 12 -5 5 Q-12 1 -5 -3 Q-8 -9 0 -9 Z"), fill: nil, alpha: 1, stroke: .color(0xB97245), width: 2),
        BuddyPiece(.body, .path("M-8 -9 L-4 -10"), fill: nil, alpha: 1, stroke: .color(0xFFE6A8), width: 2),
    ]

    /// Place normalized 32-unit art using only a rig anchor. No work during animation.
    static func place(_ art: [BuddyPiece], _ part: BuddyPart, x: Double, y: Double, size: Double) -> [BuddyPiece] {
        let k = size / 32
        func f(_ v: Double) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), v) }
        return art.map { p in
            guard case .path(let d) = p.shape else { return p }
            let path = BuddySVG.parse(d).map { cmd -> String in
                switch cmd {
                case .move(let a, let b): return "M\(f(x + a * k)) \(f(y + b * k))"
                case .line(let a, let b): return "L\(f(x + a * k)) \(f(y + b * k))"
                case .quad(let a, let b, let c, let e): return "Q\(f(x + a * k)) \(f(y + b * k)) \(f(x + c * k)) \(f(y + e * k))"
                case .close: return "Z"
                }
            }.joined(separator: " ")
            return BuddyPiece(part, .path(path), fill: p.fill, alpha: p.alpha, stroke: p.stroke, width: p.width)
        }
    }
}

struct BuddyOutfit {
    var pieces: [BuddyPiece] = []
    var recolor: [UInt32: UInt32] = [:]
    static let red: UInt32 = 0xDE5263, gold: UInt32 = 0xF8D77B, white: UInt32 = 0xFFF7ED

    static func make(_ s: BuddySeason?, _ c: BuddyCharacter) -> BuddyOutfit {
        guard let s, let r = BuddyRig.rig(c) else { return BuddyOutfit() }
        var o = BuddyOutfit()
        let h = r.hat, sh = r.sleepHat
        // Sleep accessories use the sleep head's scale and stay in its local coordinate space.
        let sn = (x: sh.x + sh.size * 1.15, y: sh.y + sh.size * 1.8)
        switch s {
        case .tet:
            switch c {
            case .girl:
                o.recolor = [0xFFB3C7: red, 0xDF8EAB: 0xB93650, 0xFF6F91: gold, 0xFFF0F4: gold]
                o.pieces = BuddyAccessory.place(BuddyAccessory.pattern, .body, x: r.neck.x, y: r.neck.y + 10, size: h.size)
                    + BuddyAccessory.place(BuddyAccessory.pattern, .sleep, x: sh.x + sh.size * 2.4, y: sh.y + sh.size * 1.4, size: sh.size * 0.6)
            case .boy:
                o.recolor = [0x304563: red, 0x536B8C: 0xF18B95]
                o.pieces = khanDong(.head, h) + khanDong(.sleep, sh)
            case .cat, .chick, .shiba, .koi, .panda, .pig, .dragon, .eagle, .off:
                o.pieces = bow(.head, r.neck) + bow(.sleep, sn)
            }
        case .christmas: o.pieces = c == .koi ? bow(.head, r.neck) + bow(.sleep, sn) : santa(.head, h) + santa(.sleep, sh)
        case .halloween:
            o.pieces = c == .girl ? witch(.head, h) + witch(.sleep, sh) : pumpkin(.head, h) + pumpkin(.sleep, sh)
        case .midAutumn:
            let x = sh.x + sh.size * (c == .chick ? 2.3 : 0.9)
            let y = sh.y + sh.size * (c == .chick ? 1.6 : 2.1)
            o.pieces = lantern(r.hand) + BuddyAccessory.place(BuddyAccessory.lantern, .sleep, x: x, y: y, size: 24).map {
                BuddyPiece(.sleep, $0.shape, fill: $0.fill, alpha: $0.alpha, stroke: $0.stroke, width: $0.width, turn: (-70, x, y))
            }
        }
        return o
    }
    static func santa(_ part: BuddyPart, _ a: (x: Double, y: Double, size: Double)) -> [BuddyPiece] {
        BuddyAccessory.place(BuddyAccessory.santa, part, x: a.x, y: a.y, size: a.size)
    }
    static func witch(_ part: BuddyPart, _ a: (x: Double, y: Double, size: Double)) -> [BuddyPiece] {
        BuddyAccessory.place(BuddyAccessory.witch, part, x: a.x, y: a.y, size: a.size)
    }
    static func pumpkin(_ part: BuddyPart, _ a: (x: Double, y: Double, size: Double)) -> [BuddyPiece] {
        BuddyAccessory.place(BuddyAccessory.pumpkin, part, x: a.x, y: a.y, size: a.size)
    }
    static func khanDong(_ part: BuddyPart, _ a: (x: Double, y: Double, size: Double)) -> [BuddyPiece] {
        BuddyAccessory.place(BuddyAccessory.khanDong, part, x: a.x, y: a.y, size: a.size)
    }
    static func bow(_ part: BuddyPart, _ a: (x: Double, y: Double)) -> [BuddyPiece] {
        BuddyAccessory.place(BuddyAccessory.bow, part, x: a.x, y: a.y, size: 22)
    }
    static func lantern(_ hnd: (x: Double, y: Double)) -> [BuddyPiece] {
        BuddyAccessory.place(BuddyAccessory.lantern, .armR, x: hnd.x, y: hnd.y, size: 24)
    }
}

/// Geometry is constructed only for a requested holiday, then cached by each view.
enum BuddyProp {
    static func make(_ reaction: BuddyReaction, _ r: BuddyRig) -> [BuddyPiece] {
        let art: [BuddyPiece]
        switch reaction {
        case .luckyMoney: art = BuddyAccessory.luckyMoney
        case .gift: art = BuddyAccessory.gift
        case .candy: art = BuddyAccessory.candy
        case .mooncake: art = BuddyAccessory.mooncake
        default: return []
        }
        return BuddyAccessory.place(art, .body, x: r.heart.x, y: r.heart.y, size: r.heart.size * 2)
    }
}

// MARK: - Đường SVG rút gọn

/// M/m L/l H/h V/v Q/q Z/z — đủ cho bảng hình. Hàm thuần (Android y hệt).
enum BuddySVG {
    enum Cmd: Equatable {
        case move(Double, Double), line(Double, Double), quad(Double, Double, Double, Double), close
    }

    /// Mọi số trong chuỗi (theo thứ tự).
    static func numbers(_ s: String) -> [Double] {
        var out: [Double] = []
        var cur = ""
        func flush() { if let v = Double(cur) { out.append(v) }; cur = "" }
        for ch in s {
            if ch.isNumber || ch == "." { cur.append(ch) }
            else if ch == "-" { flush(); cur = "-" }
            else { flush() }
        }
        flush()
        return out
    }

    /// Lệnh tuyệt đối.
    static func parse(_ s: String) -> [Cmd] {
        var out: [Cmd] = []
        var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0
        var cmd: Character = "M"
        var nums: [Double] = []
        func emit() {
            var i = 0
            let rel = cmd.isLowercase
            let c = Character(cmd.uppercased())
            func take(_ n: Int) -> [Double]? { guard i + n <= nums.count else { return nil }; defer { i += n }; return Array(nums[i..<(i + n)]) }
            switch c {
            case "Z":
                out.append(.close); x = sx; y = sy
            case "M":
                var first = true
                while let v = take(2) {
                    x = rel ? x + v[0] : v[0]; y = rel ? y + v[1] : v[1]
                    if first { out.append(.move(x, y)); sx = x; sy = y; first = false } else { out.append(.line(x, y)) }
                }
            case "L":
                while let v = take(2) { x = rel ? x + v[0] : v[0]; y = rel ? y + v[1] : v[1]; out.append(.line(x, y)) }
            case "H":
                while let v = take(1) { x = rel ? x + v[0] : v[0]; out.append(.line(x, y)) }
            case "V":
                while let v = take(1) { y = rel ? y + v[0] : v[0]; out.append(.line(x, y)) }
            case "Q":
                while let v = take(4) {
                    let cx = rel ? x + v[0] : v[0], cy = rel ? y + v[1] : v[1]
                    x = rel ? x + v[2] : v[2]; y = rel ? y + v[3] : v[3]
                    out.append(.quad(cx, cy, x, y))
                }
            default: break
            }
        }
        var token = ""
        var started = false
        for ch in s {
            if "MmLlHhVvQqZz".contains(ch) {
                if started { nums = numbers(token); emit() }
                cmd = ch; token = ""; started = true
            } else { token.append(ch) }
        }
        if started { nums = numbers(token); emit() }
        return out
    }
}
