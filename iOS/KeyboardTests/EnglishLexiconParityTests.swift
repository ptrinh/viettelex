// enlexicon đọc tại chỗ trên mmap (10/11/2026, iOS/docs/RAM-AUDIT.md §4d):
//  • kết quả tra cứu y hệt bản cũ (giải mã ra [String] + bảng phím) trên TOÀN BỘ lexicon —
//    `Legacy` dưới đây là bản cũ chép nguyên văn, chỉ dùng cho test;
//  • bảng phím vuốt chỉ dựng khi gõ vuốt tiếng Anh cần;
//  • từ trước là âm tiết Việt không chạm lexicon tiếng Anh (padsWithTopWords);
//  • main thread không bao giờ nạp lexicon (containsIfLoaded / topIfLoaded).
import XCTest

final class EnglishLexiconParityTests: XCTestCase {

    // MARK: bản cũ (trước 10/11/2026), chép nguyên văn

    private struct Legacy {
        let words: [String], freq: [UInt8], keys: [UInt8], keyStart: [Int32], order: [Int32], bucketStart: [Int32]

        static func parse(_ d: Data) -> Legacy? {
            let b = [UInt8](d)
            guard b.count >= 8, b[0] == 0x56, b[1] == 0x54, b[2] == 0x45, b[3] == 0x31 else { return nil }
            let n = Int(b[4]) | Int(b[5]) << 8 | Int(b[6]) << 16 | Int(b[7]) << 24
            var words: [String] = [], freq: [UInt8] = [], keys: [UInt8] = [], keyStart: [Int32] = [0]
            var first = [Int](repeating: 0, count: n), last = first
            var p = 8
            for i in 0..<n {
                guard p + 2 <= b.count else { return nil }
                let len = Int(b[p]), f = b[p + 1]
                guard len > 0, p + 2 + len <= b.count else { return nil }
                var prev: UInt8 = 255
                for j in 0..<len {
                    let k = b[p + 2 + j] &- 97
                    guard k < 26 else { return nil }
                    if k != prev { keys.append(k); prev = k }
                }
                first[i] = Int(keys[Int(keyStart[i])]); last[i] = Int(keys[keys.count - 1])
                keyStart.append(Int32(keys.count))
                words.append(String(decoding: b[(p + 2)..<(p + 2 + len)], as: UTF8.self))
                freq.append(f)
                p += 2 + len
            }
            var bucketStart = [Int32](repeating: 0, count: 677)
            for i in 0..<n { bucketStart[first[i] * 26 + last[i] + 1] += 1 }
            for bk in 0..<676 { bucketStart[bk + 1] += bucketStart[bk] }
            var fill = Array(bucketStart[0..<676])
            var order = [Int32](repeating: 0, count: n)
            for i in 0..<n {
                let bk = first[i] * 26 + last[i]
                order[Int(fill[bk])] = Int32(i); fill[bk] += 1
            }
            return Legacy(words: words, freq: freq, keys: keys, keyStart: keyStart, order: order, bucketStart: bucketStart)
        }

        func index(of word: String) -> Int? {
            let a = words
            var lo = 0, hi = a.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if a[mid] < word { lo = mid + 1 } else { hi = mid }
            }
            return lo < a.count && a[lo] == word ? lo : nil
        }

        func completions(_ typed: String, limit: Int = 24) -> [VNSuggest.Match] {
            let low = typed.lowercased()
            guard !low.isEmpty, limit > 0,
                  low.unicodeScalars.allSatisfy({ $0.value >= 97 && $0.value <= 122 }) else { return [] }
            let a = words
            var lo = 0, hi = a.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if a[mid] < low { lo = mid + 1 } else { hi = mid }
            }
            var hits: [(f: UInt8, i: Int)] = []
            var i = lo
            while i < a.count, a[i].hasPrefix(low) {
                if a[i] != low { hits.append((freq[i], i)) }
                i += 1
            }
            hits.sort { $0.f != $1.f ? $0.f > $1.f : $0.i < $1.i }
            return hits.prefix(limit).map { VNSuggest.Match(word: SwipeEnglish.matchCase(a[$0.i], typed), freq: Int($0.f)) }
        }

        func topWords(limit: Int) -> [String] {
            guard limit > 0 else { return [] }
            return freq.indices.sorted { freq[$0] != freq[$1] ? freq[$0] > freq[$1] : $0 < $1 }
                .prefix(limit).map { words[$0] }
        }

        func corrections(_ low: String, limit: Int = EnglishAssist.typoLimit) -> [String] {
            let r = Array(low.utf8)
            let n = r.count
            guard n >= EnglishAssist.typoMinLen, let first = r.first else { return [] }
            let maxD = n >= EnglishAssist.typoLongLen ? 2 : 1
            let a = words
            func lower(_ key: String) -> Int {
                var lo = 0, hi = a.count
                while lo < hi {
                    let mid = (lo + hi) / 2
                    if a[mid] < key { lo = mid + 1 } else { hi = mid }
                }
                return lo
            }
            let start = lower(String(UnicodeScalar(first)))
            let end = first >= 122 ? a.count : lower(String(UnicodeScalar(first + 1)))
            var hits: [(d: Int, whole: Bool, f: Int, i: Int)] = []
            let rows = UnsafeMutablePointer<Int>.allocate(capacity: 3 * (n + 1))
            defer { rows.deallocate() }
            r.withUnsafeBufferPointer { rb in
                var i = start
                while i < end {
                    defer { i += 1 }
                    let f = Int(freq[i])
                    guard f >= EnglishAssist.typoMinFreq else { continue }
                    var word = a[i]
                    let m = word.utf8.count
                    guard m >= n - maxD else { continue }
                    let d = word.withUTF8 { EnglishAssist.distance($0, rb, maxD: maxD, rows: rows) }
                    if let full = d.full, full > 0 {
                        hits.append((full, true, f, i))
                    } else if m > n, let p = d.prefix, p > 0 {
                        hits.append((p, false, f, i))
                    }
                }
            }
            hits.sort {
                if $0.whole != $1.whole { return $0.whole }
                if $0.d != $1.d { return $0.d < $1.d }
                return $0.f != $1.f ? $0.f > $1.f : $0.i < $1.i
            }
            return hits.prefix(limit).map { a[$0.i] }
        }
    }

    // MARK: dữ liệu

    private func fileData() throws -> Data {
        let url = try XCTUnwrap(VTBundleResource.url("enlexicon", "bin", anchor: KeyboardView.self))
        return try Data(contentsOf: url)
    }

    // MARK: parity toàn bộ lexicon

    func testParityWholeLexicon() throws {
        let data = try fileData()
        let old = try XCTUnwrap(Legacy.parse(data))
        let new = try XCTUnwrap(SwipeEnglish.parse(data))
        let live = SwipeEnglish.lexicon     // đường thật: NSData mmap
        XCTAssertGreaterThan(old.words.count, 10_000)
        for lex in [new, live] {
            XCTAssertEqual(lex.count, old.words.count)
            XCTAssertEqual(lex.allWords(), old.words)
            XCTAssertEqual(lex.freq, old.freq)
        }

        // Thành viên + tần suất: mọi từ, và từ KHÔNG có (biến dạng mỗi từ, chữ hoa, có dấu, ký tự lạ).
        var probes = 0
        for (i, w) in old.words.enumerated() {
            XCTAssertEqual(SwipeEnglish.index(of: w, in: new), i, w)
            XCTAssertEqual(SwipeEnglish.index(of: w), i, w)
            // Từ không có: mọi từ thêm/bớt một chữ; biến dạng khác lấy mẫu (bản cũ so String chậm ở Debug).
            var misses = [w + "q", String(w.dropLast())]
            if i % 10 == 0 { misses += [w.uppercased(), w.capitalized, w + "é", "é" + w, w + " "] }
            if i % 50 == 0 { misses += [w.replacingOccurrences(of: "e", with: "ê"), "\u{212A}" + w, w + "\u{0301}"] }
            for m in misses {
                XCTAssertEqual(SwipeEnglish.index(of: m, in: new), old.index(of: m), m)
                probes += 1
            }
        }
        for m in ["", "a", "zzzz", "\u{212A}", "\u{212A}elvin", "kelvin", "café", "naïve", "e\u{0301}", "中文", "1st", "A"] {
            XCTAssertEqual(SwipeEnglish.index(of: m, in: new), old.index(of: m), m)
            XCTAssertEqual(SwipeEnglish.contains(m), old.index(of: m) != nil, m)
        }

        // Hoàn thành tiền tố: MỌI tiền tố của mọi từ (limit 24), đủ thứ tự cho tiền tố ≤ 2 chữ.
        var prefixes = Set<String>()
        for w in old.words { for n in 1...w.count { prefixes.insert(String(w.prefix(n))) } }
        for p in prefixes {
            XCTAssertEqual(SwipeEnglish.completions(p, in: new), old.completions(p), p)
        }
        for p in prefixes where p.count <= 2 {
            XCTAssertEqual(SwipeEnglish.completions(p, limit: 100_000, in: new), old.completions(p, limit: 100_000), p)
        }
        for p in ["Hel", "HEL", "Th", "việt", "", "xyzq", "abc1"] {
            XCTAssertEqual(SwipeEnglish.completions(p, in: new), old.completions(p), p)
        }

        // Từ phổ biến: toàn bộ thứ tự.
        XCTAssertEqual(SwipeEnglish.topWords(limit: old.words.count, in: new), old.topWords(limit: old.words.count))
        XCTAssertEqual(SwipeEnglish.top, old.topWords(limit: 12))

        // Sửa chính tả (EnglishAssist.corrections): lỗi giả tất định trên mẫu từ dài.
        var typos = 0
        for (i, w) in old.words.enumerated() where w.count >= 5 && i % 27 == 0 {
            var c = Array(w)
            let k = (i / 27) % (c.count - 1) + 1
            let variants: [String] = [
                String(c.prefix(k) + c.dropFirst(k + 1)),                 // bỏ chữ
                { var x = c; x.swapAt(k, k - 1); return String(x) }(),      // đảo
                { var x = c; x[k] = x[k] == "z" ? "a" : "z"; return String(x) }(), // thay
                { c.insert("q", at: k); return String(c) }(),               // thêm
                String(w.prefix(max(5, w.count - 2))),                      // gõ dở
            ]
            for v in variants {
                XCTAssertEqual(EnglishAssist.corrections(v, in: new), old.corrections(v), v)
                typos += 1
            }
        }
        for v in ["abcd", "acomm", "enviroment", "zzzzzz", "ãbcdef", "1abcde", "Hello"] {
            XCTAssertEqual(EnglishAssist.corrections(v, in: new), old.corrections(v), v)
        }

        // Bảng phím vuốt (dựng lười) trùng bản cũ.
        let t = new.swipe
        XCTAssertEqual(t.keys, old.keys)
        XCTAssertEqual(t.keyStart, old.keyStart)
        XCTAssertEqual(t.order, old.order)
        XCTAssertEqual(t.bucketStart, old.bucketStart)
        print("EN-LEXICON PARITY: \(old.words.count) từ, \(probes) từ không có, \(prefixes.count) tiền tố, \(typos) lỗi gõ — khớp")
    }

    /// File hỏng: cùng chỗ từ chối với bản cũ.
    func testRejectsCorruptLikeLegacy() throws {
        let data = try fileData()
        var bad: [Data] = [Data(), Data("VTE1".utf8), Data("VTE2".utf8) + data.dropFirst(4), data.prefix(100)]
        var zeroLen = data; zeroLen[8] = 0; bad.append(zeroLen)
        var upper = data; upper[10] = 0x41; bad.append(upper)
        // Đếm mục lớn hơn thực tế 1 ⇒ cụt file.
        let n = UInt32(data[4]) | UInt32(data[5]) << 8 | UInt32(data[6]) << 16 | UInt32(data[7]) << 24
        var count = data
        for k in 0..<4 { count[4 + k] = UInt8(truncatingIfNeeded: (n + 1) >> (8 * k)) }
        bad.append(count)
        for (i, d) in bad.enumerated() {
            XCTAssertEqual(SwipeEnglish.parse(d) == nil, Legacy.parse(d) == nil, "ca \(i)")
            XCTAssertNil(SwipeEnglish.parse(d), "ca \(i)")
        }
        // Đuôi thừa sau n mục: cả hai đều nhận.
        XCTAssertNotNil(SwipeEnglish.parse(data + Data([1, 2, 3])))
        XCTAssertNotNil(Legacy.parse(data + Data([1, 2, 3])))
        XCTAssertEqual(SwipeEnglish.Lexicon.empty.count, 0)
        XCTAssertEqual(SwipeEnglish.Lexicon.empty.swipe.bucketStart.count, 677)
        XCTAssertNil(SwipeEnglish.index(of: "a", in: .empty))
    }

    // MARK: bảng phím vuốt chỉ khi cần

    func testSwipeTablesNotBuiltWithoutSwipe() throws {
        let lex = try XCTUnwrap(SwipeEnglish.parse(try fileData()))
        // Mọi đường KHÔNG phải gõ vuốt: tra, hoàn thành, từ phổ biến, gợi ý/sửa tiếng Anh giữa câu Việt.
        XCTAssertNotNil(SwipeEnglish.index(of: "hello", in: lex))
        XCTAssertFalse(SwipeEnglish.completions("acc", in: lex).isEmpty)
        XCTAssertEqual(SwipeEnglish.topWords(limit: 12, in: lex).count, 12)
        XCTAssertFalse(EnglishAssist.corrections("enviroment", in: lex).isEmpty)
        XCTAssertNotNil(EnglishAssist.suggest(raw: "accomm", composed: "accomm", pool: [], typedFreq: nil, lex: lex))
        XCTAssertFalse(lex.hasSwipeTables, "tắt vuốt ⇒ không dựng keys/keyStart/order/bucket")
        _ = lex.swipe
        XCTAssertTrue(lex.hasSwipeTables)

        // Lexicon dùng chung: gõ chạm (gợi ý, tự sửa, Thêm dấu) không dựng; decode vuốt tiếng Anh thì dựng.
        #if DEBUG
        SwipeEnglish.debugUnload()
        _ = SwipeEnglish.contains("hello")
        _ = SwipeEnglish.completions("hel")
        _ = EnglishAssist.suggest(raw: "accomm", composed: "accomm", pool: [], typedFreq: nil)
        _ = AutoCorrect.isEnglish("check")
        XCTAssertFalse(SwipeEnglish.lexicon.hasSwipeTables)
        let d = SwipeDecoder(); d.setLayout(SwipeLayout.qwerty(keyWidth: 40, rowHeight: 54))
        var sim = SwipeSim(seed: 3)
        _ = d.decode(sim.path("hello", SwipeLayout.qwerty(keyWidth: 40, rowHeight: 54)), topK: 3)
        XCTAssertFalse(SwipeEnglish.lexicon.hasSwipeTables, "vuốt không bật tiếng Anh ⇒ không dựng")
        _ = d.decode(sim.path("hello", SwipeLayout.qwerty(keyWidth: 40, rowHeight: 54)), topK: 3,
                     english: SwipeLangContext.defaultPrior)
        XCTAssertTrue(SwipeEnglish.lexicon.hasSwipeTables)
        #endif
    }

    // MARK: từ trước tiếng Việt không chạm lexicon tiếng Anh

    func testVietnamesePrevWordNeverAsksEnglish() {
        var asked: [String] = []
        let isEn: (String) -> Bool = { asked.append($0); return SwipeEnglish.contains($0) }
        for w in ["xin", "Chào", "anh", "em", "của", "người", "the", "to", "can"] where VNSuggest.lexiconId(of: w.lowercased()) != nil {
            asked.removeAll()
            XCTAssertTrue(SuggestRank.padsWithTopWords(w, english: false, isEnglish: isEn))
            XCTAssertTrue(asked.isEmpty, "\(w): âm tiết Việt ⇒ không hỏi tiếng Anh")
        }
        // Từ không phải âm tiết Việt vẫn hỏi; kết quả = công thức cũ !E || V trên mọi ca.
        for w in ["they", "hello", "xyzq", "ok", "github", "check", "1st", "xin", "the", "Được"] {
            asked.removeAll()
            let low = w.lowercased()
            let v = VNSuggest.lexiconId(of: low) != nil, e = SwipeEnglish.contains(low)
            XCTAssertEqual(SuggestRank.padsWithTopWords(w, english: false, isEnglish: isEn), !e || v, w)
            XCTAssertEqual(asked.isEmpty, v, w)
        }
        XCTAssertFalse(SuggestRank.padsWithTopWords("they", english: false, isEnglish: { SwipeEnglish.contains($0) }))
        XCTAssertFalse(SuggestRank.padsWithTopWords("xin", english: true, isEnglish: { _ in XCTFail(); return true }))
        XCTAssertTrue(SuggestRank.padsWithTopWords(nil, english: false, isEnglish: { _ in XCTFail(); return true }))

        // Đường controller (containsIfLoaded) với lexicon CHƯA nạp: từ trước tiếng Việt không chạm
        // SwipeEnglish (không hỏi ⇒ không hẹn nạp).
        #if DEBUG
        SwipeEnglish.debugUnload()
        var touched = false
        XCTAssertTrue(SuggestRank.padsWithTopWords("xin", english: false,
                                                   isEnglish: { touched = true; return SwipeEnglish.containsIfLoaded($0) ?? false }))
        XCTAssertFalse(touched)
        XCTAssertFalse(SwipeEnglish.debugIsLoaded)
        #endif
    }

    // MARK: main thread không nạp

    #if DEBUG
    func testMainThreadNeverLoads() {
        XCTAssertTrue(Thread.isMainThread)
        let mainLoads = SwipeEnglish.debugMainThreadLoads
        // Việc nạp nền của test trước có thể vừa về ⇒ thử lại vài lần cho tới khi thấy "chưa nạp".
        var unknown = false
        for _ in 0..<5 where !unknown {
            Thread.sleep(forTimeInterval: 0.05)
            SwipeEnglish.debugUnload()
            unknown = SwipeEnglish.containsIfLoaded("hello") == nil
        }
        XCTAssertTrue(unknown, "chưa nạp ⇒ chưa biết, không chặn")
        let deadline = Date(timeIntervalSinceNow: 10)
        while SwipeEnglish.topIfLoaded == nil, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertEqual(SwipeEnglish.containsIfLoaded("hello"), true)
        XCTAssertEqual(SwipeEnglish.containsIfLoaded("xin"), false)
        XCTAssertEqual(SwipeEnglish.topIfLoaded, SwipeEnglish.topWords(limit: 12))
        XCTAssertEqual(SwipeEnglish.debugMainThreadLoads, mainLoads, "nạp ở nền, không phải main")
    }
    #endif

    // MARK: đo (in số — RAM-AUDIT.md §4d)

    /// Heap giữ lại + đỉnh tạm thời của bản cũ (giải mã ra [String] + bảng phím) vs bản mới (offset trên
    /// mmap; bảng phím đo riêng). Đo bằng malloc_zone_statistics (heap của process).
    func testMeasureHeap() throws {
        let url = try XCTUnwrap(VTBundleResource.url("enlexicon", "bin", anchor: KeyboardView.self))
        func heap() -> Int {
            var s = malloc_statistics_t()
            malloc_zone_statistics(nil, &s)
            return Int(s.size_in_use)
        }
        func kb(_ b: Int) -> String { String(format: "%.0f KB", Double(b) / 1024) }
        var lines: [String] = []
        for _ in 0..<2 {   // lượt 1 làm ấm (cấp phát lần đầu của runtime)
            lines.removeAll()
            let h0 = heap()
            var old: Legacy? = try autoreleasepool {
                let d = try Data(contentsOf: url, options: .alwaysMapped)
                return Legacy.parse(d)
            }
            let hOld = heap() - h0
            XCTAssertNotNil(old)
            old = nil
            let h1 = heap()
            var new: SwipeEnglish.Lexicon? = try autoreleasepool {
                let d = try NSData(contentsOf: url, options: .alwaysMapped)
                return SwipeEnglish.Lexicon.make(d)
            }
            let hNew = heap() - h1
            _ = new?.swipe
            let hSwipe = heap() - h1 - hNew
            new = nil
            lines.append("cũ (words+freq+bảng phím) \(kb(hOld)) | mới, chỉ offset+freq \(kb(hNew)) | + bảng phím vuốt (lười) \(kb(hSwipe))")
        }
        print("EN-LEXICON HEAP: " + lines.joined())
    }
}
