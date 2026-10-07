// Trackpad (giữ phím cách) — logic THUẦN (không UIKit), pinned by TrackpadTests.
// Cùng thuật toán/ngưỡng cử chỉ với Android (android/.../ime/Trackpad.kt).
//
// • Ngang: mỗi 9pt = 1 ký tự (cảm giác stock). Dọc: mỗi 24pt = 1 dòng.
// • Hai trục ĐỘC LẬP như stock (kéo chéo đi cả hai), lọc theo HƯỚNG kéo: hướng = EMA
//   véc-tơ dời (α 0.3/sự kiện). Hướng gần ngang (|dy| < 0.4·|dx|, ~22°) ⇒ bỏ dy — kéo
//   ngang hơi chéo không nhảy dòng; gần dọc ⇒ bỏ dx — rung ngang khi kéo dọc không dời
//   ký tự; ở giữa (kéo chéo) ⇒ cộng cả hai. Một sự kiện đủ ngưỡng cả hai trục ⇒ phát
//   trục vượt ngưỡng nhiều hơn, trục kia giữ tích luỹ, phát ở sự kiện sau.
//   (Bản cũ khoá trục: mỗi bước ngang xoá dy tích luỹ ⇒ kéo chéo / kéo dọc hơi lệch
//   gần như không bao giờ lên xuống dòng.)
// • Tăng tốc: tốc độ (EMA, pt/s) theo trục; ≤ slow ⇒ ×1 (chính xác từng ký tự/dòng),
//   ≥ fast ⇒ ×max, giữa nội suy tuyến tính. Ngang 300→1500 pt/s, ×5; dọc 200→1000, ×3.
import Foundation

struct TrackpadGesture {
    enum Axis { case horizontal, vertical }
    /// `count` có dấu: ngang âm = trái; dọc âm = lên.
    struct Step: Equatable { let axis: Axis; let count: Int }

    static let hStep = 9.0, vStep = 24.0
    /// Tỉ lệ trục phụ / trục chính (theo hướng kéo) dưới ngưỡng này ⇒ bỏ trục phụ (~22°).
    static let offAxis = 0.4
    /// Trọng số sự kiện mới trong EMA hướng kéo.
    static let dirAlpha = 0.3
    static let hSlow = 300.0, hFast = 1500.0, hMax = 5.0
    static let vSlow = 200.0, vFast = 1000.0, vMax = 3.0
    static let ema = 0.5, minDt = 1.0 / 240, pause = 0.1

    private var accX = 0.0, accY = 0.0
    private var dirX = 0.0, dirY = 0.0
    private var lastX = 0.0, lastY = 0.0, lastT = 0.0
    private var speedX = 0.0, speedY = 0.0

    mutating func begin(x: Double, y: Double, t: Double) {
        accX = 0; accY = 0; dirX = 0; dirY = 0
        lastX = x; lastY = y; lastT = t
        speedX = 0; speedY = 0
    }

    mutating func move(x: Double, y: Double, t: Double) -> Step? {
        let dx = x - lastX, dy = y - lastY, dtRaw = t - lastT
        lastX = x; lastY = y; lastT = t
        if dx == 0 && dy == 0 { return nil }
        let dt = max(dtRaw, Self.minDt)
        let ix = abs(dx) / dt, iy = abs(dy) / dt
        if dtRaw > Self.pause { speedX = ix; speedY = iy }   // nghỉ lâu: không mang đà cũ
        else {
            speedX = Self.ema * ix + (1 - Self.ema) * speedX
            speedY = Self.ema * iy + (1 - Self.ema) * speedY
        }
        dirX = Self.dirAlpha * dx + (1 - Self.dirAlpha) * dirX
        dirY = Self.dirAlpha * dy + (1 - Self.dirAlpha) * dirY
        let hx = abs(dirX), hy = abs(dirY)
        if hy >= Self.offAxis * hx { accY += dy }            // không gần-ngang ⇒ tính dọc
        if hx >= Self.offAxis * hy { accX += dx }            // không gần-dọc ⇒ tính ngang
        let rx = abs(accX) / Self.hStep, ry = abs(accY) / Self.vStep
        if rx < 1 && ry < 1 { return nil }
        return ry >= rx ? emitV() : emitH()
    }

    private mutating func emitH() -> Step {
        let units = Int(accX / Self.hStep)
        accX -= Double(units) * Self.hStep
        return Step(axis: .horizontal,
                    count: Self.accelerate(units, speed: speedX, slow: Self.hSlow, fast: Self.hFast, max: Self.hMax))
    }

    private mutating func emitV() -> Step {
        let lines = Int(accY / Self.vStep)
        accY -= Double(lines) * Self.vStep
        return Step(axis: .vertical,
                    count: Self.accelerate(lines, speed: speedY, slow: Self.vSlow, fast: Self.vFast, max: Self.vMax))
    }

    /// `units` bước thô ⇒ bước đã tăng tốc theo `speed`. Chậm ⇒ nguyên `units`.
    static func accelerate(_ units: Int, speed: Double, slow: Double, fast: Double, max m: Double) -> Int {
        guard units != 0 else { return 0 }
        let f: Double
        if speed <= slow { f = 1 }
        else if speed >= fast { f = m }
        else { f = 1 + (m - 1) * (speed - slow) / (fast - slow) }
        let n = Swift.max(1, Int((Double(abs(units)) * f).rounded()))
        return units < 0 ? -n : n
    }
}

/// Gom các bước trackpad trong CÙNG một khung hình thành một lệnh (thuần, test ở
/// TrackpadTests). Mỗi `adjustTextPosition` là một lệnh gửi sang app host (XPC) và kéo
/// theo selectionWill/DidChange từ host — touch 120Hz + tăng tốc có thể sinh nhiều bước
/// mỗi frame. KeyboardView đẩy bước vào đây, CADisplayLink xả ≤1 lệnh/trục mỗi frame.
/// Bước liên tiếp cùng trục cộng dồn; đổi trục giữa frame giữ thứ tự (ngang rồi dọc…).
struct TrackpadCoalescer {
    private(set) var pending: [TrackpadGesture.Step] = []

    var isEmpty: Bool { pending.isEmpty }

    mutating func add(_ step: TrackpadGesture.Step) {
        guard step.count != 0 else { return }
        if let last = pending.last, last.axis == step.axis {
            let sum = last.count + step.count
            pending.removeLast()
            if sum != 0 { pending.append(.init(axis: step.axis, count: sum)) }
        } else {
            pending.append(step)
        }
    }

    /// Lấy hết bước đã gom (thường 0–1 phần tử) và xoá hàng đợi.
    mutating func drain() -> [TrackpadGesture.Step] {
        defer { pending.removeAll(keepingCapacity: true) }
        return pending
    }
}

/// Context host trong lúc kéo trackpad. Host cập nhật `documentContext*` BẤT ĐỒNG BỘ
/// sau `adjustTextPosition` (XPC) — bước kế tiếp (frame sau, hoặc dọc ngay sau ngang
/// trong cùng frame) có thể còn đọc context CŨ ⇒ tính dòng/cột từ chỗ con trỏ đã rời.
/// Giữ một "view" đã dời theo các lệnh mình gửi: đọc mới GIỐNG lần đọc trước ⇒ host chưa
/// kịp, dùng view; khác ⇒ host đã cập nhật, lấy context mới. Thuần, pinned by tests.
struct TrackpadContext {
    private var lastRead: (before: String, after: String)?
    private(set) var before = "", after = ""

    mutating func reset() { lastRead = nil; before = ""; after = "" }

    mutating func resolve(before b: String, after a: String) -> (before: String, after: String) {
        if let r = lastRead, r.before == b, r.after == a { return (before, after) }
        lastRead = (b, a); before = b; after = a
        return (b, a)
    }

    /// Đã gửi lệnh dời `off` UTF-16: dời view (kẹp trong context thấy được, như host kẹp
    /// ở đầu/cuối văn bản; rơi giữa grapheme ⇒ lùi về đầu grapheme).
    mutating func moved(by off: Int) {
        guard off != 0, lastRead != nil else { return }
        let full = before + after
        let target = min(max(before.utf16.count + off, 0), full.utf16.count)
        var u = 0
        var cut = full.startIndex
        for i in full.indices {
            let n = full[i].utf16.count
            if u + n > target { break }
            u += n
            cut = full.index(after: i)
        }
        before = String(full[..<cut]); after = String(full[cut...])
    }
}

enum VerticalMove {
    /// Ký tự / dòng hiển thị ước lượng: bề ngang ô (≈ bề ngang bàn phím trừ lề) chia bề
    /// rộng trung bình một ký tự của font thân bài. ≤ 0 ⇒ không biết (chỉ ngắt cứng).
    static func charsPerLine(fieldWidth: Double, avgAdvance: Double) -> Int {
        guard fieldWidth > 0, avgAdvance > 0 else { return 0 }
        return max(minCharsPerLine, Int(fieldWidth / avgAdvance))
    }
    static let minCharsPerLine = 8
    /// Lề trái + phải ước lượng của ô văn bản so với bề ngang bàn phím (Notes ~2×20pt,
    /// ô Messages hẹp hơn; chọn giữa — xem báo cáo hiệu chỉnh trong TrackpadTests).
    static let fieldInset = 48.0
    /// Câu mẫu tiếng Việt để đo bề rộng ký tự trung bình (có dấu cách). Câu nửa Việt nửa
    /// Anh đo hẹp hơn chữ Việt thật ~6% ⇒ ước dư ký tự/dòng (hiệu chỉnh TrackpadTests).
    static let sample = "Hôm nay trời đẹp quá, mình rủ mấy đứa bạn đi uống cà phê rồi về nhà nấu cơm tối nhé."
    /// Bề rộng ký tự TB từ bề rộng `sample` đã đo. ×1.05: TextKit ngắt theo pixel, câu
    /// mẫu đo hơi hẹp so với văn thật — hiệu chỉnh để số dòng/đầu dòng khớp TextKit
    /// (testCalibrationAgainstTextKit, màn 375/402/440pt).
    static func avgAdvance(sampleWidth: Double) -> Double {
        sampleWidth / Double(sample.count) * 1.05
    }

    /// Dời (UTF-16 — đơn vị NSString mà UITextInput/adjustTextPosition dùng) để lên
    /// (`lines` < 0) / xuống `lines` dòng HIỂN THỊ, giữ cột grapheme (dòng đích ngắn hơn
    /// ⇒ cuối dòng). Proxy không biết bố cục host ⇒ GẦN ĐÚNG: dựng lại dòng hiển thị trên
    /// context thấy được — đoạn tách bởi ký tự xuống dòng, mỗi đoạn ngắt chữ (word wrap)
    /// theo `charsPerLine` ký tự (≤ 0 ⇒ chỉ ngắt cứng). Một bước = dòng trên/dưới, dù là
    /// dòng tự ngắt hay qua ngắt cứng (sang dòng hiển thị cuối/đầu của đoạn kề).
    /// Ít dòng hơn yêu cầu ⇒ đi hết số có. Đã ở dòng đầu/cuối của phần THẤY ĐƯỢC (host
    /// hay cắt context — không chắc là đầu/cuối văn bản) ⇒ về đầu/cuối phần thấy được;
    /// đã ở đúng mép (`before`/`after` rỗng) ⇒ ±1 để vượt sang dòng khuất (đầu/cuối văn
    /// bản thật thì host kẹp, vô hại — như trackpad ngang). Không có context nào ⇒ nil.
    static func offset(before: String, after: String, lines: Int, charsPerLine cpl: Int = 0) -> Int? {
        guard lines != 0 else { return 0 }
        let b = Array(before), a = Array(after)
        if b.isEmpty && a.isEmpty { return nil }
        let chars = b + a
        let caret = b.count
        let vl = layout(chars, charsPerLine: cpl)
        let cur = vl.lastIndex { $0.start <= caret } ?? 0
        if lines < 0 && cur == 0 { return b.isEmpty ? -1 : -before.utf16.count }
        if lines > 0 && cur == vl.count - 1 { return a.isEmpty ? 1 : after.utf16.count }
        let line = vl[min(max(cur + lines, 0), vl.count - 1)]
        let col = caret - vl[cur].start
        // Dòng tự ngắt: cuối dòng == đầu dòng sau (con trỏ sẽ hiện ở dòng sau) ⇒ đứng
        // trước ký tự cuối (thường là dấu cách treo).
        let maxCol = line.hardEnd ? line.end - line.start : max(line.end - line.start - 1, 0)
        let pos = line.start + min(col, maxCol)
        if pos >= caret { return chars[caret..<pos].reduce(0) { $0 + $1.utf16.count } }
        return -chars[pos..<caret].reduce(0) { $0 + $1.utf16.count }
    }

    /// Dòng hiển thị [start, end) theo chỉ số grapheme; `hardEnd` = dòng cuối của đoạn.
    struct Line: Equatable { let start: Int; let end: Int; let hardEnd: Bool }

    /// Tách đoạn theo Character.isNewline (\n, \r, \r\n một ký tự, U+2028/2029…), rồi
    /// ngắt chữ tham lam: dòng chứa ≤ cpl ký tự, ngắt sau dấu cách gần nhất; dấu cách ở
    /// chỗ tràn thì treo cuối dòng (như UIKit); từ dài hơn cả dòng ⇒ cắt cứng.
    static func layout(_ chars: [Character], charsPerLine cpl: Int) -> [Line] {
        var out: [Line] = []
        func wrap(_ ps: Int, _ pe: Int) {
            var ls = ps
            if cpl > 0 {
                while pe - ls > cpl {
                    let limit = ls + cpl
                    var next = limit
                    if isSpace(chars[limit]) {
                        while next < pe && isSpace(chars[next]) { next += 1 }
                    } else {
                        while next > ls && !isSpace(chars[next - 1]) { next -= 1 }
                        if next == ls { next = limit }
                    }
                    if next >= pe { break }           // chỉ còn dấu cách treo: cùng dòng
                    out.append(Line(start: ls, end: next, hardEnd: false))
                    ls = next
                }
            }
            out.append(Line(start: ls, end: pe, hardEnd: true))
        }
        var ps = 0
        for (i, c) in chars.enumerated() where c.isNewline {
            wrap(ps, i)
            ps = i + 1
        }
        wrap(ps, chars.count)
        return out
    }

    private static func isSpace(_ c: Character) -> Bool { c.isWhitespace && !c.isNewline }
}
