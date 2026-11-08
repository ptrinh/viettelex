// Theme "Gõ mõ" + "Kính màu" (11/2026, Plus): hiệu ứng Công đức (merit), Nắng qua kính (sunlight), dáng phím ô kính
// ("keyShape":"glass" — GlassKeys). Song sinh android/keyboard/.../MeritGlass.kt (hàm thuần CÙNG SỐ — test chéo hai bên).
//
// Tôn trọng người có đạo: KHÔNG hình tượng Phật / Chúa / Đức Mẹ / thánh / thần linh, không kinh văn — chỉ biểu tượng
// (mõ gỗ, hoa sen, chuông, ô kính màu, tia nắng, ánh nến). Chữ "+1 công đức" là câu đùa vui dân gian khi gõ mõ.
//
// Hiệu năng (như mọi hiệu ứng phím): kiểu khác ⇒ overlay không giữ gì từ file này (nil). Bật: layer dựng lười theo pool,
// animation gắn MỘT lần lúc dựng, bấm chỉ đổi vị trí / path + beginTime. Bộ đếm công đức = một Int trong RAM, ghi App Group
// tối đa mỗi `MeritCounter.persistInterval` giây + lúc ẩn bàn phím. Chỉ lưu SỐ ĐẾM (không lưu phím / chữ).
import UIKit

/// 0xRRGGBB → UIColor (riêng file này; KeyEffects có bản private).
private func meritColor(_ v: UInt32) -> UIColor {
    UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

// MARK: - Công đức (theme Gõ mõ)

/// "Công đức": mỗi phím một nhãn "+1 công đức" vàng dịu bay lên từ phím rồi mờ (~0,9 s). Tối đa `cap` nhãn cùng lúc
/// (pool xoay vòng — gõ nhanh hơn thì nhãn cũ nhất được dùng lại). Hàm thuần — Android MeritFx cùng số.
enum MeritFx {
    static let duration = 0.9
    /// Quãng bay lên (pt).
    static let rise = 44.0
    static let cap = 5
    static let fontSize = 13.0
    /// Vàng dịu + viền nâu sẫm mảnh (đọc được trên phím sáng lẫn tối).
    static let color: UInt32 = 0xF2C14E
    static let edge: UInt32 = 0x3A2200
    static let fadeIn = 0.12
    static let fadeOutFrom = 0.5
    /// Khung nhãn (pt) — để kẹp trong bàn phím.
    static let labelWidth = 110.0
    static let labelHeight = 18.0
    /// Nhãn đếm trên phím cách.
    static let counterFont = 10.0
    static let counterAlpha = 0.8

    /// Độ mờ sau `t` giây: lên trong `fadeIn`, giữ, tắt tuyến tính từ `fadeOutFrom` tới `duration`.
    static func alpha(_ t: Double) -> Double {
        guard t >= 0, t < duration else { return 0 }
        if t < fadeIn { return t / fadeIn }
        if t < fadeOutFrom { return 1 }
        return 1 - (t - fadeOutFrom) / (duration - fadeOutFrom)
    }

    /// Đã bay lên bao nhiêu pt sau `t` giây (easeOut, ≥ 0).
    static func lift(_ t: Double) -> Double {
        let u = Swift.min(Swift.max(t / duration, 0), 1)
        return rise * (1 - (1 - u) * (1 - u))
    }

    /// Lệch ngang nhẹ theo lần bấm: −6, 0, +6 pt.
    static func drift(_ seed: Int) -> Double { Double(((seed % 3) + 3) % 3 - 1) * 6 }

    /// Tâm nhãn lúc xuất phát (toạ độ overlay): mép trên phím, kẹp sao cho cả đường bay nằm trong khung `b`.
    static func origin(keyMidX: Double, keyTop: Double, bounds b: (x: Double, y: Double, w: Double, h: Double))
        -> (x: Double, y: Double) {
        let hw = labelWidth / 2 + 8, hh = labelHeight / 2 + 1
        let x = Swift.min(Swift.max(keyMidX, b.x + hw), Swift.max(b.x + b.w - hw, b.x + hw))
        let y = Swift.min(Swift.max(keyTop, b.y + rise + hh), Swift.max(b.y + b.h - hh, b.y + rise + hh))
        return (x, y)
    }

    /// Nhóm nghìn: 1234 ⇒ "1.234" (vi) / "1,234" (en). Số âm ⇒ "0".
    static func grouped(_ n: Int, separator: String) -> String {
        guard n > 0 else { return "0" }
        let s = String(n)
        var out = ""
        for (i, c) in s.enumerated() {
            if i > 0 && (s.count - i) % 3 == 0 { out += separator }
            out.append(c)
        }
        return out
    }

    /// "Công đức hôm nay: 1.234" / "Merit today: 1,234".
    static func counterText(_ n: Int, english: Bool = L10n.isEnglish) -> String {
        L("Công đức hôm nay") + ": " + grouped(n, separator: english ? "," : ".")
    }

    static var floatText: String { L("+1 công đức") }
}

/// Bộ đếm công đức TRONG NGÀY (giờ địa phương, qua nửa đêm về 0). Thuần — giờ / ngày truyền vào (test được).
/// `press` trả true khi nên ghi xuống (lần đầu, rồi tối đa mỗi `persistInterval` giây); ẩn bàn phím ⇒ `takeDirty`.
struct MeritCounter: Equatable {
    static let persistInterval = 5.0
    /// Khoá App Group (Android: prefs ime_state cùng tên). Chỉ hai số — không sao lưu (số liệu cục bộ như trạng thái IME).
    static let dayKey = "meritDay"
    static let countKey = "meritCount"

    private(set) var day: Int
    private(set) var count: Int
    private(set) var dirty = false
    private var lastPersist = -Double.greatestFiniteMagnitude

    init(day: Int = Int.min, count: Int = 0) { self.day = day; self.count = max(0, count) }

    /// Số ngày địa phương (0 = 01/01/1970) của thời điểm `epoch` (giây) với lệch múi giờ `utcOffset` (giây).
    static func dayIndex(epoch: Double, utcOffset: Int) -> Int {
        Int(((epoch + Double(utcOffset)) / 86_400).rounded(.down))
    }

    /// Công đức của ngày `d` (ngày khác ngày đã đếm ⇒ 0).
    func today(_ d: Int) -> Int { d == day ? count : 0 }

    /// Một phím vào ngày `d`, lúc `t` (giây máy, đơn điệu). true ⇒ ghi ngay.
    mutating func press(day d: Int, at t: Double) -> Bool {
        if d != day { day = d; count = 0 }
        count += 1
        dirty = true
        guard t - lastPersist >= Self.persistInterval else { return false }
        lastPersist = t
        dirty = false
        return true
    }

    /// Còn số chưa ghi? (ẩn bàn phím ⇒ ghi nốt). Gọi xong coi như đã ghi.
    mutating func takeDirty() -> Bool {
        defer { dirty = false }
        return dirty
    }
}

/// Nơi lưu bộ đếm (App Group) — KeyboardView đặt khi kiểu là Công đức; test truyền kho giả.
struct MeritStore {
    let load: () -> (day: Int, count: Int)
    let save: (_ day: Int, _ count: Int) -> Void

    static func defaults(_ d: UserDefaults?) -> MeritStore {
        MeritStore(load: {
            guard let d, d.object(forKey: MeritCounter.dayKey) != nil else { return (Int.min, 0) }
            return (d.integer(forKey: MeritCounter.dayKey), d.integer(forKey: MeritCounter.countKey))
        }, save: { day, count in
            d?.set(day, forKey: MeritCounter.dayKey)
            d?.set(count, forKey: MeritCounter.countKey)
        })
    }
}

// MARK: - Nắng qua kính (theme Kính màu)

/// "Nắng qua kính": bấm ⇒ ô vừa bấm sáng lên như nắng xuyên qua kính (ô quanh sáng nhẹ hơn) + vài vệt tia nắng chéo từ
/// mép trên xuống phím, lên `rise` rồi tắt (1−u)² trong `duration`. Gõ dồn (ComboMeter ≥ `candleLevel`) ⇒ ánh nến ấm ở
/// mép dưới bập bùng CHẬM (CandleFlicker: ≤ 3 lần đổi độ sáng mỗi giây, đổi mượt — không nhấp nháy). Thuần — Android cùng số.
enum SunlightFx {
    static let duration = 0.7
    static let rise = 0.08
    /// Độ đục lớp nắng trên ô vừa bấm / ô quanh.
    static let peak = 0.38
    static let neighbor = 0.16
    static let pitchX = 1.12
    static let pitchY = 1.25
    /// Nắng vàng nhạt.
    static let light: UInt32 = 0xFFF1C9
    static let cornerFactor = 0.18
    /// Tia nắng: góc lệch so với phương thẳng đứng (nắng chiếu từ trên-trái xuống-phải).
    static let beamAngle = 0.35
    static let beamOffsets = [-0.3, 0.05, 0.35]
    static let beamHalf = [0.12, 0.18, 0.10]
    static let beamSpread = 2.2
    static let beamWeights = [0.8, 1.0, 0.6]
    static let beamPeak = 0.2
    static var beams: Int { beamOffsets.count }
    /// Số chùm xoay vòng.
    static let pool = 4

    // Ánh nến khi gõ dồn.
    static let candleLevel = 2
    /// ≥ 0,34 s giữa hai lần đổi độ sáng ⇒ ≤ 3 lần / giây (an toàn cảm quang, không nhấp nháy).
    static let candleMinInterval = 0.34
    static let candleLevels = [0.34, 0.24, 0.40, 0.28]
    static let candleRamp = 0.3
    static let candleHold = 1.0
    static let candleFade = 0.5
    static let candleBand = 22.0
    static let candleColor: UInt32 = 0xFFB347

    struct Pane: Equatable { var x: Double; var y: Double; var w: Double; var h: Double; var level: Double }

    /// Đường bao 0…1 sau `dt` giây: lên tuyến tính `rise`, tắt (1−u)².
    static func envelope(_ dt: Double) -> Double {
        guard dt >= 0, dt < duration else { return 0 }
        if dt < rise { return dt / rise }
        let u = (dt - rise) / (duration - rise)
        return (1 - u) * (1 - u)
    }

    /// Ô vừa bấm (đúng khung phím, `peak`) + 4 ô quanh (trái / phải / trên / dưới theo bước phím, `neighbor`).
    static func panes(cx: Double, cy: Double, w: Double, h: Double) -> [Pane] {
        [Pane(x: cx, y: cy, w: w, h: h, level: peak),
         Pane(x: cx - w * pitchX, y: cy, w: w, h: h, level: neighbor),
         Pane(x: cx + w * pitchX, y: cy, w: w, h: h, level: neighbor),
         Pane(x: cx, y: cy - h * pitchY, w: w, h: h, level: neighbor),
         Pane(x: cx, y: cy + h * pitchY, w: w, h: h, level: neighbor)]
    }

    /// Tia `i`: tứ giác [x0,y0, x1,y1, x2,y2, x3,y3] từ mép trên `top` (rộng) xuống mép trên phím `keyTop` (hẹp).
    static func beam(_ i: Int, cx: Double, keyTop: Double, w: Double, top: Double) -> [Double] {
        let xk = cx + beamOffsets[i] * w, hk = beamHalf[i] * w, ht = hk * beamSpread
        let xt = xk - tan(beamAngle) * Swift.max(keyTop - top, 0)
        return [xt - ht, top, xt + ht, top, xk + hk, keyTop, xk - hk, keyTop]
    }
}

/// Ánh nến bập bùng: mỗi lần đổi độ sáng chuyển MƯỢT (`candleRamp`), giữ, không gõ nữa thì tắt dần. Cổng thời gian ⇒
/// ≤ 3 lần đổi mỗi giây. Thuần — Android CandleFlicker cùng số.
struct CandleFlicker: Equatable {
    private(set) var last = -Double.greatestFiniteMagnitude
    private(set) var from = 0.0
    private(set) var target = 0.0
    private(set) var changes = 0

    /// Độ sáng sau `dt` giây kể từ lần đổi (từ `from` tới `to`).
    static func envelope(_ dt: Double, from: Double, to: Double) -> Double {
        if dt < 0 { return from }
        if dt < SunlightFx.candleRamp {
            let u = dt / SunlightFx.candleRamp
            return from + (to - from) * u * u * (3 - 2 * u)
        }
        if dt < SunlightFx.candleHold { return to }
        if dt < SunlightFx.candleHold + SunlightFx.candleFade {
            return to * (1 - (dt - SunlightFx.candleHold) / SunlightFx.candleFade)
        }
        return 0
    }

    func value(at t: Double) -> Double {
        last == -Double.greatestFiniteMagnitude ? 0 : Self.envelope(t - last, from: from, to: target)
    }

    /// Một phím lúc `t` ở mức combo `level`: được đổi ⇒ độ sáng đích mới; không ⇒ nil.
    mutating func press(at t: Double, level: Int) -> Double? {
        guard level >= SunlightFx.candleLevel, t - last >= SunlightFx.candleMinInterval else { return nil }
        from = value(at: t)
        target = SunlightFx.candleLevels[changes % SunlightFx.candleLevels.count]
        last = t
        changes += 1
        return target
    }

    mutating func reset() { self = CandleFlicker() }
}

// MARK: - Dáng phím ô kính (theme Kính màu)

/// "keyShape":"glass": mỗi phím chữ một ô kính màu (ruby, lam ngọc, lục bảo, hổ phách) xếp so le theo hàng QWERTY, viền
/// chì gần đen dày + gradient trong nhẹ (sáng trên, sẫm dưới); phím chức năng = kính khói (fn), Enter hành động = màu nhấn,
/// số / ký hiệu = "key" của theme. iOS: ảnh 9-slice tí hon dựng MỘT lần mỗi bảng màu (cache) — skin của KeyButton như
/// PixelKeys. Thuần (màu / chỉ số ô / độ dày chì) — Android GlassKeys cùng số.
enum GlassKeys {
    static let shape = "glass"
    /// Ruby, lam ngọc, lục bảo, hổ phách — đủ sẫm cho chữ kem (tương phản ≥ 4,5 cả ở dải sáng trên — test chốt).
    static let panes: [UInt32] = [0x8E1B2E, 0x1E4596, 0x0F5C40, 0x7A4A00]
    static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    /// Chì khi theme không đặt "border".
    static let lead: UInt32 = 0x0B0A0C
    /// Trộn trắng ở mép trên (gradient trong) / đen ở mép dưới.
    static let highlight = 0.10
    static let shade = 0.14
    /// Ô đang đè: sáng hơn (trộn trắng).
    static let pressedLift = 0.22
    /// Độ dày chì = cao phím × leadFactor, tối thiểu minLead.
    static let leadFactor = 0.06
    static let minLead = 2.0

    /// Ô màu của chữ `label` (không phân biệt hoa thường): (cột + 2·hàng) mod 4 theo hàng QWERTY ⇒ ô kề nhau (ngang lẫn
    /// dọc) khác màu. Ký tự khác: mã Unicode mod 4. Rỗng ⇒ 0.
    static func paneIndex(_ label: String) -> Int {
        let s = label.lowercased()
        guard let ch = s.unicodeScalars.first else { return 0 }
        for (r, row) in rows.enumerated() {
            if let c = row.unicodeScalars.firstIndex(of: ch) {
                return (row.unicodeScalars.distance(from: row.unicodeScalars.startIndex, to: c) + 2 * r) % panes.count
            }
        }
        return Int(ch.value % UInt32(panes.count))
    }

    static func paneColor(_ label: String) -> UInt32 { panes[paneIndex(label)] }

    /// Trộn `c` về phía `d` một phần `t` (0xRRGGBB, làm tròn).
    static func mix(_ c: UInt32, _ d: UInt32, _ t: Double) -> UInt32 {
        func ch(_ sh: UInt32) -> UInt32 {
            let a = Double((c >> sh) & 0xFF), b = Double((d >> sh) & 0xFF)
            return UInt32((a + (b - a) * t).rounded()) << sh
        }
        return ch(16) | ch(8) | ch(0)
    }

    static func top(_ c: UInt32) -> UInt32 { mix(c, 0xFFFFFF, highlight) }
    static func pressed(_ c: UInt32) -> UInt32 { mix(c, 0xFFFFFF, pressedLift) }
    static func leadWidth(keyHeight h: Double) -> Double { Swift.max(minLead, h * leadFactor) }

    // iOS: ảnh 9-slice (px). Cao `imageH` px ⇒ hệ số = cao phím / imageH (≈ 0,5 pt / px trên iPhone).
    static let imageW = 60
    static let imageH = 80
    static let radius = 10.0
    static let slice = [14, 14, 14, 14]

    static func hex(_ c: RGBA) -> UInt32 {
        func q(_ v: Double) -> UInt32 { UInt32((Swift.min(Swift.max(v, 0), 1) * 255).rounded()) }
        return q(c.r) << 16 | q(c.g) << 8 | q(c.b)
    }

    /// Ảnh một ô: viền chì, mặt kính, gradient trong. `pressed` ⇒ mặt sáng hơn.
    static func image(fill: UInt32, lead: RGBA, pressed: Bool) -> CGImage? {
        let w = imageW, h = imageH
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let outer = CGRect(x: 0.5, y: 0.5, width: CGFloat(w) - 1, height: CGFloat(h) - 1)
        let lw = CGFloat(leadWidth(keyHeight: Double(h)))
        ctx.setFillColor(lead.ui.cgColor)
        ctx.addPath(CGPath(roundedRect: outer, cornerWidth: CGFloat(radius), cornerHeight: CGFloat(radius), transform: nil))
        ctx.fillPath()
        let inner = outer.insetBy(dx: lw, dy: lw)
        let ir = max(CGFloat(radius) - lw, 2)
        let face = pressed ? Self.pressed(fill) : fill
        let innerPath = CGPath(roundedRect: inner, cornerWidth: ir, cornerHeight: ir, transform: nil)
        ctx.addPath(innerPath)
        ctx.setFillColor(meritColor(face).cgColor)
        ctx.fillPath()
        // Gradient trong: trắng mờ ở trên → trong suốt (55 %) → đen mờ ở đáy.
        let colors = [UIColor(white: 1, alpha: highlight).cgColor, UIColor(white: 1, alpha: 0).cgColor,
                      UIColor(white: 0, alpha: shade).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
            ctx.saveGState()
            ctx.addPath(innerPath)
            ctx.clip()
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: inner.minY), end: CGPoint(x: 0, y: inner.maxY), options: [])
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    nonisolated(unsafe) private static var cache: [String: LoadedThemeAssets.Skin] = [:]
    static func skin(fill: UInt32, lead: RGBA) -> LoadedThemeAssets.Skin? {
        let k = String(format: "%06X|%06X|%.3f", fill, hex(lead), lead.a)
        if let s = cache[k] { return s }
        guard let n = image(fill: fill, lead: lead, pressed: false), let p = image(fill: fill, lead: lead, pressed: true)
        else { return nil }
        if cache.count > 24 { cache.removeAll() }
        let s = LoadedThemeAssets.Skin(normal: n, pressed: p, insets: slice, srcH: imageH)
        cache[k] = s
        return s
    }

    /// Vai phím → skin: a–z = ô màu theo chữ; "default" (số / ký hiệu) = "key"; chức năng = "fn"; Enter hành động = nhấn.
    static func skins(_ p: KeyboardPalette) -> [String: LoadedThemeAssets.Skin] {
        let lead = p.keyBorder.map { $0.a > 0 ? $0 : RGBA(hex: Self.lead) } ?? RGBA(hex: Self.lead)
        guard let key = skin(fill: hex(p.keyFill), lead: lead), let fn = skin(fill: hex(p.fnFill), lead: lead),
              let act = skin(fill: hex(p.accent), lead: lead) else { return [:] }
        var out: [String: LoadedThemeAssets.Skin] = [:]
        for r in ThemeAssetPlan.roles {
            if ThemeAssetSpec.letterKeys.contains(r) {
                out[r] = skin(fill: paneColor(r), lead: lead) ?? key
            } else {
                out[r] = r == "default" ? key : fn
            }
        }
        out[PixelKeys.actionReturnRole] = act
        return out
    }

    /// Bộ "tệp đã nạp" có skin ô kính, giữ phông / ảnh nền / tiền cảnh của bộ tải về (nếu có).
    static func assets(over base: LoadedThemeAssets?, palette p: KeyboardPalette) -> LoadedThemeAssets {
        let sig = "glass|" + [p.keyFill, p.fnFill, p.accent, p.keyBorder ?? .black].map {
            String(format: "%.4f,%.4f,%.4f,%.4f", $0.r, $0.g, $0.b, $0.a)
        }.joined(separator: ";")
        return LoadedThemeAssets(signature: (base?.signature ?? "") + "|" + sig, font: base?.font, skins: skins(p),
                                 backgroundURL: base?.backgroundURL, foregroundURL: base?.foregroundURL)
    }
}

// MARK: - Lớp vẽ trong KeyEffectOverlay

/// Công đức: pool `MeritFx.cap` CATextLayer (dựng lười; animation gắn MỘT lần, bấm chỉ đặt vị trí + beginTime) + nhãn
/// đếm trên phím cách (một CATextLayer, chỉ đổi chữ khi số đổi).
final class MeritLayers {
    private weak var host: CALayer?
    private(set) var labels: [CATextLayer] = []
    private var pool = KeyEffectPool(capacity: MeritFx.cap)
    private(set) var seq = 0
    private(set) var counterLayer: CATextLayer?
    private var shownCount = -1
    private static let animBegin: CFTimeInterval = 1e-3

    init(host: CALayer) { self.host = host }

    func fire(key r: CGRect, bounds b: CGRect, now: CFTimeInterval) {
        let slot = pool.next()
        let l: CATextLayer
        if slot < labels.count { l = labels[slot] } else { l = make(); labels.append(l) }
        let o = MeritFx.origin(keyMidX: Double(r.midX), keyTop: Double(r.size == .zero ? r.midY : r.minY),
                               bounds: (Double(b.minX), Double(b.minY), Double(b.width), Double(b.height)))
        l.position = CGPoint(x: o.x + MeritFx.drift(seq), y: o.y)
        l.beginTime = now
        l.isHidden = false
        seq += 1
    }

    private func make() -> CATextLayer {
        let l = CATextLayer()
        l.bounds = CGRect(x: 0, y: 0, width: MeritFx.labelWidth, height: MeritFx.labelHeight)
        l.contentsScale = UIScreen.main.scale
        l.alignmentMode = .center
        l.string = Self.text(MeritFx.floatText, size: MeritFx.fontSize, bold: true)
        l.opacity = 0
        l.isHidden = true
        let steps = 12
        let lift = CAKeyframeAnimation(keyPath: "transform.translation.y")
        lift.values = (0...steps).map { -MeritFx.lift(MeritFx.duration * Double($0) / Double(steps)) }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = (0...steps).map { MeritFx.alpha(MeritFx.duration * Double($0) / Double(steps) * 0.9999) }
        let times = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        lift.keyTimes = times
        fade.keyTimes = times
        let g = CAAnimationGroup()
        g.animations = [lift, fade]
        g.duration = MeritFx.duration
        g.beginTime = Self.animBegin
        g.fillMode = .both
        g.isRemovedOnCompletion = false
        l.add(g, forKey: "fx")
        host?.addSublayer(l)
        return l
    }

    /// Chữ vàng viền nâu sẫm (stroke âm = tô + viền) — không bóng (khỏi offscreen pass).
    static func text(_ s: String, size: Double, bold: Bool) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: bold ? UIFont.boldSystemFont(ofSize: CGFloat(size)) : UIFont.systemFont(ofSize: CGFloat(size), weight: .semibold),
            .foregroundColor: meritColor(MeritFx.color),
            .strokeColor: meritColor(MeritFx.edge),
            .strokeWidth: -3.0,
        ])
    }

    /// Nhãn đếm ở góc trên-trái phím cách (`anchor`, toạ độ overlay); nil ⇒ ẩn (bàn emoji / chưa layout).
    func showCounter(_ n: Int, anchor: CGRect?) {
        guard let a = anchor, a.width > 40, a.height > 16 else { counterLayer?.isHidden = true; return }
        let l = counterLayer ?? {
            let t = CATextLayer()
            t.contentsScale = UIScreen.main.scale
            t.alignmentMode = .left
            t.opacity = Float(MeritFx.counterAlpha)
            t.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()]
            host?.addSublayer(t)
            counterLayer = t
            return t
        }()
        let f = CGRect(x: a.minX + 6, y: a.minY + 2, width: max(a.width * 0.62, 40), height: CGFloat(MeritFx.counterFont) + 4)
        if l.frame != f { l.frame = f }
        if n != shownCount {
            shownCount = n
            l.string = Self.text(MeritFx.counterText(n), size: MeritFx.counterFont, bold: false)
        }
        l.isHidden = false
    }

    func remove() {
        for l in labels { l.removeFromSuperlayer() }
        labels.removeAll()
        counterLayer?.removeFromSuperlayer()
        counterLayer = nil
        shownCount = -1
    }
}

/// Nắng qua kính: pool `SunlightFx.pool` chùm (lớp nắng ô vừa bấm + lớp ô quanh + `beams` tia) — animation mờ dựng MỘT lần,
/// bấm chỉ đặt path + beginTime. Ánh nến mép dưới: MỘT CAGradientLayer dựng lười ở lần gõ dồn đầu tiên.
final class SunlightLayers {
    final class Burst {
        let root = CALayer()
        let strong = CAShapeLayer()
        let soft = CAShapeLayer()
        var rays: [CAShapeLayer] = []
    }
    private weak var host: CALayer?
    private(set) var bursts: [Burst] = []
    private var pool = KeyEffectPool(capacity: SunlightFx.pool)
    private var combo = ComboMeter()
    private(set) var candle = CandleFlicker()
    private(set) var candleLayer: CAGradientLayer?
    private static let animBegin: CFTimeInterval = 1e-3

    init(host: CALayer) { self.host = host }

    func fire(key r: CGRect, bounds b: CGRect, now: CFTimeInterval, media: CFTimeInterval) {
        let key = r.size == .zero
            ? CGRect(x: r.minX - KeyEffectOverlay.defaultKeySize.width / 2, y: r.minY - KeyEffectOverlay.defaultKeySize.height / 2,
                     width: KeyEffectOverlay.defaultKeySize.width, height: KeyEffectOverlay.defaultKeySize.height) : r
        let slot = pool.next()
        let bu: Burst
        if slot < bursts.count { bu = bursts[slot] } else { bu = make(); bursts.append(bu) }
        let ps = SunlightFx.panes(cx: Double(key.midX), cy: Double(key.midY), w: Double(key.width), h: Double(key.height))
        func rr(_ p: SunlightFx.Pane) -> CGPath {
            let rect = CGRect(x: p.x - p.w / 2, y: p.y - p.h / 2, width: p.w, height: p.h)
            let c = CGFloat(SunlightFx.cornerFactor) * min(rect.width, rect.height)
            return CGPath(roundedRect: rect, cornerWidth: c, cornerHeight: c, transform: nil)
        }
        bu.strong.path = rr(ps[0])
        let soft = CGMutablePath()
        for p in ps.dropFirst() { soft.addPath(rr(p)) }
        bu.soft.path = soft
        for (i, ray) in bu.rays.enumerated() {
            let q = SunlightFx.beam(i, cx: Double(key.midX), keyTop: Double(key.minY), w: Double(key.width), top: Double(b.minY))
            let p = CGMutablePath()
            p.move(to: CGPoint(x: q[0], y: q[1]))
            p.addLine(to: CGPoint(x: q[2], y: q[3]))
            p.addLine(to: CGPoint(x: q[4], y: q[5]))
            p.addLine(to: CGPoint(x: q[6], y: q[7]))
            p.closeSubpath()
            ray.path = p
        }
        bu.root.beginTime = now
        bu.root.isHidden = false
        // Gõ dồn ⇒ ánh nến mép dưới đổi độ sáng (≤ 3 lần / giây, chuyển mượt).
        let level = combo.press(at: media)
        let from = candle.value(at: media)
        if let to = candle.press(at: media, level: level) { candleStep(from: from, to: to, bounds: b) }
    }

    private func candleStep(from: Double, to: Double, bounds b: CGRect) {
        let l = candleLayer ?? {
            let g = CAGradientLayer()
            let c = meritColor(SunlightFx.candleColor)
            g.colors = [c.withAlphaComponent(0).cgColor, c.withAlphaComponent(0.9).cgColor]
            g.startPoint = CGPoint(x: 0.5, y: 0)
            g.endPoint = CGPoint(x: 0.5, y: 1)
            g.opacity = 0
            host?.addSublayer(g)
            candleLayer = g
            return g
        }()
        let band = CGFloat(SunlightFx.candleBand)
        let f = CGRect(x: b.minX, y: b.maxY - band, width: b.width, height: band)
        if l.frame != f { l.frame = f }
        let total = SunlightFx.candleHold + SunlightFx.candleFade
        let steps = 15
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = (0...steps).map { CandleFlicker.envelope(total * Double($0) / Double(steps), from: from, to: to) }
        a.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        a.duration = total
        a.isRemovedOnCompletion = true
        l.opacity = 0
        l.add(a, forKey: "candle")
    }

    private func make() -> Burst {
        let bu = Burst()
        bu.root.bounds = .zero
        bu.root.position = .zero
        bu.root.anchorPoint = .zero
        bu.root.isHidden = true
        let light = meritColor(SunlightFx.light).cgColor
        func attach(_ l: CAShapeLayer, level: Double) {
            l.fillColor = light
            l.opacity = 0
            let a = CAKeyframeAnimation(keyPath: "opacity")
            let steps = 10
            a.values = (0...steps).map { level * SunlightFx.envelope(SunlightFx.duration * Double($0) / Double(steps) * 0.9999) }
            a.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
            a.duration = SunlightFx.duration
            a.beginTime = Self.animBegin
            a.fillMode = .removed
            a.isRemovedOnCompletion = false
            l.add(a, forKey: "fx")
            bu.root.addSublayer(l)
        }
        for i in 0..<SunlightFx.beams {
            let ray = CAShapeLayer()
            attach(ray, level: SunlightFx.beamPeak * SunlightFx.beamWeights[i])
            bu.rays.append(ray)
        }
        attach(bu.soft, level: SunlightFx.neighbor)
        attach(bu.strong, level: SunlightFx.peak)
        host?.addSublayer(bu.root)
        return bu
    }

    func halt() {
        candleLayer?.removeAllAnimations()
        candle.reset()
        combo.reset()
    }

    func remove() {
        for b in bursts { b.root.removeFromSuperlayer() }
        bursts.removeAll()
        candleLayer?.removeFromSuperlayer()
        candleLayer = nil
        candle.reset()
        combo.reset()
    }
}
