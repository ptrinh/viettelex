// FutoSwipe.swift — decoder gõ vuốt THỬ NGHIỆM dùng encoder FUTO Swipe (FutoSwipeModel,
// "powered by FUTO Swipe"), sau công tắc KeyboardSettings.swipeFuto (mặc định TẮT). Bản Kotlin
// song sinh: android/keyboard/src/main/kotlin/com/viettelex/keyboard/FutoSwipe.kt.
//
// Công tắc TẮT ⇒ lớp này không được tạo, không tải gì, đường gõ vuốt SHARK2 y nguyên. Bật ⇒
// `load()` (hàng đợi nền của SwipeTyping) đọc asset fp16 → model; `release()` khi ẩn bàn phím /
// cảnh báo bộ nhớ; decode lúc model chưa sẵn trả nil ⇒ caller dùng SHARK2 như cũ.
//
// Luồng decode: (1) đường vuốt → chuẩn hoá theo khung vùng phím chữ (bbox tâm phím ± nửa phím,
// 3 hàng) về 0–1, kẹp; resample theo THỜI GIAN 60 Hz rồi 64 điểm (như FUTO); (2) encoder →
// log-xác suất phím 32 bước (CTC); (3) âm học mỗi từ = CTC Viterbi của chuỗi phím đã gộp chữ
// lặp, tìm trên từ vựng theo tiền tố (dùng lại cột của tiền tố chung, cắt nhánh bằng cận trên
// max_t α); (4) ENSEMBLE (mặc định) = điểm SHARK2 + β·(âm học − tốt nhất) trên pool SHARK2 ∪ top
// âm học; FUTO = A·âm học + λ·tần suất (+ bias Anh) + ngữ cảnh. KHÔNG thread-safe.
import Foundation

final class FutoSwipe {
    enum Mode { case ensemble, futo }

    struct Params {
        var mode: Mode = .ensemble
        /// Mode.futo: trọng số âm học (log-prob CTC) so với λ·tần suất/ngữ cảnh.
        var acousticWeight: Float = 0.5
        /// Mode.ensemble: trọng số âm học cộng vào điểm SHARK2.
        var ensembleWeight: Float = 0.1
        /// Âm học thấp nhất khi từ không chấm được (kẹp phạt).
        var ensembleFloor: Float = -30
        /// Số ứng viên âm học tốt nhất nhập thêm vào pool ensemble.
        var ensembleExtra = 4
        /// Pool đem cộng ngữ cảnh — như SwipeDecoder.Params.contextPool.
        var pool = 16
    }

    var params = Params()
    private let source: () -> Data?
    private var model: FutoSwipeModel?
    private var loadFailed = false
    private var layout: SwipeLayout?
    private var keyXY = [Float](repeating: 0, count: 52)
    /// chữ a…z → cột trong đầu ra model (−1 = layout không có phím).
    private var classOf = [Int](repeating: -1, count: 26)
    private var nk = 0
    private var frameX: Float = 0, frameW: Float = 1, frameY: Float = 0, frameH: Float = 1
    // scratch
    private var feats = [Float](repeating: 0, count: 128)
    private var em = [Float](repeating: 0, count: 32 * 27)
    private var px: [Float] = [], py: [Float] = [], pt: [Float] = []
    private var gx: [Float] = [], gy: [Float] = []
    private static let T2 = FutoSwipeModel.T2, maxDepth = 32
    private var nb = [Float](repeating: 0, count: 32 * 32)
    private var bl = [Float](repeating: 0, count: 32 * 32)
    private var bl0 = [Float](repeating: 0, count: 32)
    private var stack = [Int](repeating: 0, count: 32)
    private var topScore = [Float](repeating: 0, count: 64), topAc = [Float](repeating: 0, count: 64)
    private var topIdx = [Int](repeating: 0, count: 64)
    private var topFilled = 0
    /// Có emissions hợp lệ cho đường vuốt cuối cùng.
    private(set) var hasEmissions = false
    /// Thời gian encoder lần cuối (ms).
    private(set) var lastModelMs: Double = 0

    init(source: @escaping () -> Data?) { self.source = source }

    /// Asset trong bundle bàn phím (mmap; không có ⇒ nil).
    static func bundledWeights() -> Data? {
        final class BundleToken {}
        guard let url = Bundle(for: BundleToken.self).url(forResource: "futoswipe", withExtension: "bin") else { return nil }
        return try? Data(contentsOf: url, options: .alwaysMapped)
    }

    var isLoaded: Bool { model != nil }

    /// Tải model (hàng đợi nền). An toàn gọi lại; hỏng thì không thử lại tới `release()`.
    @discardableResult
    func load() -> Bool {
        if model != nil { return true }
        if loadFailed { return false }
        guard let d = source(), let m = FutoSwipeModel.load(d) else { loadFailed = true; return false }
        model = m
        return true
    }

    /// Nhả model (ẩn bàn phím / cảnh báo bộ nhớ / tắt công tắc).
    func release() {
        model = nil
        loadFailed = false
        hasEmissions = false
    }

    func setLayout(_ l: SwipeLayout) {
        guard l != layout else { return }
        layout = l
        var minX = Float.infinity, maxX = -Float.infinity, minY = Float.infinity, maxY = -Float.infinity
        for k in 0..<26 {
            let x = l.centers[2 * k], y = l.centers[2 * k + 1]
            guard x.isFinite else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        let kw = l.keyWidth
        frameX = minX - kw / 2; frameW = max(maxX - minX + kw, 1e-3)
        let rh = max((maxY - minY) / 2, 1e-3)
        frameY = minY - rh / 2; frameH = 3 * rh
        nk = 0
        for k in 0..<26 {
            let x = l.centers[2 * k]
            guard x.isFinite else { classOf[k] = -1; continue }
            classOf[k] = nk
            keyXY[2 * nk] = (x - frameX) / frameW
            keyXY[2 * nk + 1] = (l.centers[2 * k + 1] - frameY) / frameH
            nk += 1
        }
        hasEmissions = false
    }

    /// Toạ độ chuẩn hoá của phím (test).
    func normalizedKeys() -> [Float] { Array(keyXY.prefix(2 * nk)) }

    /// Bước 1: đường vuốt → 128 đặc trưng (x hàng rồi y hàng). `ts` giây. Cùng thuật toán
    /// Scripts/futo-swipe/gen_fixture.py (làm tròn floor(x+0.5)).
    func features(xs: [Float], ys: [Float], ts: [Double], count: Int) -> [Float] {
        if px.count < count {
            px = [Float](repeating: 0, count: count); py = px; pt = px
        }
        for i in 0..<count {
            px[i] = min(max((xs[i] - frameX) / frameW, 0), 1)
            py[i] = min(max((ys[i] - frameY) / frameH, 0), 1)
            pt[i] = Float((ts[i] - ts[0]) * 1000)
        }
        resampleTime(count)
        return feats
    }

    private func resampleTime(_ count: Int) {
        let tn = FutoSwipeModel.T
        let tEnd = pt[count - 1]
        var n = count
        var useGrid = false
        if count > 1 && tEnd > 1e-3 {
            let n60 = max(2, Int(floor(tEnd / (1000 / 60) + 0.5)) + 1)
            if gx.count < n60 { gx = [Float](repeating: 0, count: n60); gy = gx }
            var j = 0
            for i in 0..<n60 {
                let tt = tEnd * Float(i) / Float(n60 - 1)
                while j < count - 2 && pt[j + 1] < tt { j += 1 }
                let t0 = pt[j], t1 = pt[j + 1]
                let a: Float = t1 > t0 ? min(max((tt - t0) / (t1 - t0), 0), 1) : 0
                gx[i] = px[j] + a * (px[j + 1] - px[j])
                gy[i] = py[j] + a * (py[j + 1] - py[j])
            }
            n = n60; useGrid = true
        }
        let sx = useGrid ? gx : px, sy = useGrid ? gy : py
        for i in 0..<tn {
            if n == 1 { feats[i] = sx[0]; feats[tn + i] = sy[0]; continue }
            let pos = Float(n - 1) * Float(i) / Float(tn - 1)
            let j = min(Int(pos), max(n - 2, 0))
            let a = pos - Float(j)
            feats[i] = sx[j] + a * (sx[j + 1] - sx[j])
            feats[tn + i] = sy[j] + a * (sy[j + 1] - sy[j])
        }
    }

    /// Bước 2: encoder trên đường vuốt → emissions nội bộ. false nếu chưa có model/layout.
    @discardableResult
    func computeEmissions(xs: [Float], ys: [Float], ts: [Double], count: Int) -> Bool {
        hasEmissions = false
        guard let m = model, layout != nil, nk > 0, count >= 1 else { return false }
        _ = features(xs: xs, ys: ys, ts: ts, count: count)
        if em.count < Self.T2 * (nk + 1) { em = [Float](repeating: 0, count: Self.T2 * (nk + 1)) }
        let t0 = CFAbsoluteTimeGetCurrent()
        m.run(feats, keyXY, nk, &em)
        lastModelMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        hasEmissions = true
        return true
    }

    func emissions() -> [Float] { Array(em.prefix(Self.T2 * (nk + 1))) }

    /// Bước 3: CTC Viterbi (log) của chuỗi phím đã gộp chữ lặp, trên emissions hiện có.
    func score(_ keys: [UInt8], _ lo: Int, _ hi: Int) -> Float {
        guard hasEmissions, hi > lo, hi - lo <= Self.maxDepth else { return -.infinity }
        initBlank()
        for d in 0..<(hi - lo) {
            let c = classOf[Int(keys[lo + d])]
            guard c >= 0 else { return -.infinity }
            extend(d, c)
        }
        let base = (hi - lo - 1) * Self.T2 + Self.T2 - 1
        return max(nb[base], bl[base])
    }

    func score(_ word: String) -> Float {
        var b: [UInt8] = []
        var last = -1
        for ch in word.unicodeScalars {
            let k = Int(ch.value) - 97
            guard k >= 0 && k < 26 else { return -.infinity }
            if k != last { b.append(UInt8(k)); last = k }
        }
        return score(b, 0, b.count)
    }

    private func initBlank() {
        let stride = nk + 1
        var acc: Float = 0
        for t in 0..<Self.T2 { acc += em[t * stride + nk]; bl0[t] = acc }
    }

    /// Cột CTC cho tiền tố độ sâu d (kết thúc bằng phím c), từ độ sâu d−1 (hoặc rỗng).
    private func extend(_ d: Int, _ c: Int) {
        let stride = nk + 1, T2 = Self.T2
        let o = d * T2, q = (d - 1) * T2
        let neg = -Float.infinity
        for t in 0..<T2 {
            let e = em[t * stride + c]
            let from: Float
            if t == 0 {
                from = d == 0 ? 0 : neg
            } else {
                let a = nb[o + t - 1]
                let b = d == 0 ? bl0[t - 1] : max(bl[q + t - 1], nb[q + t - 1])
                from = max(a, b)
            }
            nb[o + t] = e + from
            bl[o + t] = t == 0 ? neg : em[t * stride + nk] + max(bl[o + t - 1], nb[o + t - 1])
        }
    }

    private func bound(_ d: Int) -> Float {
        var m = -Float.infinity
        let o = d * Self.T2
        for t in 0..<Self.T2 where nb[o + t] > m { m = nb[o + t] }
        return m
    }

    /// Tìm trên từ vựng: top-`m` theo prior = `w`·âm học + λ·tần suất/255 (+ `enBias` cho từ Anh).
    /// Chỉ số < fc = dạng Việt; ≥ fc = từ tiếng Anh.
    func search(_ m: Int, _ w: Float, _ lambdaFreq: Float, _ en: SwipeEnglish.Lexicon?, _ enBias: Float) {
        topFilled = 0
        guard hasEmissions else { return }
        initBlank()
        let forms = SwipeLexicon.forms
        let fc = forms.count
        let maxPrior = lambdaFreq + (en != nil ? max(0, enBias) : 0)
        searchList(forms.keys, forms.keyStart, fc, 0, { Int(forms.freq[$0]) }, m, w, lambdaFreq, 0, maxPrior)
        if let en {
            let t = en.swipe
            searchList(t.keys, t.keyStart, en.count, fc, { Int(en.freq[$0]) }, m, w, lambdaFreq, enBias, maxPrior)
        }
    }

    /// Kết quả `search`: (chỉ số, âm học) theo điểm giảm dần.
    func top() -> [(Int, Float)] { (0..<topFilled).map { (topIdx[$0], topAc[$0]) } }

    private func searchList(_ keys: [UInt8], _ keyStart: [Int32], _ n: Int, _ idxBase: Int, _ freq: (Int) -> Int,
                            _ m: Int, _ w: Float, _ lam: Float, _ bias: Float, _ maxPrior: Float) {
        var depth = 0
        var prunedLen = -1
        let T2 = Self.T2
        for i in 0..<n {
            let lo = Int(keyStart[i]), len = Int(keyStart[i + 1]) - lo
            if len <= 0 || len > Self.maxDepth { continue }
            if prunedLen > 0 && len >= prunedLen {
                var same = true
                for d in 0..<prunedLen where stack[d] != Int(keys[lo + d]) { same = false; break }
                if same { continue }
            }
            prunedLen = -1
            var l = 0
            let lim = min(depth, len)
            while l < lim && stack[l] == Int(keys[lo + l]) { l += 1 }
            depth = l
            var ok = true
            let thr = topFilled == m ? topScore[m - 1] : -Float.infinity
            while depth < len {
                let k = Int(keys[lo + depth])
                let c = classOf[k]
                if c < 0 { ok = false; break }
                stack[depth] = k
                extend(depth, c)
                depth += 1
                if depth < len && thr > -Float.infinity && w * bound(depth - 1) + maxPrior < thr {
                    prunedLen = depth; ok = false; break
                }
            }
            if !ok { continue }
            let base = (len - 1) * T2 + T2 - 1
            let ac = max(nb[base], bl[base])
            if ac == -Float.infinity { continue }
            insertTop(w * ac + lam * Float(freq(i)) / 255 + bias, ac, idxBase + i, m)
        }
    }

    private func insertTop(_ s: Float, _ ac: Float, _ idx: Int, _ m: Int) {
        if topFilled == m && s <= topScore[m - 1] { return }
        var pos = topFilled < m ? topFilled : m - 1
        while pos > 0 && topScore[pos - 1] < s {
            topScore[pos] = topScore[pos - 1]; topAc[pos] = topAc[pos - 1]; topIdx[pos] = topIdx[pos - 1]; pos -= 1
        }
        topScore[pos] = s; topAc[pos] = ac; topIdx[pos] = idx
        if topFilled < m { topFilled += 1 }
    }

    /// Giải mã một cú vuốt. nil ⇒ model chưa sẵn (caller dùng SHARK2). `shark` cần cho
    /// .ensemble (đã setLayout). Tham số khác y như SwipeDecoder.decode.
    func decode(_ path: SwipePath, topK: Int, context: ((String) -> Float)?, english: SwipeEnglishPrior?,
                englishContext: ((String) -> Float)?, shark: SwipeDecoder?,
                reuseEmissions: Bool = false) -> [SwipeCandidate]? {
        if !(reuseEmissions && hasEmissions) {
            guard computeEmissions(xs: path.xs, ys: path.ys, ts: path.ts, count: path.count) else { return nil }
        }
        let lam = SwipeDecoder.Params().lambdaFreq
        let en: SwipeEnglish.Lexicon? = english == nil ? nil : SwipeEnglish.lexicon
        let forms = SwipeLexicon.forms
        let fc = forms.count
        var out: [SwipeCandidate] = []
        if params.mode == .ensemble, let shark {
            let pool = shark.decode(path, topK: max(topK, params.pool), context: context, english: english,
                                    englishContext: englishContext)
            search(max(1, params.ensembleExtra), 1, 0, en, 0)
            let acs = pool.map { score($0.folded) }
            var best = -Float.infinity
            for a in acs where a > best { best = a }
            for k in 0..<topFilled where topAc[k] > best { best = topAc[k] }
            let floorAc = best + params.ensembleFloor
            var seen = Set<String>()
            var minShark = Float.infinity
            for (i, c) in pool.enumerated() {
                seen.insert(c.folded)
                if c.score < minShark { minShark = c.score }
                out.append(SwipeCandidate(folded: c.folded,
                                          score: c.score + params.ensembleWeight * (max(acs[i], floorAc) - best),
                                          lang: c.lang))
            }
            // ứng viên âm học mạnh mà SHARK2 bỏ sót: điểm gốc = SHARK2 kém nhất của pool
            if !pool.isEmpty {
                for k in 0..<topFilled {
                    let idx = topIdx[k]
                    let isEn = idx >= fc
                    let word = isEn ? en!.word(idx - fc) : forms.folded[idx]
                    guard seen.insert(word).inserted else { continue }
                    var s = minShark + params.ensembleWeight * (topAc[k] - best)
                    if !isEn, let context { s += context(word) }
                    if isEn, let english { s += english.bias; if let englishContext { s += englishContext(word) } }
                    out.append(SwipeCandidate(folded: word, score: s, lang: isEn ? .en : .vi))
                }
            }
        } else {
            search(max(topK, params.pool), params.acousticWeight, lam, en, english?.bias ?? 0)
            for k in 0..<topFilled {
                let idx = topIdx[k]
                var s = topScore[k]
                if idx >= fc {
                    let word = en!.word(idx - fc)
                    if let englishContext { s += englishContext(word) }
                    out.append(SwipeCandidate(folded: word, score: s, lang: .en))
                } else {
                    let word = forms.folded[idx]
                    if let context { s += context(word) }
                    out.append(SwipeCandidate(folded: word, score: s))
                }
            }
        }
        let sorted = out.enumerated().sorted {
            $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset
        }.map(\.element)
        if let english { return SwipeDecoder.arbitrate(sorted, topK: topK, margin: english.margin) }
        return Array(sorted.prefix(topK))
    }
}
