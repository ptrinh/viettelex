// SwipeDecoder.swift — LÕI GIẢI MÃ GÕ VUỐT (swipe/glide typing) tiếng Việt, phần
// THUẦN: không UIKit, không touch. Bản Kotlin song sinh:
// android/keyboard/src/main/kotlin/com/viettelex/keyboard/SwipeDecoder.kt —
// sửa thuật toán/hằng số ở đây thì sửa y hệt bên kia (test parity dùng chung
// fixture KeyboardTests/Fixtures/swipe-paths.txt so top-1 hai bản).
//
// Mô hình: người dùng vuốt theo chữ KHÔNG DẤU ("viet"), decoder trả các dạng
// không dấu top-K; `expand` bung một dạng thành âm tiết có dấu (việt, viết…)
// theo tần suất lexicon (+ điểm ngữ cảnh do caller cấp).
//
// Thuật toán kiểu SHARK2 (Kristensson & Zhai 2004), giống FlorisBoard
// StatisticalGlideTypingClassifier:
//   • template = đường nối tâm phím của dạng không dấu (gộp chữ lặp: luu→lu,
//     boong→bong), tính theo LAYOUT THẬT caller truyền vào;
//   • resample cả đường vuốt lẫn template thành N điểm cách đều theo độ dài;
//   • shape channel: dời trọng tâm về gốc, chia cạnh lớn bbox (sàn 1 phím) →
//     khoảng cách trung bình; location channel: khoảng cách tuyệt đối (đơn vị
//     bề rộng phím), trọng số α nặng ở 2 đầu, "đường hầm" 0.25 phím không phạt;
//   • log-prob Gaussian 2 kênh + λ·tần suất (byte log 0-255 của lexicon);
//   • lọc trước: phím đầu/cuối của template phải cách điểm đầu/cuối đường vuốt
//     ≤ 1.6 phím (không đủ ứng viên thì nới 3.2).
// Hằng số tinh chỉnh bằng đường vuốt giả (σ nhiễu 0.25 phím) trên 500 âm tiết
// phổ biến — xem SwipeDecoderTests. Mọi phép tính Float32 cùng thứ tự với bản
// Kotlin để hai nền tảng ra cùng điểm (không dùng exp/log trong vòng chấm).
//
// Bộ nhớ: không tải gì cho tới lần decode đầu (hoặc prepare()). Template
// Float32 phẳng 1666 dạng × 24 điểm × 2 ≈ 320 KB + ~60 KB metadata.
// Không cấp phát trong vòng chấm điểm (buffer cấp sẵn). KHÔNG thread-safe:
// gọi từ một luồng (main) hoặc tự khoá.
import Foundation

// MARK: - Layout

/// Tâm phím chữ a…z theo toạ độ thật của bàn phím (pt/px tuỳ caller, miễn
/// cùng hệ với đường vuốt). Đổi layout (xoay máy, iPad, bàn phím nổi…) →
/// gọi `SwipeDecoder.setLayout` lại; template dựng lại lười.
struct SwipeLayout: Equatable {
    /// Bước phím ngang (tâm-tới-tâm) — đơn vị chuẩn hoá mọi khoảng cách.
    let keyWidth: Float
    /// 52 số: (x, y) của 'a'…'z'; +∞ = layout không có phím đó.
    let centers: [Float]

    init(keyWidth: Float, centers: [Character: (x: Float, y: Float)]) {
        precondition(keyWidth > 0, "keyWidth phải > 0")
        var c = [Float](repeating: .infinity, count: 52)
        for (ch, p) in centers {
            guard let a = ch.asciiValue, a >= 97, a <= 122 else { continue }
            c[Int(a - 97) * 2] = p.x
            c[Int(a - 97) * 2 + 1] = p.y
        }
        self.keyWidth = keyWidth
        self.centers = c
    }

    /// QWERTY chuẩn (hàng 2 lệch 0.5 phím, hàng 3 lệch 1.5 phím như iPhone/
    /// Gboard) — tiện cho test và làm mặc định khi chưa đo được layout thật.
    static func qwerty(keyWidth: Float, rowHeight: Float,
                       originX: Float = 0, originY: Float = 0) -> SwipeLayout {
        var m: [Character: (x: Float, y: Float)] = [:]
        let rows: [(String, Float)] = [("qwertyuiop", 0.5), ("asdfghjkl", 1.0), ("zxcvbnm", 2.0)]
        for (r, (row, x0)) in rows.enumerated() {
            for (i, ch) in row.enumerated() {
                m[ch] = (originX + (x0 + Float(i)) * keyWidth,
                         originY + (Float(r) + 0.5) * rowHeight)
            }
        }
        return SwipeLayout(keyWidth: keyWidth, centers: m)
    }

    func center(of ch: Character) -> (x: Float, y: Float)? {
        guard let a = ch.asciiValue, a >= 97, a <= 122 else { return nil }
        let x = centers[Int(a - 97) * 2]
        return x.isFinite ? (x, centers[Int(a - 97) * 2 + 1]) : nil
    }
}

// MARK: - Đường vuốt

/// Bộ đệm điểm vuốt cấp sẵn, dùng chung cho iOS/Android (bản Kotlin cùng
/// hành vi). Chỉ nhận điểm cách điểm nhận trước ≥ `minDistance` (khuyên
/// 1/6–1/4 bề rộng phím) để bỏ rung tay + giữ mảng nhỏ; điểm nhấc tay thêm
/// bằng `add(…, force: true)` để đầu cuối luôn đúng. Đầy thì điểm mới ghi đè
/// điểm cuối (không cấp phát thêm).
struct SwipePath {
    let capacity: Int
    let minDistance: Float
    private(set) var xs: [Float]
    private(set) var ys: [Float]
    private(set) var ts: [Double]
    private(set) var count = 0
    /// Tổng độ dài polyline (cùng đơn vị toạ độ).
    private(set) var length: Float = 0

    init(minDistance: Float, capacity: Int = 256) {
        precondition(capacity >= 2)
        self.capacity = capacity
        self.minDistance = minDistance
        xs = [Float](repeating: 0, count: capacity)
        ys = [Float](repeating: 0, count: capacity)
        ts = [Double](repeating: 0, count: capacity)
    }

    mutating func reset() { count = 0; length = 0 }

    /// Thêm điểm; trả true nếu được nhận (hoặc ghi đè điểm cuối khi đầy).
    @discardableResult
    mutating func add(x: Float, y: Float, t: Double, force: Bool = false) -> Bool {
        if count > 0 {
            let dx = x - xs[count - 1], dy = y - ys[count - 1]
            let d = (dx * dx + dy * dy).squareRoot()
            if !force && d < minDistance { return false }
            if force && d == 0 { ts[count - 1] = t; return true }
            if count == capacity {
                // đầy: dời điểm cuối tới vị trí mới
                let px = xs[count - 2], py = ys[count - 2]
                let ox = xs[count - 1] - px, oy = ys[count - 1] - py
                let nx = x - px, ny = y - py
                length += (nx * nx + ny * ny).squareRoot() - (ox * ox + oy * oy).squareRoot()
                xs[count - 1] = x; ys[count - 1] = y; ts[count - 1] = t
                return true
            }
            length += d
        }
        xs[count] = x; ys[count] = y; ts[count] = t
        count += 1
        return true
    }

    /// Thời lượng vuốt (giây) — agent tích hợp dùng phân biệt vuốt/chạm.
    var duration: Double { count > 1 ? ts[count - 1] - ts[0] : 0 }
}

// MARK: - Kết quả

struct SwipeCandidate: Equatable {
    /// Dạng không dấu trong lexicon (đ gộp d), vd "viet".
    let folded: String
    /// Điểm log (càng lớn càng tốt; chỉ so sánh tương đối).
    let score: Float
}

struct SwipeWord: Equatable {
    /// Âm tiết có dấu, chữ thường, vd "việt".
    let word: String
    let score: Float
}

// MARK: - Lexicon dạng không dấu (lười)

/// 1666 dạng không dấu rút từ vnlexicon.bin (entry đã sort theo folded rồi
/// tần suất giảm dần → mỗi dạng là một dải id liên tiếp, entry đầu có tần
/// suất cao nhất).
enum SwipeLexicon {
    struct Forms {
        let folded: [String]
        /// Dải id lexicon của dạng f: idStart[f] ..< idStart[f+1].
        let idStart: [Int32]
        /// Tần suất (0-255) = entry mạnh nhất của dạng.
        let freq: [UInt8]
        /// Phím đã gộp chữ lặp (0…25), dạng f: keys[keyStart[f] ..< keyStart[f+1]].
        let keys: [UInt8]
        let keyStart: [Int32]
        var count: Int { folded.count }
    }

    static let forms: Forms = {
        let n = VNLexicon2Data.count
        let off = VNLexicon2Data.offsets
        var folded: [String] = [], idStart: [Int32] = [], freq: [UInt8] = []
        var keys: [UInt8] = [], keyStart: [Int32] = [0]
        folded.reserveCapacity(1700); idStart.reserveCapacity(1701)
        var prev = Data()
        for id in 0..<n {
            let f = VNLexicon2Data.foldedSlice(Int(off[id]), Int(off[id + 1]))
            if id > 0 && f.elementsEqual(prev) { continue }
            prev = f
            folded.append(String(decoding: f, as: UTF8.self))
            idStart.append(Int32(id))
            freq.append(VNLexicon2Data.freq(id))
            var last: UInt8 = 255
            for b in f {
                let k = b &- 97
                if k != last { keys.append(k); last = k }
            }
            keyStart.append(Int32(keys.count))
        }
        idStart.append(Int32(n))
        return Forms(folded: folded, idStart: idStart, freq: freq,
                     keys: keys, keyStart: keyStart)
    }()

    /// Chỉ số dạng `folded` (binary search, ASCII) — nil nếu không có.
    static func index(of folded: String) -> Int? {
        let a = forms.folded
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] < folded { lo = mid + 1 } else { hi = mid }
        }
        return lo < a.count && a[lo] == folded ? lo : nil
    }
}

// MARK: - Decoder

final class SwipeDecoder {
    /// Hằng số mô hình — GIỮ Y HỆT bản Kotlin.
    struct Params: Equatable {
        var points = 24            // N điểm resample
        var sigmaShape: Float = 0.2
        var sigmaLoc: Float = 0.2  // đơn vị bề rộng phím
        var lambdaFreq: Float = 2.5
        var tunnel: Float = 0.25   // lệch ≤ 0.25 phím không phạt (location)
        var endWeight: Float = 8   // α ở 2 đầu = 1 + endWeight
        var endSpan: Float = 0.15  // phần đường (mỗi đầu) được tăng α
        var filterRadius: Float = 1.6
        /// Số ứng viên (sau hình học) đem chấm ngữ cảnh khi có closure.
        var contextPool = 16
    }

    let params: Params
    private(set) var layout: SwipeLayout?

    // template: dạng f, điểm i → tpl[(f*N + i)*2], tpl[(f*N + i)*2 + 1]
    private var tpl: [Float] = []
    private var tplCX: [Float] = [], tplCY: [Float] = [], tplScale: [Float] = []
    private var tplValid: [Bool] = []
    private let alpha: [Float]
    private let alphaSum: Float
    // scratch cấp sẵn
    private var ux: [Float], uy: [Float], sx: [Float], sy: [Float]
    private var topScore: [Float] = [], topIdx: [Int] = []

    init(params: Params = Params()) {
        self.params = params
        let n = params.points
        precondition(n >= 2)
        var a = [Float](repeating: 1, count: n)
        var s: Float = 0
        for i in 0..<n {
            let edge = Float(min(i, n - 1 - i)) / (Float(n) * params.endSpan)
            a[i] = 1 + params.endWeight * max(0, 1 - edge)
            s += a[i]
        }
        alpha = a; alphaSum = s
        ux = [Float](repeating: 0, count: n); uy = ux; sx = ux; sy = ux
    }

    /// Đặt layout; khác layout cũ thì bỏ template (dựng lại lười).
    func setLayout(_ l: SwipeLayout) {
        guard l != layout else { return }
        layout = l
        tpl = []; tplCX = []; tplCY = []; tplScale = []; tplValid = []
    }

    /// Dựng template ngay (gọi ở background khi bàn phím hiện để lần vuốt
    /// đầu không trễ). An toàn gọi nhiều lần.
    func prepare() {
        guard let l = layout, tpl.isEmpty else { return }
        buildTemplates(l)
    }

    /// Byte RAM template hiện giữ (test ngân sách bộ nhớ).
    var templateBytes: Int {
        tpl.count * 4 + (tplCX.count + tplCY.count + tplScale.count) * 4 + tplValid.count
    }

    private func buildTemplates(_ l: SwipeLayout) {
        let forms = SwipeLexicon.forms
        let n = params.points, fc = forms.count
        tpl = [Float](repeating: 0, count: fc * n * 2)
        tplCX = [Float](repeating: 0, count: fc)
        tplCY = tplCX; tplScale = tplCX
        tplValid = [Bool](repeating: false, count: fc)
        var kx = [Float](repeating: 0, count: 32), ky = kx
        var rx = [Float](repeating: 0, count: n), ry = rx
        for f in 0..<fc {
            let lo = Int(forms.keyStart[f]), hi = Int(forms.keyStart[f + 1])
            var ok = hi - lo <= kx.count
            var m = 0
            if ok {
                for j in lo..<hi {
                    let k = Int(forms.keys[j])
                    guard k < 26 else { ok = false; break }
                    let x = l.centers[k * 2], y = l.centers[k * 2 + 1]
                    guard x.isFinite else { ok = false; break }
                    kx[m] = x; ky[m] = y; m += 1
                }
            }
            guard ok, m > 0 else { continue }
            Self.resample(kx, ky, m, n, &rx, &ry)
            let base = f * n * 2
            for i in 0..<n { tpl[base + i * 2] = rx[i]; tpl[base + i * 2 + 1] = ry[i] }
            let (cx, cy, sc) = Self.shapeFrame(rx, ry, n, l.keyWidth)
            tplCX[f] = cx; tplCY[f] = cy; tplScale[f] = sc
            tplValid[f] = true
        }
    }

    /// Giải mã đường vuốt → top-K dạng không dấu, điểm giảm dần.
    /// `context(folded)` (tuỳ chọn) cộng điểm ngữ cảnh (log-domain, vd từ
    /// UserLangModel với từ trước) cho `contextPool` ứng viên đầu.
    func decode(_ path: SwipePath, topK: Int = 5,
                context: ((String) -> Float)? = nil) -> [SwipeCandidate] {
        decode(xs: path.xs, ys: path.ys, count: path.count, topK: topK, context: context)
    }

    func decode(xs: [Float], ys: [Float], count: Int, topK: Int = 5,
                context: ((String) -> Float)? = nil) -> [SwipeCandidate] {
        guard count > 0, topK > 0, let l = layout else { return [] }
        if tpl.isEmpty { buildTemplates(l) }
        let forms = SwipeLexicon.forms
        let n = params.points, w = l.keyWidth
        Self.resample(xs, ys, count, n, &ux, &uy)
        let (ucx, ucy, us) = Self.shapeFrame(ux, uy, n, w)
        for i in 0..<n { sx[i] = (ux[i] - ucx) * us; sy[i] = (uy[i] - ucy) * us }

        let m = context == nil ? topK : max(topK, params.contextPool)
        if topScore.count < m {
            topScore = [Float](repeating: 0, count: m)
            topIdx = [Int](repeating: 0, count: m)
        }
        var filled = 0
        let tunnelW = params.tunnel * w
        let invS = 1 / (2 * params.sigmaShape * params.sigmaShape)
        let invL = 1 / (2 * params.sigmaLoc * params.sigmaLoc)
        let lam = params.lambdaFreq

        tpl.withUnsafeBufferPointer { T in
        ux.withUnsafeBufferPointer { UX in
        uy.withUnsafeBufferPointer { UY in
        sx.withUnsafeBufferPointer { SX in
        sy.withUnsafeBufferPointer { SY in
        alpha.withUnsafeBufferPointer { A in
        topScore.withUnsafeMutableBufferPointer { TS in
        topIdx.withUnsafeMutableBufferPointer { TI in
            for pass in 0..<2 {
                let r = params.filterRadius * w * (pass == 0 ? 1 : 2)
                let r2 = r * r
                filled = 0
                for f in 0..<forms.count where tplValid[f] {
                    let base = f * n * 2
                    var dx = UX[0] - T[base], dy = UY[0] - T[base + 1]
                    if dx * dx + dy * dy > r2 { continue }
                    dx = UX[n - 1] - T[base + (n - 1) * 2]
                    dy = UY[n - 1] - T[base + (n - 1) * 2 + 1]
                    if dx * dx + dy * dy > r2 { continue }
                    let cx = tplCX[f], cy = tplCY[f], sc = tplScale[f]
                    var ds: Float = 0, dl: Float = 0
                    for i in 0..<n {
                        let tx = T[base + i * 2], ty = T[base + i * 2 + 1]
                        let ex = SX[i] - (tx - cx) * sc, ey = SY[i] - (ty - cy) * sc
                        ds += (ex * ex + ey * ey).squareRoot()
                        let lx = UX[i] - tx, ly = UY[i] - ty
                        let d = (lx * lx + ly * ly).squareRoot() - tunnelW
                        if d > 0 { dl += A[i] * d }
                    }
                    ds = ds / Float(n)
                    dl = dl / alphaSum / w
                    let score = -(ds * ds) * invS - (dl * dl) * invL
                        + lam * Float(forms.freq[f]) / 255
                    Self.insertTop(score, f, TS, TI, &filled, m)
                }
                if filled >= topK { break }
            }
        }}}}}}}}

        var out: [SwipeCandidate] = []
        out.reserveCapacity(filled)
        for k in 0..<filled {
            let f = topIdx[k]
            var s = topScore[k]
            if let context { s += context(forms.folded[f]) }
            out.append(SwipeCandidate(folded: forms.folded[f], score: s))
        }
        if context != nil {
            // sort ổn định: bằng điểm giữ thứ tự hình học
            out = out.enumerated().sorted {
                $0.element.score != $1.element.score
                    ? $0.element.score > $1.element.score : $0.offset < $1.offset
            }.map { $0.element }
        }
        return Array(out.prefix(topK))
    }

    /// Bung dạng không dấu thành âm tiết có dấu, điểm = λ·tần suất/255
    /// (+ context(âm tiết)), giảm dần; bằng điểm giữ thứ tự lexicon.
    static func expand(_ folded: String, limit: Int = 8, lambdaFreq: Float = Params().lambdaFreq,
                       context: ((String) -> Float)? = nil) -> [SwipeWord] {
        guard limit > 0, let f = SwipeLexicon.index(of: folded) else { return [] }
        let forms = SwipeLexicon.forms
        let lo = Int(forms.idStart[f]), hi = Int(forms.idStart[f + 1])
        var out: [(SwipeWord, Int)] = []
        out.reserveCapacity(hi - lo)
        for id in lo..<hi {
            let w = VNSuggest.display(id)
            var s = lambdaFreq * Float(VNLexicon2Data.freq(id)) / 255
            if let context { s += context(w) }
            out.append((SwipeWord(word: w, score: s), id))
        }
        out.sort { $0.0.score != $1.0.score ? $0.0.score > $1.0.score : $0.1 < $1.1 }
        return out.prefix(limit).map { $0.0 }
    }

    // MARK: hàm thuần (cùng thứ tự phép tính với bản Kotlin)

    /// Chèn (score, idx) vào top-m giảm dần; bằng điểm → phần tử vào trước
    /// (idx nhỏ hơn) đứng trước.
    private static func insertTop(_ s: Float, _ idx: Int,
                                  _ ts: UnsafeMutableBufferPointer<Float>,
                                  _ ti: UnsafeMutableBufferPointer<Int>,
                                  _ filled: inout Int, _ m: Int) {
        if filled == m && s <= ts[m - 1] { return }
        var pos = filled < m ? filled : m - 1
        while pos > 0 && ts[pos - 1] < s {
            ts[pos] = ts[pos - 1]; ti[pos] = ti[pos - 1]; pos -= 1
        }
        ts[pos] = s; ti[pos] = idx
        if filled < m { filled += 1 }
    }

    /// Resample polyline (count điểm) thành n điểm cách đều theo độ dài.
    static func resample(_ xs: [Float], _ ys: [Float], _ count: Int, _ n: Int,
                         _ ox: inout [Float], _ oy: inout [Float]) {
        var total: Float = 0
        if count > 1 {
            for j in 0..<(count - 1) {
                let dx = xs[j + 1] - xs[j], dy = ys[j + 1] - ys[j]
                total += (dx * dx + dy * dy).squareRoot()
            }
        }
        if count == 1 || total <= 1e-4 {
            for k in 0..<n { ox[k] = xs[0]; oy[k] = ys[0] }
            return
        }
        let step = total / Float(n - 1)
        ox[0] = xs[0]; oy[0] = ys[0]
        var j = 0, acc: Float = 0
        var segLen = segmentLength(xs, ys, 0)
        for k in 1..<(n - 1) {
            let target = Float(k) * step
            while j < count - 2 && acc + segLen < target {
                acc += segLen; j += 1
                segLen = segmentLength(xs, ys, j)
            }
            var t: Float = segLen > 0 ? (target - acc) / segLen : 0
            if t < 0 { t = 0 } else if t > 1 { t = 1 }
            ox[k] = xs[j] + (xs[j + 1] - xs[j]) * t
            oy[k] = ys[j] + (ys[j + 1] - ys[j]) * t
        }
        ox[n - 1] = xs[count - 1]; oy[n - 1] = ys[count - 1]
    }

    private static func segmentLength(_ xs: [Float], _ ys: [Float], _ j: Int) -> Float {
        let dx = xs[j + 1] - xs[j], dy = ys[j + 1] - ys[j]
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Trọng tâm + hệ số chuẩn hoá shape: 1 / max(cạnh bbox, 1 phím).
    static func shapeFrame(_ xs: [Float], _ ys: [Float], _ n: Int,
                           _ keyWidth: Float) -> (Float, Float, Float) {
        var minX = xs[0], maxX = xs[0], minY = ys[0], maxY = ys[0]
        var sx: Float = 0, sy: Float = 0
        for i in 0..<n {
            let x = xs[i], y = ys[i]
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
            sx += x; sy += y
        }
        let side = max(max(maxX - minX, maxY - minY), keyWidth)
        return (sx / Float(n), sy / Float(n), 1 / side)
    }
}
