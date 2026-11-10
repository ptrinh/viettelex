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
//     ≤ 1.6 phím (không đủ ứng viên thì nới 3.2);
//   • kênh độ dài (dài đường vs dài template, đơn vị phím);
//   • TẦNG 2 trên top-16: σ location thích nghi (nét cẩu thả ⇒ nới σ_L tới ×1.5, tin
//     tần suất/ngữ cảnh hơn), căn phím template đơn điệu vào đường 48 điểm, mỗi góc gắt
//     của đường phải gần một phím của ứng viên. Đo trên đường giả (dev/test tách,
//     scratchpad harness): +0.4…+4.4 điểm top-1 trong câu, lớn nhất khi lệch đầu/cuối;
//   • lệch tay cá nhân `offsetX/offsetY` học online bằng `learnOffset` (EMA);
//   • NHỊP (khi có thời gian điểm — SwipePath.ts): đuôi nét chậm ⇒ miễn phần LỐ theo hướng
//     nét cuối (người thật trôi quá phím cuối ~0.45 phím trước khi nhấc tay); tầng 2 phạt phím
//     giữa nằm trên đoạn lướt nhanh và đòi điểm DỪNG gần một phím. Không có thời gian ⇒ y hệt
//     thuật toán cũ. Đo trên nét thật: docs/DATA-SOURCES.md "Nét vuốt thật".
//   • UỐN h (tầng 2, không cần thời gian): cặp ứng viên chỉ khác chữ h của phụ âm ghép
//     (chưa/của) đổi chỗ theo độ uốn của đường về h (Params.bendWeight).
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
    /// Dạng không dấu trong lexicon (đ gộp d), vd "viet" — hoặc từ tiếng Anh nguyên văn
    /// khi `lang == .en` (giai đoạn 3, SwipeEnglish.swift).
    let folded: String
    /// Điểm log (càng lớn càng tốt; chỉ so sánh tương đối).
    let score: Float
    /// Nhãn ngôn ngữ: .vi = dạng không dấu cần expand; .en = chèn nguyên văn.
    var lang: SwipeLang = .vi
}

struct SwipeWord: Equatable {
    /// Âm tiết có dấu, chữ thường, vd "việt".
    let word: String
    let score: Float
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
        /// Kênh độ dài: −w·ln²((dài đường+1)/(dài template+1)), đơn vị phím (`lengthPenalty`).
        var lengthWeight: Float = 2
        /// Chấm lại (tầng 2) top-`rescorePool` hình học; 0 = tắt cả tầng 2 + σ thích nghi.
        var rescorePool = 16
        /// Điểm resample của tầng 2 (căn phím + góc).
        var rescorePoints = 48
        /// Căn phím template vào đường (đơn điệu): −w·trung bình d² (phím, trừ tunnel).
        var alignWeight: Float = 1
        /// Mỗi GÓC gắt trên đường phải gần một phím của ứng viên: −w·Σ d².
        var cornerWeight: Float = 3
        var cornerDegrees: Float = 55
        var rescoreTunnel: Float = 0.25
        /// σ location thích nghi: nét cẩu thả (location tốt nhất > ngưỡng, phím) ⇒ σ_L
        /// nhân tới `adaptMax` — tin tần suất/ngữ cảnh hơn (kiểu SHARK2 nới σ theo tốc độ).
        var adaptThreshold: Float = 0.13
        var adaptMax: Float = 1.5
        /// NHỊP (cần thời gian điểm vuốt, tầng 2): tốc độ tương đối r = v / v trung bình tại 48
        /// điểm. Mỗi phím GIỮA của ứng viên mà điểm đường gần nó nhất nằm trên đoạn nhanh (lướt
        /// qua) bị phạt w·max(0, r − speedRef); 0 = tắt. Hằng số nhịp/lố chỉnh trên nét thật +
        /// đường giả "tự nhiên" (docs/DATA-SOURCES.md "Nét vuốt thật").
        var speedWeight: Float = 0.3
        var speedRef: Float = 1.3
        /// Điểm DỪNG (cực tiểu r < dwellRatio, không sát 2 đầu) phải gần một phím: −w·Σ d².
        var dwellWeight: Float = 3
        var dwellRatio: Float = 0.35
        /// CHỮ "h" CỦA PHỤ ÂM GHÉP (tầng 2): hai ứng viên trong pool khác nhau đúng một phím giữa h
        /// đứng sau c/n/t/p/k/g (Việt) hoặc t/s/c/w/p/g (Anh) — chưa/của, chú/cụ. Nét thật lướt qua h
        /// nhanh như phím thường (không chậm lại) nên nhịp không phân biệt được; thứ phân biệt là
        /// đường UỐN về h: uốn = khoảng cách h tới dây cung nối 2 phím kề − khoảng cách h tới đường
        /// (phím). Ứng viên có h += w·kẹp(uốn − bendBias, ±bendCap), rồi kẹp trong [min, max] điểm
        /// cặp ± 0,01 (chỉ đổi chỗ TRONG cặp, không vượt ứng viên khác). Chỉ khi dây cung cách h
        /// trong [bendMinChord, bendMaxChord] phím (h gần thẳng hàng như chọn/con ⇒ hình học không
        /// phân biệt được; xa ⇒ kênh location đã đủ). 0 = tắt.
        var bendWeight: Float = 3
        var bendBias: Float = 0.05
        var bendCap: Float = 0.3
        var bendMinChord: Float = 0.3
        var bendMaxChord: Float = 1
        /// Lố đích ở đầu cuối: thành phần lệch THEO hướng nét cuối của template (đi quá phím cuối
        /// trước khi nhấc tay) được miễn tới `overshoot` phím ở điểm cuối (giảm dần về 0 hết đoạn
        /// endSpan); chỉ khi đuôi nét chậm (`tailGate`). 0 = tắt.
        var overshoot: Float = 1
        /// Cổng miễn lố theo tốc độ tương đối đuôi r: r ≤ tailSlow ⇒ đủ, r ≥ tailFast ⇒ tắt.
        var tailSlow: Float = 0.5
        var tailFast: Float = 0.8
        /// Học lệch tay cá nhân (`learnOffset`): tốc độ EMA, trần mỗi lần (phím).
        var offsetRate: Float = 0.05
        var offsetCap: Float = 0.5
    }

    let params: Params
    private(set) var layout: SwipeLayout?

    // template: dạng f, điểm i → tpl[(f*N + i)*2], tpl[(f*N + i)*2 + 1]
    private var tpl: [Float] = []
    private var tplCX: [Float] = [], tplCY: [Float] = [], tplScale: [Float] = []
    private var tplValid: [Bool] = []
    /// Từ vựng (theo công tắc lọc từ nhạy cảm) mà template đang dựng theo — đổi ⇒ dựng lại.
    private var tplVocab: SwipeVocab.Vocab?
    private let alpha: [Float]
    private let alphaSum: Float
    // scratch cấp sẵn
    private var ux: [Float], uy: [Float], sx: [Float], sy: [Float]
    private var topScore: [Float] = [], topIdx: [Int] = [], topDl: [Float] = []
    private var tplLen: [Float] = []
    /// Hướng đơn vị nét cuối của template (phím áp chót → phím cuối); 0 nếu 1 phím.
    private var tplDX: [Float] = [], tplDY: [Float] = []
    /// Độ sâu miễn lố [0, 1] theo điểm (1 ở điểm cuối), từ `ovFrom`.
    private let ovDepth: [Float]
    private let ovFrom: Int
    /// Hệ số miễn lố của lần decode này (`tailGate`).
    private var ovScale: Float = 0
    // nhịp (tầng 2): thời gian + tốc độ tương đối tại mx/my, điểm dừng, phạt tốc độ
    private var mt: [Float], spd: [Float], spdPen: [Float], dwells: [Int]
    private var dwellCount = 0
    private var speedOn = false
    /// Phạt tốc độ của ứng viên vừa `alignCost`.
    private var alignSpeed: Float = 0
    // tầng 2 + học lệch
    private var mx: [Float], my: [Float], dp: [Float], back: [Int], corners: [Int]
    private var cornerCount = 0
    private var rkx = [Float](repeating: 0, count: 32), rky = [Float](repeating: 0, count: 32)
    /// Mã phím ứng viên vừa `candidateKeys`; pool tầng 2: mã phím từng ứng viên (32/ô) + số phím.
    private var rkc = [UInt8](repeating: 0, count: 32)
    private var poolKeys: [UInt8] = [], poolLen: [Int] = [], poolHasH: [Bool] = []
    private let cosCorner: Float
    /// Lệch tay hệ thống của người dùng (đơn vị bề rộng phím; + = phải/xuống), trừ khỏi
    /// đường vuốt trước khi chấm. Học bằng `learnOffset`; caller lưu/khôi phục.
    var offsetX: Float = 0
    var offsetY: Float = 0
    // template tiếng Anh dựng ngay lúc chấm (không giữ): phím + điểm resample
    private var ekx = [Float](repeating: 0, count: 32), eky = [Float](repeating: 0, count: 32)
    private var erx: [Float], ery: [Float]

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
        var dep = [Float](repeating: 0, count: n)
        var from = n
        for i in 0..<n {
            dep[i] = max(0, 1 - Float(n - 1 - i) / (Float(n) * params.endSpan))
            if dep[i] > 0 && from == n { from = i }
        }
        ovDepth = dep; ovFrom = from
        ux = [Float](repeating: 0, count: n); uy = ux; sx = ux; sy = ux
        erx = ux; ery = ux
        let m2 = max(2, params.rescorePoints)
        mx = [Float](repeating: 0, count: m2); my = mx
        dp = [Float](repeating: 0, count: 32 * m2); back = [Int](repeating: 0, count: 32 * m2)
        corners = [Int](repeating: 0, count: m2)
        mt = [Float](repeating: 0, count: m2); spd = mt; spdPen = mt
        dwells = [Int](repeating: 0, count: m2)
        cosCorner = Float(cos(Double(params.cornerDegrees) * Double.pi / 180))
    }

    /// Đặt layout; khác layout cũ thì bỏ template (dựng lại lười).
    func setLayout(_ l: SwipeLayout) {
        guard l != layout else { return }
        layout = l
        tpl = []; tplCX = []; tplCY = []; tplScale = []; tplLen = []; tplValid = []
        tplDX = []; tplDY = []
        tplVocab = nil
    }

    /// Dựng template ngay (gọi ở background khi bàn phím hiện để lần vuốt
    /// đầu không trễ). An toàn gọi nhiều lần.
    func prepare() {
        guard let l = layout else { return }
        let v = SwipeVocab.current
        if tpl.isEmpty || tplVocab !== v { buildTemplates(l, v) }
    }

    /// Byte RAM template hiện giữ (test ngân sách bộ nhớ).
    var templateBytes: Int {
        tpl.count * 4 + (tplCX.count + tplCY.count + tplScale.count + tplLen.count + tplDX.count
                         + tplDY.count) * 4 + tplValid.count
    }

    private func buildTemplates(_ l: SwipeLayout, _ v: SwipeVocab.Vocab) {
        tplVocab = v
        let forms = v.forms
        let n = params.points, fc = forms.count
        tpl = [Float](repeating: 0, count: fc * n * 2)
        tplCX = [Float](repeating: 0, count: fc)
        tplCY = tplCX; tplScale = tplCX; tplLen = tplCX; tplDX = tplCX; tplDY = tplCX
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
            tplLen[f] = Self.keyPathLength(kx, ky, m, l.keyWidth)
            (tplDX[f], tplDY[f]) = Self.endDirection(kx, ky, m)
            tplValid[f] = true
        }
    }

    /// Giải mã đường vuốt → top-K dạng không dấu, điểm giảm dần.
    /// `context(folded)` (tuỳ chọn) cộng điểm ngữ cảnh (log-domain, vd từ
    /// UserLangModel với từ trước) cho `contextPool` ứng viên đầu.
    ///
    /// `english` (giai đoạn 3): thêm ~20k từ tiếng Anh vào CÙNG không gian ứng viên,
    /// điểm = hình học + λ·tần suất (cùng thang) + `english.bias`; `englishContext(từ)`
    /// là điểm ngữ cảnh riêng cho từ tiếng Anh. Sau khi xếp: tiếng Anh top-1 phải hơn
    /// ứng viên Việt tốt nhất ≥ `english.margin`, và kết quả luôn giữ ≥ 1 ứng viên ngôn
    /// ngữ kia nếu có (thanh gợi ý the ↔ thế). nil ⇒ hành vi cũ, y hệt từng bit.
    /// (Overload riêng, `english` bắt buộc: closure đuôi `decode(p, topK: k) { … }` vẫn là
    /// `context`.)
    func decode(_ path: SwipePath, topK: Int = 5,
                context: ((String) -> Float)? = nil) -> [SwipeCandidate] {
        decode(xs: path.xs, ys: path.ys, count: path.count, topK: topK, context: context, english: nil,
               englishContext: nil, ts: path.ts)
    }

    func decode(_ path: SwipePath, topK: Int = 5, context: ((String) -> Float)? = nil,
                english: SwipeEnglishPrior?,
                englishContext: ((String) -> Float)? = nil) -> [SwipeCandidate] {
        decode(xs: path.xs, ys: path.ys, count: path.count, topK: topK, context: context,
               english: english, englishContext: englishContext, ts: path.ts)
    }

    /// `ts` = thời gian điểm (giây, tuỳ gốc) — nil ⇒ không dùng nhịp (điểm như đường đều).
    func decode(xs: [Float], ys: [Float], count: Int, topK: Int = 5,
                context: ((String) -> Float)? = nil, ts: [Double]? = nil) -> [SwipeCandidate] {
        decode(xs: xs, ys: ys, count: count, topK: topK, context: context, english: nil,
               englishContext: nil, ts: ts)
    }

    func decode(xs xs0: [Float], ys ys0: [Float], count: Int, topK: Int = 5,
                context: ((String) -> Float)? = nil,
                english: SwipeEnglishPrior?,
                englishContext: ((String) -> Float)? = nil,
                ts: [Double]? = nil) -> [SwipeCandidate] {
        guard count > 0, topK > 0, let l = layout else { return [] }
        let vocab = SwipeVocab.current
        if tpl.isEmpty || tplVocab !== vocab { buildTemplates(l, vocab) }
        let forms = vocab.forms
        let en: SwipeEnglish.Lexicon? = english == nil ? nil : SwipeEnglish.lexicon
        let fc = forms.count
        let n = params.points, w = l.keyWidth
        let (xs, ys) = shifted(xs0, ys0, count, w)
        Self.resample(xs, ys, count, n, &ux, &uy)
        let pathLen = Self.keyPathLength(xs, ys, count, w)
        let (ucx, ucy, us) = Self.shapeFrame(ux, uy, n, w)
        for i in 0..<n { sx[i] = (ux[i] - ucx) * us; sy[i] = (uy[i] - ucy) * us }

        var m = context == nil && english == nil ? topK : max(topK, params.contextPool)
        if params.rescorePool > 0 { m = max(m, params.rescorePool) }
        if topScore.count < m {
            topScore = [Float](repeating: 0, count: m)
            topIdx = [Int](repeating: 0, count: m)
            topDl = [Float](repeating: 0, count: m)
        }
        var filled = 0
        let tunnelW = params.tunnel * w
        let invS = 1 / (2 * params.sigmaShape * params.sigmaShape)
        let invL = 1 / (2 * params.sigmaLoc * params.sigmaLoc)
        let lam = params.lambdaFreq
        let lw = params.lengthWeight
        ovScale = params.overshoot > 0 ? tailGate(xs, ys, ts, count) : 0
        let ov = params.overshoot * w * ovScale
        let ovStart = ov > 0 ? ovFrom : n   // điểm i ≥ ovStart được miễn lố

        tplDX.withUnsafeBufferPointer { DX in
        tplDY.withUnsafeBufferPointer { DY in
        ovDepth.withUnsafeBufferPointer { OD in
        tplLen.withUnsafeBufferPointer { TL in
        tpl.withUnsafeBufferPointer { T in
        ux.withUnsafeBufferPointer { UX in
        uy.withUnsafeBufferPointer { UY in
        sx.withUnsafeBufferPointer { SX in
        sy.withUnsafeBufferPointer { SY in
        alpha.withUnsafeBufferPointer { A in
        topScore.withUnsafeMutableBufferPointer { TS in
        topIdx.withUnsafeMutableBufferPointer { TI in
        topDl.withUnsafeMutableBufferPointer { TD in
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
                    let ddx = DX[f], ddy = DY[f]
                    for i in 0..<n {
                        let tx = T[base + i * 2], ty = T[base + i * 2 + 1]
                        let ex = SX[i] - (tx - cx) * sc, ey = SY[i] - (ty - cy) * sc
                        ds += (ex * ex + ey * ey).squareRoot()
                        var lx = UX[i] - tx, ly = UY[i] - ty
                        if i >= ovStart {
                            // lố theo hướng nét cuối (tplDX/DY đơn vị) được miễn tới ov·độ sâu
                            let al = lx * ddx + ly * ddy
                            if al > 0 {
                                let cut = min(al, ov * OD[i])
                                lx -= cut * ddx; ly -= cut * ddy
                            }
                        }
                        let d = (lx * lx + ly * ly).squareRoot() - tunnelW
                        if d > 0 { dl += A[i] * d }
                    }
                    ds = ds / Float(n)
                    dl = dl / alphaSum / w
                    var score = -(ds * ds) * invS - (dl * dl) * invL
                        + lam * Float(forms.freq[f]) / 255
                    if lw > 0 { score -= lw * Self.lengthPenalty(pathLen, TL[f]) }
                    Self.insertTop(score, f, dl, TS, TI, TD, &filled, m)
                }
                if let en, let english {
                    scoreEnglish(en, english.bias, l, r2, UX, UY, SX, SY, A, TS, TI, TD, &filled, m, fc,
                                 pathLen)
                }
                if filled >= topK { break }
            }
        }}}}}}}}}}}}}
        if params.rescorePool > 0 && filled > 0 {
            rescore(xs, ys, ts, count, l, invL, en, fc, filled)
        }

        var out: [SwipeCandidate] = []
        out.reserveCapacity(filled)
        for k in 0..<filled {
            let f = topIdx[k]
            var s = topScore[k]
            if f >= fc, let en {
                let w = en.word(f - fc)
                if let englishContext { s += englishContext(w) }
                out.append(SwipeCandidate(folded: w, score: s, lang: .en))
                continue
            }
            if let context { s += context(forms.folded[f]) }
            out.append(SwipeCandidate(folded: forms.folded[f], score: s))
        }
        if context != nil || englishContext != nil {
            // sort ổn định: bằng điểm giữ thứ tự hình học
            out = out.enumerated().sorted {
                $0.element.score != $1.element.score
                    ? $0.element.score > $1.element.score : $0.offset < $1.offset
            }.map { $0.element }
        }
        if let english { return Self.arbitrate(out, topK: topK, margin: english.margin) }
        return Array(out.prefix(topK))
    }

    /// Chấm các từ tiếng Anh lọt bộ lọc phím đầu/cuối (duyệt theo cặp phím đầu–cuối,
    /// thứ tự cố định — parity Kotlin). Template dựng ngay tại chỗ, cùng công thức VN.
    private func scoreEnglish(_ en: SwipeEnglish.Lexicon, _ bias: Float, _ l: SwipeLayout,
                              _ r2: Float,
                              _ UX: UnsafeBufferPointer<Float>, _ UY: UnsafeBufferPointer<Float>,
                              _ SX: UnsafeBufferPointer<Float>, _ SY: UnsafeBufferPointer<Float>,
                              _ A: UnsafeBufferPointer<Float>,
                              _ TS: UnsafeMutableBufferPointer<Float>,
                              _ TI: UnsafeMutableBufferPointer<Int>,
                              _ TD: UnsafeMutableBufferPointer<Float>,
                              _ filled: inout Int, _ m: Int, _ fc: Int, _ pathLen: Float) {
        let n = params.points, w = l.keyWidth
        let tunnelW = params.tunnel * w
        let invS = 1 / (2 * params.sigmaShape * params.sigmaShape)
        let invL = 1 / (2 * params.sigmaLoc * params.sigmaLoc)
        let lam = params.lambdaFreq
        let ov = params.overshoot * w * ovScale
        let ovStart = ov > 0 ? ovFrom : n, od = ovDepth
        let t = en.swipe   // bảng phím vuốt (dựng lười lần decode tiếng Anh đầu)
        // buffer cục bộ (tránh kiểm tra độc quyền truy cập property mỗi phần tử)
        var kx = ekx, ky = eky, rx = erx, ry = ery
        var okFirst = [Bool](repeating: false, count: 26), okLast = okFirst
        for k in 0..<26 {
            let x = l.centers[k * 2], y = l.centers[k * 2 + 1]
            guard x.isFinite else { continue }
            var dx = UX[0] - x, dy = UY[0] - y
            okFirst[k] = dx * dx + dy * dy <= r2
            dx = UX[n - 1] - x; dy = UY[n - 1] - y
            okLast[k] = dx * dx + dy * dy <= r2
        }
        for a in 0..<26 where okFirst[a] {
            for b in 0..<26 where okLast[b] {
                let bk = a * 26 + b
                for o in Int(t.bucketStart[bk])..<Int(t.bucketStart[bk + 1]) {
                    let i = Int(t.order[o])
                    let lo = Int(t.keyStart[i]), hi = Int(t.keyStart[i + 1])
                    guard hi - lo <= kx.count else { continue }
                    var mk = 0, ok = true
                    for j in lo..<hi {
                        let k = Int(t.keys[j])
                        let x = l.centers[k * 2]
                        guard x.isFinite else { ok = false; break }
                        kx[mk] = x; ky[mk] = l.centers[k * 2 + 1]; mk += 1
                    }
                    guard ok else { continue }
                    Self.resample(kx, ky, mk, n, &rx, &ry)
                    let (ddx, ddy) = Self.endDirection(kx, ky, mk)
                    let (cx, cy, sc) = Self.shapeFrame(rx, ry, n, w)
                    var ds: Float = 0, dl: Float = 0
                    for p in 0..<n {
                        let tx = rx[p], ty = ry[p]
                        let ex = SX[p] - (tx - cx) * sc, ey = SY[p] - (ty - cy) * sc
                        ds += (ex * ex + ey * ey).squareRoot()
                        var lx = UX[p] - tx, ly = UY[p] - ty
                        if p >= ovStart {
                            let al = lx * ddx + ly * ddy
                            if al > 0 {
                                let cut = min(al, ov * od[p])
                                lx -= cut * ddx; ly -= cut * ddy
                            }
                        }
                        let d = (lx * lx + ly * ly).squareRoot() - tunnelW
                        if d > 0 { dl += A[p] * d }
                    }
                    ds = ds / Float(n)
                    dl = dl / alphaSum / w
                    var score = -(ds * ds) * invS - (dl * dl) * invL
                        + lam * Float(en.freq[i]) / 255 + bias
                    if params.lengthWeight > 0 {
                        score -= params.lengthWeight
                            * Self.lengthPenalty(pathLen, Self.keyPathLength(kx, ky, mk, w))
                    }
                    Self.insertTop(score, fc + i, dl, TS, TI, TD, &filled, m)
                }
            }
        }
    }

    /// Phân xử ngôn ngữ trên danh sách đã xếp (thuần, parity Kotlin):
    ///  1. top-1 tiếng Anh mà có ứng viên Việt kém < margin ⇒ ứng viên Việt đó lên đầu;
    ///  2. top-K không có ngôn ngữ kia mà pool có ⇒ NỐI THÊM ứng viên tốt nhất của ngôn
    ///     ngữ kia (kết quả dài tối đa topK+1, không chiếm chỗ ứng viên cùng ngôn ngữ) —
    ///     thanh gợi ý luôn có phương án chéo.
    static func arbitrate(_ sorted: [SwipeCandidate], topK: Int, margin: Float) -> [SwipeCandidate] {
        var out = sorted
        if let first = out.first, first.lang == .en, margin > 0,
           let j = out.firstIndex(where: { $0.lang == .vi && $0.score > first.score - margin }) {
            out.insert(out.remove(at: j), at: 0)
        }
        var top = Array(out.prefix(topK))
        if topK >= 2, let lead = top.first?.lang, !top.contains(where: { $0.lang != lead }),
           let other = out.first(where: { $0.lang != lead }) {
            top.append(other)
        }
        return top
    }

    /// Bung dạng không dấu thành âm tiết có dấu, điểm = λ·tần suất/255
    /// (+ context(âm tiết)), giảm dần; bằng điểm giữ thứ tự lexicon.
    /// Theo SwipeVocab.current: lọc bật ⇒ bỏ từ nhạy cảm; thêm từ chat/viết tắt (+ tục khi tắt lọc).
    static func expand(_ folded: String, limit: Int = 8, lambdaFreq: Float = Params().lambdaFreq,
                       context: ((String) -> Float)? = nil) -> [SwipeWord] {
        guard limit > 0 else { return [] }
        let vocab = SwipeVocab.current
        let f = SwipeLexicon.index(of: folded)
        let extra = vocab.words[folded]
        guard f != nil || extra != nil else { return [] }
        var out: [(SwipeWord, Int)] = []
        if let f {
            let forms = SwipeLexicon.forms
            let lo = Int(forms.idStart[f]), hi = Int(forms.idStart[f + 1])
            out.reserveCapacity(hi - lo)
            for id in lo..<hi {
                let w = VNSuggest.display(id)
                if vocab.filter && SwipeVocab.isSensitive(w) { continue }
                if let extra, extra.contains(where: { $0.word == w }) { continue }   // bảng thay tần suất
                var s = lambdaFreq * Float(VNLexicon2Data.freq(id)) / 255
                if let context { s += context(w) }
                out.append((SwipeWord(word: w, score: s), id))
            }
        }
        for (k, e) in (extra ?? []).enumerated() {
            var s = lambdaFreq * e.score / 255
            if let context { s += context(e.word) }
            out.append((SwipeWord(word: e.word, score: s), VNLexicon2Data.count + k))
        }
        out.sort { $0.0.score != $1.0.score ? $0.0.score > $1.0.score : $0.1 < $1.1 }
        return out.prefix(limit).map { $0.0 }
    }

    // MARK: tầng 2 (chấm lại top-K) + học lệch tay — parity Kotlin

    /// Phím của ứng viên `idx` (< fc: dạng VN; ≥ fc: từ tiếng Anh) → rkx/rky; số phím,
    /// ≤ 0 = không dựng được.
    private func candidateKeys(_ idx: Int, _ l: SwipeLayout, _ en: SwipeEnglish.Lexicon?,
                               _ fc: Int) -> Int {
        let lo: Int, hi: Int
        let keys: [UInt8]
        if idx < fc {
            let forms = (tplVocab ?? SwipeVocab.current).forms
            keys = forms.keys; lo = Int(forms.keyStart[idx]); hi = Int(forms.keyStart[idx + 1])
        } else {
            guard let en else { return -1 }
            let t = en.swipe; keys = t.keys; lo = Int(t.keyStart[idx - fc]); hi = Int(t.keyStart[idx - fc + 1])
        }
        guard hi - lo <= rkx.count else { return -1 }
        var k = 0
        for j in lo..<hi {
            let c = Int(keys[j])
            guard c < 26 else { return -1 }
            let x = l.centers[c * 2]
            guard x.isFinite else { return -1 }
            rkc[k] = UInt8(c)
            rkx[k] = x; rky[k] = l.centers[c * 2 + 1]; k += 1
        }
        return k
    }

    /// Tầng 2 trên top-`filled`: σ location thích nghi (theo location tốt nhất), rồi trừ
    /// chi phí căn phím + góc; xếp lại ổn định (bằng điểm giữ thứ tự cũ).
    private func rescore(_ xs: [Float], _ ys: [Float], _ ts: [Double]?, _ count: Int, _ l: SwipeLayout,
                         _ invL: Float, _ en: SwipeEnglish.Lexicon?, _ fc: Int, _ filled: Int) {
        let w = l.keyWidth
        if params.adaptThreshold > 0 && params.adaptMax > 1 {
            var best = Float.greatestFiniteMagnitude
            for k in 0..<filled where topDl[k] < best { best = topDl[k] }
            var kk = best / params.adaptThreshold
            if kk > params.adaptMax { kk = params.adaptMax }
            if kk > 1 {
                let gain = invL * (1 - 1 / (kk * kk))
                for k in 0..<filled { topScore[k] += topDl[k] * topDl[k] * gain }
            }
        }
        Self.resample(xs, ys, count, mx.count, &mx, &my)
        detectCorners(w)
        computeSpeed(xs, ys, ts, count)
        let t = params.rescoreTunnel * w
        let bend = params.bendWeight > 0
        if bend && poolLen.count < filled {
            poolLen = [Int](repeating: 0, count: filled)
            poolKeys = [UInt8](repeating: 0, count: filled * 32)
            poolHasH = [Bool](repeating: false, count: filled)
        }
        for k in 0..<filled {
            let km = candidateKeys(topIdx[k], l, en, fc)
            if bend {
                // false = không có h giữa ⇒ bỏ qua khi ghép cặp (đa số ứng viên)
                var hasH = false
                if km > 2 { for j in 1..<(km - 1) where rkc[j] == Self.hKey { hasH = true; break } }
                poolLen[k] = km > 0 ? km : 0
                poolHasH[k] = hasH
                for j in 0..<max(km, 0) { poolKeys[k * 32 + j] = rkc[j] }
            }
            guard km > 0 else { continue }
            var cost: Float = 0
            if params.alignWeight > 0 || speedOn {
                let a = alignCost(km, t, w)
                if params.alignWeight > 0 { cost += params.alignWeight * a }
                cost += alignSpeed
            }
            if params.cornerWeight > 0 && cornerCount > 0 {
                var c: Float = 0
                for q in 0..<cornerCount {
                    c += nearestKeyCost(mx[corners[q]], my[corners[q]], km, t, w)
                }
                cost += params.cornerWeight * c
            }
            if dwellCount > 0 {
                var c: Float = 0
                for q in 0..<dwellCount {
                    c += nearestKeyCost(mx[dwells[q]], my[dwells[q]], km, t, w)
                }
                cost += params.dwellWeight * c
            }
            topScore[k] -= cost
        }
        if bend { insertionBend(l, fc, filled) }
        // insertion sort ổn định, giảm dần
        if filled > 1 {
            for i in 1..<filled {
                let s = topScore[i], id = topIdx[i], d = topDl[i]
                var j = i
                while j > 0 && topScore[j - 1] < s {
                    topScore[j] = topScore[j - 1]; topIdx[j] = topIdx[j - 1]; topDl[j] = topDl[j - 1]
                    j -= 1
                }
                topScore[j] = s; topIdx[j] = id; topDl[j] = d
            }
        }
    }

    private static let bendEps: Float = 0.01
    private static let hKey: UInt8 = 7   // 'h'
    /// Phím đứng trước h thành phụ âm ghép: Việt ch nh th ph kh gh; Anh th sh ch wh ph gh.
    private static let hAfterVI = keySet("cntpkg"), hAfterEN = keySet("tscwpg")

    private static func keySet(_ s: String) -> [Bool] {
        var m = [Bool](repeating: false, count: 26)
        for c in s.utf8 { m[Int(c) - 97] = true }
        return m
    }

    /// Cặp ứng viên B = A + một phím giữa K (cùng ngôn ngữ): B += w·kẹp(uốn − bias, ±cap), uốn =
    /// d(K, dây cung phím trước–phím sau) − d(K, đường 48 điểm) (phím). Mỗi B lấy cặp A đầu tiên.
    private func insertionBend(_ l: SwipeLayout, _ fc: Int, _ filled: Int) {
        let w = l.keyWidth
        let c = l.centers
        for b in 0..<filled {
            let nb = poolLen[b]
            if nb < 3 || !poolHasH[b] { continue }
            let bEn = topIdx[b] >= fc
            for a in 0..<filled {
                if poolLen[a] != nb - 1 || (topIdx[a] >= fc) != bEn { continue }
                var j = 0
                while j < nb - 1 && poolKeys[b * 32 + j] == poolKeys[a * 32 + j] { j += 1 }
                if j == 0 || j >= nb - 1 { continue }
                var same = true
                for q in j..<(nb - 1) where poolKeys[b * 32 + q + 1] != poolKeys[a * 32 + q] { same = false; break }
                if !same { continue }
                let kk = poolKeys[b * 32 + j]
                let kp = Int(poolKeys[b * 32 + j - 1]), kn = Int(poolKeys[b * 32 + j + 1])
                if kk != Self.hKey || !(bEn ? Self.hAfterEN : Self.hAfterVI)[kp] { continue }
                let k = Int(kk)
                let px = c[kp * 2], py = c[kp * 2 + 1], kx = c[k * 2], ky = c[k * 2 + 1]
                let nx = c[kn * 2], ny = c[kn * 2 + 1]
                let dx = nx - px, dy = ny - py
                let len2 = dx * dx + dy * dy
                var u: Float = len2 > 0 ? ((kx - px) * dx + (ky - py) * dy) / len2 : 0
                if u < 0 { u = 0 } else if u > 1 { u = 1 }
                let cx = kx - (px + u * dx), cy = ky - (py + u * dy)
                let chord = (cx * cx + cy * cy).squareRoot() / w
                if chord < params.bendMinChord || chord > params.bendMaxChord { break }
                var best = Float.greatestFiniteMagnitude
                for i in 0..<mx.count {
                    let ex = mx[i] - kx, ey = my[i] - ky
                    let q = ex * ex + ey * ey
                    if q < best { best = q }
                }
                var g = chord - best.squareRoot() / w - params.bendBias
                if g > params.bendCap { g = params.bendCap } else if g < -params.bendCap { g = -params.bendCap }
                // chỉ đổi thứ tự TRONG cặp: B mới kẹp trong [min(A, B) − ε, max(A, B) + ε]
                let sa = topScore[a], sb = topScore[b]
                var v = sb + params.bendWeight * g
                let hi = (sa > sb ? sa : sb) + Self.bendEps, lo = (sa < sb ? sa : sb) - Self.bendEps
                if v > hi { v = hi } else if v < lo { v = lo }
                topScore[b] = v
                break
            }
        }
    }

    /// Nhịp tầng 2: thời gian tại mx/my (nội suy theo độ dài như `resample`) → tốc độ tương đối
    /// spd[i] = v_i / v trung bình (sai phân trung tâm, kẹp ≤ 4), phạt tốc độ cho phím giữa
    /// (spdPen) và điểm dừng (dwells). Không có ts / thời lượng ≈ 0 ⇒ tắt (speedOn = false).
    private func computeSpeed(_ xs: [Float], _ ys: [Float], _ ts: [Double]?, _ count: Int) {
        speedOn = false; dwellCount = 0
        guard let ts, count >= 2, params.speedWeight > 0 || params.dwellWeight > 0 else { return }
        let m2 = mx.count
        Self.resampleTime(xs, ys, ts, count, m2, &mt)
        let total = mt[m2 - 1] - mt[0]
        guard total > 1e-3 else { return }
        let unit = total / Float(m2 - 1)
        for i in 0..<m2 {
            let lo = i > 0 ? i - 1 : 0
            let hi = i < m2 - 1 ? i + 1 : m2 - 1
            let dt = mt[hi] - mt[lo]
            let need = Float(hi - lo) * unit
            spd[i] = dt * 4 <= need ? 4 : need / dt
        }
        speedOn = params.speedWeight > 0
        for i in 0..<m2 {
            let e = spd[i] - params.speedRef
            spdPen[i] = e > 0 ? params.speedWeight * e : 0
        }
        guard params.dwellWeight > 0 else { return }
        let g = 2
        for i in g..<(m2 - g) {
            let v = spd[i]
            if v >= params.dwellRatio || v > spd[i - 1] || v > spd[i + 1] { continue }
            if dwellCount > 0 && i - dwells[dwellCount - 1] <= g {
                if v < spd[dwells[dwellCount - 1]] { dwells[dwellCount - 1] = i }
            } else {
                dwells[dwellCount] = i; dwellCount += 1
            }
        }
    }

    /// Đuôi nét CHẬM (trôi trước khi nhấc tay) ⇒ bật miễn lố: r = tốc độ tương đối trên endSpan
    /// độ dài cuối; r ≤ tailSlow ⇒ 1, r ≥ tailFast ⇒ 0, tuyến tính giữa. Không có ts ⇒ 0.
    private func tailGate(_ xs: [Float], _ ys: [Float], _ ts: [Double]?, _ count: Int) -> Float {
        guard let ts, count >= 2 else { return 0 }
        var total: Float = 0
        for j in 0..<(count - 1) { total += Self.segmentLength(xs, ys, j) }
        let dur = Float(ts[count - 1] - ts[0])
        guard total > 1e-4, dur > 1e-3 else { return 0 }
        let want = total * params.endSpan
        var acc: Float = 0, tail: Float = 0
        for q in 0..<(count - 1) {
            let j = count - 2 - q   // đoạn j: điểm j → j+1, từ cuối ngược lại
            let seg = Self.segmentLength(xs, ys, j)
            let dt = Float(ts[j + 1] - ts[j])
            if acc + seg >= want {
                let u: Float = seg > 0 ? (want - acc) / seg : 0
                tail += dt * u
                break
            }
            acc += seg; tail += dt
        }
        guard tail > 0 else { return 1 }
        let r = params.endSpan * dur / tail
        let g = (params.tailFast - r) / (params.tailFast - params.tailSlow)
        return g <= 0 ? 0 : (g >= 1 ? 1 : g)
    }

    /// Góc gắt trên đường resample tầng 2 (cos góc rẽ < cos `cornerDegrees`).
    private func detectCorners(_ w: Float) {
        cornerCount = 0
        guard params.cornerWeight > 0 else { return }
        let m2 = mx.count, g = 2, minLen: Float = 0.15 * w
        guard m2 > 2 * g else { return }
        for i in g..<(m2 - g) {
            let c = turnCos(i, g, minLen)
            if c >= cosCorner { continue }
            if cornerCount > 0 && i - corners[cornerCount - 1] <= g {
                if c < turnCos(corners[cornerCount - 1], g, minLen) { corners[cornerCount - 1] = i }
            } else {
                corners[cornerCount] = i; cornerCount += 1
            }
        }
    }

    /// cos góc rẽ tại điểm i (cạnh ±g điểm); cạnh < minLen ⇒ 1 (không tính là góc).
    private func turnCos(_ i: Int, _ g: Int, _ minLen: Float) -> Float {
        let ax = mx[i] - mx[i - g], ay = my[i] - my[i - g]
        let bx = mx[i + g] - mx[i], by = my[i + g] - my[i]
        let la = (ax * ax + ay * ay).squareRoot(), lb = (bx * bx + by * by).squareRoot()
        if la < minLen || lb < minLen { return 1 }
        return (ax * bx + ay * by) / (la * lb)
    }

    /// (khoảng cách tới phím gần nhất của ứng viên − tunnel)², đơn vị phím.
    private func nearestKeyCost(_ x: Float, _ y: Float, _ km: Int, _ t: Float, _ w: Float) -> Float {
        var best = Float.greatestFiniteMagnitude
        for j in 0..<km {
            let dx = x - rkx[j], dy = y - rky[j]
            var d = ((dx * dx + dy * dy).squareRoot() - t) / w
            if d < 0 { d = 0 }
            if d < best { best = d }
        }
        return best * best
    }

    /// Căn đơn điệu km phím (rkx/rky) vào mx/my: trung bình (d − tunnel)² nhỏ nhất (phím).
    /// Cùng vòng: `alignSpeed` = Σ spdPen tại điểm đường GẦN NHẤT mỗi phím giữa (phím nằm trên đoạn
    /// lướt nhanh ⇒ không phải phím định đi); lấy điểm gần nhất, không theo căn DP, để DP không
    /// "giấu" phím thừa vào chỗ dừng.
    private func alignCost(_ km: Int, _ t: Float, _ w: Float) -> Float {
        let m2 = mx.count
        let sp = speedOn
        var speed: Float = 0
        // con trỏ thô: vòng nóng nhất tầng 2 (16 ứng viên × km × 48)
        let r = spdPen.withUnsafeBufferPointer { SP in
        mx.withUnsafeBufferPointer { MX in
        my.withUnsafeBufferPointer { MY in
        rkx.withUnsafeBufferPointer { KX in
        rky.withUnsafeBufferPointer { KY in
        dp.withUnsafeMutableBufferPointer { DP -> Float in
            for j in 0..<km {
                var run = Float.greatestFiniteMagnitude
                let mid = sp && j > 0 && j < km - 1
                var bq = Float.greatestFiniteMagnitude, bi = 0
                for i in 0..<m2 {
                    let dx = MX[i] - KX[j], dy = MY[i] - KY[j]
                    let q = dx * dx + dy * dy
                    if mid && q < bq { bq = q; bi = i }
                    var d = (q.squareRoot() - t) / w
                    if d < 0 { d = 0 }
                    var prev: Float = 0
                    if j > 0 { let v = DP[(j - 1) * m2 + i]; if v < run { run = v }; prev = run }
                    DP[j * m2 + i] = d * d + prev
                }
                if mid { speed += SP[bi] }
            }
            var best = Float.greatestFiniteMagnitude
            for i in 0..<m2 { let v = DP[(km - 1) * m2 + i]; if v < best { best = v } }
            return best / Float(km)
        }}}}}}
        alignSpeed = speed
        return r
    }

    /// Đường trừ lệch tay (`offsetX`/`offsetY`); không lệch ⇒ chính mảng gốc.
    private func shifted(_ xs: [Float], _ ys: [Float], _ count: Int, _ w: Float) -> ([Float], [Float]) {
        guard offsetX != 0 || offsetY != 0 else { return (xs, ys) }
        let ox = offsetX * w, oy = offsetY * w
        var bx = [Float](repeating: 0, count: count), by = bx
        for i in 0..<count { bx[i] = xs[i] - ox; by[i] = ys[i] - oy }
        return (bx, by)
    }

    /// Học lệch tay từ một lượt vuốt người dùng ĐÃ CHẤP NHẬN là dạng `folded` (không dấu,
    /// có trong lexicon): căn phím vào đường (đã trừ lệch hiện tại), lệch trung bình (kẹp
    /// ±`offsetCap` phím) → EMA `offsetRate` vào `offsetX`/`offsetY`.
    /// false = không học (chưa có layout / dạng lạ / đường < 2 điểm).
    @discardableResult
    func learnOffset(xs xs0: [Float], ys ys0: [Float], count: Int, folded: String) -> Bool {
        guard let l = layout, count >= 2, params.offsetRate > 0,
              case let v = tplVocab ?? SwipeVocab.current,
              let f = v.index(of: folded) else { return false }
        let km = candidateKeys(f, l, nil, v.forms.count)
        guard km > 0 else { return false }
        let w = l.keyWidth
        let (xs, ys) = shifted(xs0, ys0, count, w)
        let m2 = mx.count
        Self.resample(xs, ys, count, m2, &mx, &my)
        for j in 0..<km {
            var run = Float.greatestFiniteMagnitude, runI = 0
            for i in 0..<m2 {
                let dx = mx[i] - rkx[j], dy = my[i] - rky[j]
                let d = (dx * dx + dy * dy).squareRoot() / w
                var prev: Float = 0
                if j > 0 {
                    let v = dp[(j - 1) * m2 + i]
                    if v < run { run = v; runI = i }
                    prev = run; back[j * m2 + i] = runI
                }
                dp[j * m2 + i] = d * d + prev
            }
        }
        var bi = 0
        for i in 1..<m2 where dp[(km - 1) * m2 + i] < dp[(km - 1) * m2 + bi] { bi = i }
        var sx: Float = 0, sy: Float = 0
        var pos = bi
        for j in stride(from: km - 1, through: 0, by: -1) {
            sx += mx[pos] - rkx[j]; sy += my[pos] - rky[j]
            if j > 0 { pos = back[j * m2 + pos] }
        }
        let cap = params.offsetCap
        let dx = min(max(sx / Float(km) / w, -cap), cap)
        let dy = min(max(sy / Float(km) / w, -cap), cap)
        offsetX += params.offsetRate * dx
        offsetY += params.offsetRate * dy
        return true
    }

    @discardableResult
    func learnOffset(_ path: SwipePath, folded: String) -> Bool {
        learnOffset(xs: path.xs, ys: path.ys, count: path.count, folded: folded)
    }

    /// Hướng đơn vị phím áp chót → phím cuối ((0, 0) nếu < 2 phím / trùng).
    static func endDirection(_ kx: [Float], _ ky: [Float], _ m: Int) -> (Float, Float) {
        guard m >= 2 else { return (0, 0) }
        let dx = kx[m - 1] - kx[m - 2], dy = ky[m - 1] - ky[m - 2]
        let d = (dx * dx + dy * dy).squareRoot()
        return d > 0 ? (dx / d, dy / d) : (0, 0)
    }

    /// Độ dài polyline (count điểm) theo đơn vị phím.
    static func keyPathLength(_ xs: [Float], _ ys: [Float], _ count: Int, _ keyWidth: Float) -> Float {
        var s: Float = 0
        if count > 1 {
            for j in 0..<(count - 1) {
                let dx = xs[j + 1] - xs[j], dy = ys[j + 1] - ys[j]
                s += (dx * dx + dy * dy).squareRoot()
            }
        }
        return s / keyWidth
    }

    /// ≈ ln²((a+1)/(b+1)) bằng 2(a−b)/(a+b+2) (xấp xỉ Padé của ln, bão hoà ở ±2 khi lệch
    /// lớn) — thuần + − × ÷ nên Swift/Kotlin ra cùng bit.
    static func lengthPenalty(_ a: Float, _ b: Float) -> Float {
        let r = 2 * (a - b) / (a + b + 2)
        return r * r
    }

    // MARK: hàm thuần (cùng thứ tự phép tính với bản Kotlin)

    /// Chèn (score, idx) vào top-m giảm dần; bằng điểm → phần tử vào trước
    /// (idx nhỏ hơn) đứng trước.
    private static func insertTop(_ s: Float, _ idx: Int, _ dl: Float,
                                  _ ts: UnsafeMutableBufferPointer<Float>,
                                  _ ti: UnsafeMutableBufferPointer<Int>,
                                  _ td: UnsafeMutableBufferPointer<Float>,
                                  _ filled: inout Int, _ m: Int) {
        if filled == m && s <= ts[m - 1] { return }
        var pos = filled < m ? filled : m - 1
        while pos > 0 && ts[pos - 1] < s {
            ts[pos] = ts[pos - 1]; ti[pos] = ti[pos - 1]; td[pos] = td[pos - 1]; pos -= 1
        }
        ts[pos] = s; ti[pos] = idx; td[pos] = dl
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

    /// Thời gian (giây, gốc = ts[0], Float) tại n điểm resample của `resample` — cùng vòng
    /// duyệt, nội suy tuyến tính trong đoạn.
    static func resampleTime(_ xs: [Float], _ ys: [Float], _ ts: [Double], _ count: Int, _ n: Int,
                             _ ot: inout [Float]) {
        var total: Float = 0
        if count > 1 {
            for j in 0..<(count - 1) {
                let dx = xs[j + 1] - xs[j], dy = ys[j + 1] - ys[j]
                total += (dx * dx + dy * dy).squareRoot()
            }
        }
        let t0 = ts[0]
        if count == 1 || total <= 1e-4 {
            for k in 0..<n { ot[k] = 0 }
            return
        }
        let step = total / Float(n - 1)
        ot[0] = 0
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
            let a = Float(ts[j] - t0), b = Float(ts[j + 1] - t0)
            ot[k] = a + (b - a) * t
        }
        ot[n - 1] = Float(ts[count - 1] - t0)
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
