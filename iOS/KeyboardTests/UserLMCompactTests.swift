// Bảng gọn của UserLangModel (intern id + file VTL2) — iOS/docs/RAM-AUDIT.md §5.
// - Property test: chuỗi thao tác ngẫu nhiên áp lên LegacyUserLangModel (bản cũ, nguyên vẹn) và
//   UserLangModel, so MỌI đầu ra sau từng bước (gợi ý, count, entries, bảng đầy đủ) — gồm chạm trần
//   (prune), decay, retract, thêm/xoá tay.
// - Chuyển đổi plist cũ → VTL2 (fixture), fixture VTL2 dựng bằng Python (Android đọc cùng file),
//   file hỏng, sao lưu JSON không đổi.
// - Đo trước/sau (RAM heap, nạp/lưu, độ trễ tra) — dòng "USERLM …".
import XCTest

final class UserLMCompactTests: XCTestCase {

    // MARK: tiện ích

    struct RNG {
        var s: UInt64
        mutating func next() -> UInt64 {
            s &+= 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        mutating func chance(_ p: Double) -> Bool { Double(next() % 1_000_000) / 1_000_000 < p }
    }

    static let onsets = ["b", "c", "ch", "d", "đ", "g", "gh", "h", "k", "kh", "l", "m", "n", "ng",
                         "nh", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x", ""]
    static let rimes = ["a", "á", "à", "ả", "ã", "ạ", "ăn", "ắt", "ân", "ấy", "anh", "ành", "ong", "óng",
                        "ương", "ường", "iêu", "iếu", "ưa", "ứa", "ơi", "ời", "uôi", "uối", "em", "ém",
                        "ên", "ết", "inh", "ình", "oa", "oá", "oan", "oàn", "ui", "úi", "ưng", "ừng",
                        "ai", "ái", "ao", "áo", "êu", "ều", "ia", "ìa", "ôm", "ốm", "ơn", "ớn", "uyên",
                        "uyền", "yêu", "ỷ", "ốc", "ọc", "ắc", "ặc", "iệt", "ược", "ưởng", "uống"]
    /// Âm tiết giả tiếng Việt (có dấu) — đủ đa dạng để chạm trần uni 3000.
    static func syllables(_ n: Int) -> [String] {
        var out: [String] = []
        outer: for x in ["", "x", "y", "z"] { for r in rimes { for o in onsets {
            out.append(o + r + x)
            if out.count >= n { break outer }
        } } }
        return out
    }

    private func tmpURL(_ tag: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ulm-\(tag)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("userlm.plist")
    }

    private func fixtureURL(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext))
    }

    /// So toàn bộ đầu ra quan sát được của hai model.
    private func assertSame(_ a: LegacyUserLangModel, _ b: UserLangModel, probe words: [String],
                            rng: inout RNG, full: Bool, _ ctx: String, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 {
            let w = words[rng.int(words.count)]
            let p2 = rng.chance(0.5) ? words[rng.int(words.count)] : nil
            let lim = 1 + rng.int(6)
            XCTAssertEqual(a.nextWords(after: w, prev2: p2, limit: lim), b.nextWords(after: w, prev2: p2, limit: lim),
                           "nextWords(\(w),\(p2 ?? "-")) \(ctx)", file: file, line: line)
            XCTAssertEqual(a.count(of: w), b.count(of: w), "count \(w) \(ctx)", file: file, line: line)
            XCTAssertEqual(a.isUserWord(w), b.isUserWord(w), "isUserWord \(w) \(ctx)", file: file, line: line)
            let n = words[rng.int(words.count)]
            XCTAssertEqual(a.bigramCount(w, n), b.bigramCount(w, n), "bigram \(w)→\(n) \(ctx)", file: file, line: line)
            let q = words[rng.int(words.count)]
            XCTAssertEqual(a.trigramCount(q, w, n), b.trigramCount(q, w, n), "trigram \(q),\(w)→\(n) \(ctx)", file: file, line: line)
            if let p2 { XCTAssertEqual(a.trigramCount(p2, w, n), b.trigramCount(p2, w, n), file: file, line: line) }
        }
        let k = 1 + rng.int(20)
        XCTAssertEqual(a.topWords(limit: k), b.topWords(limit: k), "topWords(\(k)) \(ctx)", file: file, line: line)
        let pre = String(words[rng.int(words.count)].prefix(1 + rng.int(2)))
        XCTAssertEqual(a.manualCompletions(pre), b.manualCompletions(pre), "manual(\(pre)) \(ctx)", file: file, line: line)
        if full {
            XCTAssertEqual(a.uni, b.uni, "uni \(ctx)", file: file, line: line)
            XCTAssertEqual(a.bi, b.bi, "bi \(ctx)", file: file, line: line)
            XCTAssertEqual(a.tri, b.tri, "tri \(ctx)", file: file, line: line)
            XCTAssertEqual(a.manual, b.manual, "manual \(ctx)", file: file, line: line)
            XCTAssertEqual(a.entries().map { [$0.word, "\($0.count)", "\($0.manual)"] },
                           b.entries().map { [$0.word, "\($0.count)", "\($0.manual)"] }, "entries \(ctx)", file: file, line: line)
            XCTAssertEqual(b.uniCount, a.uni.count, file: file, line: line)
            XCTAssertEqual(b.biPairCount, a.bi.values.reduce(0) { $0 + $1.count }, file: file, line: line)
            XCTAssertEqual(b.triPairCount, a.tri.values.reduce(0) { $0 + $1.count }, file: file, line: line)
        }
    }

    /// Chạy `steps` thao tác ngẫu nhiên trên cả hai model.
    private func runRandom(seed: UInt64, vocab: Int, steps: Int, fullEvery: Int) {
        var rng = RNG(s: seed)
        var words = Self.syllables(vocab)
        // từ không học được / hoa-thường lẫn lộn — cùng đi qua cả hai
        words += ["abc1", "heeeyyy", "", "Anh", "EM", "a b", "quáaaa", "VietTelex", "Kubernetes"]
        let a = LegacyUserLangModel(appGroup: nil), b = UserLangModel(appGroup: nil)
        let known: (String) -> Bool = { w in w.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 3 != 0 }
        a.isKnownWord = known; b.isKnownWord = known
        if seed % 2 == 0 {
            var su: [String: Int] = [:]
            for (i, w) in words.prefix(40).enumerated() { su[w] = 5 + i % 40 }
            var sb: [(String, String, Int)] = []
            for i in 0..<60 { sb.append((words[i % 40], words[(i * 7) % 40], 1 + i % 9)) }
            a.seedIfEmpty(unigrams: su, bigrams: sb); b.seedIfEmpty(unigrams: su, bigrams: sb)
        }
        var receipts: [(LegacyUserLangModel.Learned?, UserLangModel.Learned?)] = []
        var p1: String?, p2: String?
        let base = Date()
        var week = 0
        for step in 0..<steps {
            let r = rng.int(1000)
            switch r {
            case 0..<900:
                // Zipf nhẹ: nửa số lần rơi vào 1/8 đầu bảng từ ⇒ tri có nền (bi ≥ 2)
                let w = rng.chance(0.5) ? words[rng.int(max(1, words.count / 8))] : words[rng.int(words.count)]
                let wt = rng.chance(0.1) ? 2 : 1
                let ra = a.record(word: w, after: p1, prev2: p2, weight: wt)
                let rb = b.record(word: w, after: p1, prev2: p2, weight: wt)
                XCTAssertEqual(ra?.word, rb?.word); XCTAssertEqual(ra?.prev1, rb?.prev1)
                XCTAssertEqual(ra?.triKey, rb?.triKey)
                receipts.append((ra, rb))
                if receipts.count > 50 { receipts.removeFirst() }
                if rng.chance(0.15) { p1 = nil; p2 = nil } else { p2 = p1; p1 = w }
            case 900..<940:
                if !receipts.isEmpty {
                    let (ra, rb) = receipts.remove(at: rng.int(receipts.count))
                    if let ra { a.retract(ra) }
                    if let rb { b.retract(rb) }
                }
            case 940..<955:
                let w = words[rng.int(words.count)]
                XCTAssertEqual(a.addWord(w), b.addWord(w))
            case 955..<970:
                let w = words[rng.int(words.count)]
                XCTAssertEqual(a.removeWord(w), b.removeWord(w), "removeWord \(w)")
            case 970..<975:
                week += 1 + rng.int(3)
                let now = base.addingTimeInterval(Double(week) * 7 * 86400 + 3600)
                a.decayIfDue(now: now); b.decayIfDue(now: now)
            default:
                break
            }
            assertSame(a, b, probe: words, rng: &rng, full: step % fullEvery == 0, "seed=\(seed) step=\(step)")
        }
        assertSame(a, b, probe: words, rng: &rng, full: true, "seed=\(seed) end")
    }

    // MARK: property test cũ ≡ mới

    func testRandomOpsMatchLegacy() {
        for seed in UInt64(1)...6 { runRandom(seed: seed, vocab: 120, steps: 1500, fullEvery: 25) }
    }

    /// Vượt trần uni 3000 / bi 6000 / tri 3000 nhiều lần (prune halve + compact id).
    func testCapsAndPruneMatchLegacy() {
        runRandom(seed: 42, vocab: 3600, steps: 40_000, fullEvery: 2000)
        runRandom(seed: 43, vocab: 3600, steps: 40_000, fullEvery: 2000)
    }

    func testRetractRestoresTables() {
        let m = UserLangModel(appGroup: nil)
        m.isKnownWord = { _ in true }
        for _ in 0..<3 { m.record(word: "cảm", after: nil); m.record(word: "ơn", after: "cảm") }
        let before = (m.uni, m.bi, m.tri)
        let l1 = m.record(word: "nhiều", after: "ơn", prev2: "cảm")
        let l2 = m.record(word: "ơn", after: "cảm", weight: 2)
        XCTAssertNotNil(l1?.triKey)
        m.retract(l2!); m.retract(l1!)
        XCTAssertEqual(m.uni, before.0); XCTAssertEqual(m.bi, before.1); XCTAssertEqual(m.tri, before.2)
        m.retract(l1!)                                 // rút lần hai: không âm, không đổi gì
        XCTAssertEqual(m.uni, before.0)
    }

    func testCompactDropsOrphanWords() {
        let m = UserLangModel(appGroup: nil)
        m.record(word: "một", after: nil); m.record(word: "hai", after: "một")
        XCTAssertEqual(m.debugVocabCount, 2)
        XCTAssertTrue(m.removeWord("hai"))
        XCTAssertEqual(m.debugVocabCount, 1)         // "hai" không còn ở đâu ⇒ bỏ khỏi bảng từ
        XCTAssertEqual(m.count(of: "một"), 1)
        XCTAssertEqual(m.bigramCount("một", "hai"), 0)
    }

    // MARK: file — lưu / nạp / chuyển đổi

    func testSaveReloadRoundTrip() {
        let url = tmpURL("rt")
        let a = UserLangModel(fileURL: url, synchronous: true)
        a.isKnownWord = { _ in true }
        var rng = RNG(s: 7)
        let words = Self.syllables(300)
        var p1: String?, p2: String?
        for _ in 0..<5000 {
            let w = words[rng.int(rng.chance(0.5) ? 30 : words.count)]
            a.record(word: w, after: p1, prev2: p2); p2 = p1; p1 = w
        }
        a.addWord("VietTelex")
        a.saveSync()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))       // không ghi plist nữa
        let b = UserLangModel(fileURL: url, synchronous: true)
        XCTAssertEqual(a.uni, b.uni); XCTAssertEqual(a.bi, b.bi); XCTAssertEqual(a.tri, b.tri)
        XCTAssertEqual(a.manual, b.manual)
        b.isKnownWord = { _ in true }
        for w in words.prefix(50) { XCTAssertEqual(a.nextWords(after: w, limit: 5), b.nextWords(after: w, limit: 5)) }
    }

    /// plist kiểu cũ (fixture Python + bản do LegacyUserLangModel ghi) → nạp đúng, ghi userlm.bin, bỏ plist.
    func testMigratesLegacyPlistFixture() throws {
        let url = tmpURL("mig")
        try FileManager.default.copyItem(at: fixtureURL("userlm-legacy-ios", "plist"), to: url)
        // Đọc không ghi (đường sao lưu) — đúng nội dung fixture.
        let plain = try XCTUnwrap(UserLangModel.readPlain(at: url))
        XCTAssertEqual(plain.uni, ["cảm": 7, "ơn": 6, "nhiều": 4, "viettelex": 5, "sếp": 3])
        XCTAssertEqual(plain.bi, ["cảm": ["ơn": 5], "ơn": ["nhiều": 3, "sếp": 1]])
        XCTAssertEqual(plain.tri, ["cảm\u{1}ơn": ["nhiều": 3]])
        XCTAssertEqual(plain.manual, ["VietTelex"])
        XCTAssertEqual(plain.lastDecay.timeIntervalSince1970, 1_788_220_800, accuracy: 0.001)

        // Model cũ và mới cùng nạp (cùng decay theo lastDecay) ⇒ bảng giống hệt.
        let legacyCopy = url.deletingLastPathComponent().appendingPathComponent("legacy.plist")
        try FileManager.default.copyItem(at: url, to: legacyCopy)
        let old = LegacyUserLangModel(fileURL: legacyCopy, synchronous: true)
        let m = UserLangModel(fileURL: url, synchronous: true)
        XCTAssertEqual(m.uni, old.uni); XCTAssertEqual(m.bi, old.bi); XCTAssertEqual(m.tri, old.tri)
        XCTAssertEqual(m.manual, old.manual)
        m.saveSync()
        let bin = UserLangModel.compactURL(for: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bin.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "plist cũ phải bị xoá sau khi chuyển")
        let again = UserLangModel(fileURL: url, synchronous: true)
        XCTAssertEqual(again.uni, old.uni); XCTAssertEqual(again.manualCompletions("viet"), ["VietTelex"])
    }

    func testMigratesPlistWrittenByLegacyModel() {
        let url = tmpURL("mig2")
        let old = LegacyUserLangModel(fileURL: url, synchronous: true)
        old.isKnownWord = { _ in true }
        var rng = RNG(s: 99)
        let words = Self.syllables(400)
        var p1: String?, p2: String?
        for _ in 0..<8000 {
            let w = words[rng.int(rng.chance(0.6) ? 40 : words.count)]
            old.record(word: w, after: p1, prev2: p2); p2 = p1; p1 = w
        }
        old.addWord("Kubernetes")
        old.saveSync()
        let m = UserLangModel(fileURL: url, synchronous: true)
        XCTAssertEqual(m.uni, old.uni); XCTAssertEqual(m.bi, old.bi); XCTAssertEqual(m.tri, old.tri)
        XCTAssertEqual(m.manual, old.manual)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// Ghi bản mới thất bại (chỗ ghi bị chiếm) ⇒ plist cũ KHÔNG bị xoá, dữ liệu vẫn nạp từ plist.
    func testMigrationWriteFailureKeepsLegacy() throws {
        let url = tmpURL("migfail")
        try FileManager.default.copyItem(at: fixtureURL("userlm-legacy-ios", "plist"), to: url)
        let bin = UserLangModel.compactURL(for: url)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try "x".write(to: bin.appendingPathComponent("chặn"), atomically: true, encoding: .utf8)
        let original = try Data(contentsOf: url)
        // Đồng hồ cố định = lastDecay của fixture: không decay lúc nạp. Trước đây test dùng giờ
        // thật ⇒ từ 01/09/2026 trở đi decay 0.7^tuần làm count fixture rơi về 0 (test hỏng theo lịch).
        let fixtureNow = { Date(timeIntervalSince1970: 1_788_220_800) }
        let m = UserLangModel(fileURL: url, synchronous: true, clock: fixtureNow)
        // Ghi bản mới thất bại ⇒ bản cũ còn nguyên từng byte, dữ liệu vẫn dùng được trong phiên.
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(m.manual, ["viettelex": "VietTelex"])
        XCTAssertEqual(m.count(of: "cảm"), 7)
        XCTAssertEqual(m.count(of: "ơn"), 6)

        // Gỡ vật cản ⇒ lần nạp sau chuyển đổi thành công, bản cũ mới bị xoá.
        try FileManager.default.removeItem(at: bin)
        let again = UserLangModel(fileURL: url, synchronous: true, clock: fixtureNow)
        XCTAssertEqual(again.count(of: "cảm"), 7)
        XCTAssertNotNil(UserLMCodec.decode(try Data(contentsOf: bin)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// Fixture VTL2 do bộ mã hoá Python độc lập dựng — Android đọc cùng file (layout chung).
    func testDecodesCrossPlatformFixture() throws {
        let data = try Data(contentsOf: fixtureURL("userlm-vtl2", "bin"))
        let d = try XCTUnwrap(UserLMCodec.decode(data))
        XCTAssertEqual(d.tables.uniDict(), ["cảm": 7, "ơn": 6, "nhiều": 4, "viettelex": 5, "sếp": 3])
        XCTAssertEqual(d.tables.biDict(), ["cảm": ["ơn": 5], "ơn": ["nhiều": 3, "sếp": 1]])
        XCTAssertEqual(d.tables.triDict(), ["cảm\u{1}ơn": ["nhiều": 3]])
        XCTAssertEqual(d.manual, ["VietTelex"])
        XCTAssertEqual(d.lastDecay.timeIntervalSince1970, 1_788_220_800, accuracy: 0.0001)
        // mã hoá lại bảng vừa đọc (cùng thứ tự id) ⇒ trùng từng byte với bản Python
        XCTAssertEqual(UserLMCodec.encode(d.tables, lastDecay: d.lastDecay, manual: d.manual), data)
    }

    func testCorruptFilesAreRejected() throws {
        let good = try Data(contentsOf: fixtureURL("userlm-vtl2", "bin"))
        XCTAssertNotNil(UserLMCodec.decode(good))
        for i in stride(from: 0, to: good.count, by: 3) {           // lật từng byte ⇒ CRC/magic bắt
            var bad = good; bad[i] ^= 0x5A
            XCTAssertNil(UserLMCodec.decode(bad), "byte \(i)")
        }
        for n in [0, 3, 20, good.count - 1] { XCTAssertNil(UserLMCodec.decode(good.prefix(n))) }
        XCTAssertNil(UserLMCodec.decode(Data((0..<500).map { UInt8($0 & 0xFF) })))
        XCTAssertNil(UserLMCodec.decode(good + Data([0])))

        // bin hỏng + còn plist cũ ⇒ dùng plist
        let url = tmpURL("corrupt")
        try FileManager.default.copyItem(at: fixtureURL("userlm-legacy-ios", "plist"), to: url)
        var bad = good; bad[40] ^= 1
        try bad.write(to: UserLangModel.compactURL(for: url))
        let m = UserLangModel(fileURL: url, synchronous: true)
        XCTAssertEqual(m.manual, ["viettelex": "VietTelex"])

        // bin hỏng, không còn gì ⇒ rỗng (không crash), vẫn học được
        let url2 = tmpURL("corrupt2")
        try bad.write(to: UserLangModel.compactURL(for: url2))
        let e = UserLangModel(fileURL: url2, synchronous: true)
        XCTAssertEqual(e.uniCount, 0)
        e.record(word: "chào", after: nil)
        XCTAssertEqual(e.count(of: "chào"), 1)
        // plist hỏng, không bin ⇒ rỗng
        let url3 = tmpURL("corrupt3")
        try Data("không phải plist".utf8).write(to: url3)
        XCTAssertEqual(UserLangModel(fileURL: url3, synchronous: true).uniCount, 0)
    }

    func testRemoveStoreDeletesAllGenerations() throws {
        let url = tmpURL("erase")
        try Data([1]).write(to: url)
        try Data([2]).write(to: UserLangModel.compactURL(for: url))
        UserLangModel.removeStore(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: UserLangModel.compactURL(for: url).path))
    }

    // MARK: sao lưu — JSON không đổi

    func testBackupJSONUnchanged() throws {
        let fixture = try Data(contentsOf: fixtureURL("backup-ios-v1", "json"))
        let payload = try BackupCodec.decode(fixture)
        let lw = try XCTUnwrap(payload.learnedWords)
        let suite = "vt.ulm.bk.\(UUID().uuidString)"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BackupStore(defaults: UserDefaults(suiteName: suite)!, containerURL: dir)
        store.mergeLearnedWords(lw)
        var expect = lw
        for m in lw.manual where expect.uni[m.lowercased()] == nil { expect.uni[m.lowercased()] = 1 }
        XCTAssertEqual(store.learnedWords(), expect)
        let out = try BackupCodec.encode(store.snapshot(includeLearned: true))
        let a = try XCTUnwrap((try JSONSerialization.jsonObject(with: out) as? [String: Any])?["learnedWords"] as? NSDictionary)
        let b = try XCTUnwrap((try JSONSerialization.jsonObject(with: fixture) as? [String: Any])?["learnedWords"] as? NSDictionary)
        XCTAssertEqual(a, b)
        // Model đọc được file sao lưu vừa gộp.
        let m = UserLangModel(fileURL: dir.appendingPathComponent(BackupStore.learnedFile), synchronous: true)
        XCTAssertEqual(m.uni, expect.uni)
    }

    // MARK: đo trước/sau

    /// Người dùng nặng tại trần: 2.990 uni / 5.990 bi / 2.990 tri. In "USERLM …".
    func testMeasureHeavyUser() throws {
        let words = Self.syllables(2990)
        var uni: [String: Int] = [:], bi: [String: [String: Int]] = [:], tri: [String: [String: Int]] = [:]
        for (i, w) in words.enumerated() { uni[w] = 1 + (2990 - i) / 30 }
        var n = 0, i = 0
        while n < 5990 {
            let p = words[(i * 13) % 600], x = words[(i * 7919) % words.count]
            if bi[p]?[x] == nil { bi[p, default: [:]][x] = 1 + i % 7; n += 1 }
            i += 1
        }
        n = 0; i = 0
        while n < 2990 {
            let p2 = words[(i * 17) % 200], p1 = words[(i * 31) % 300], x = words[(i * 104_729) % words.count]
            let k = p2 + "\u{1}" + p1
            if tri[k]?[x] == nil { tri[k, default: [:]][x] = 1 + i % 5; n += 1 }
            i += 1
        }
        let now = Date()
        let oldURL = tmpURL("bench-old"), newURL = tmpURL("bench-new")
        let plist: [String: Any] = ["version": 3, "uni": uni, "bi": bi, "tri": tri, "lastDecay": now, "manual": [String]()]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: oldURL)
        XCTAssertTrue(UserLangModel.writePlain(.init(uni: uni, bi: bi, tri: tri, manual: [], lastDecay: now), to: newURL))
        let oldBytes = (try? Data(contentsOf: oldURL).count) ?? 0
        let newBytes = (try? Data(contentsOf: UserLangModel.compactURL(for: newURL)).count) ?? 0

        func heap() -> Int { RamBreakdownTests.heapBytes() }
        func ms(_ f: () -> Void) -> Double { let t = CFAbsoluteTimeGetCurrent(); f(); return (CFAbsoluteTimeGetCurrent() - t) * 1000 }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }

        // nạp (đo 3 lần, lấy nhỏ nhất) + RAM giữ lại
        var oldLoad = Double.infinity, newLoad = Double.infinity
        for _ in 0..<3 {
            oldLoad = min(oldLoad, ms { _ = LegacyUserLangModel(fileURL: oldURL, synchronous: true) })
            newLoad = min(newLoad, ms { _ = UserLangModel(fileURL: newURL, synchronous: true) })
        }
        settle()
        // RAM giữ lại = phần heap NHẢ ra khi bỏ model (xác định, không lẫn rác của test khác).
        func retained(_ make: () -> AnyObject) -> Int {
            var m: AnyObject?
            autoreleasepool { m = make() }
            settle()
            let h = heap()
            autoreleasepool { m = nil }
            settle()
            return h - heap()
        }
        let oldHeap = retained { LegacyUserLangModel(fileURL: oldURL, synchronous: true) }
        let newHeap = retained { UserLangModel(fileURL: newURL, synchronous: true) }
        let old = LegacyUserLangModel(fileURL: oldURL, synchronous: true)
        let new = UserLangModel(fileURL: newURL, synchronous: true)
        XCTAssertEqual(new.uni, old.uni); XCTAssertEqual(new.bi, old.bi); XCTAssertEqual(new.tri, old.tri)

        // lưu (encode + ghi atomic, đồng bộ)
        var oldSave = Double.infinity, newSave = Double.infinity
        for k in 0..<3 {
            old.record(word: words[k], after: words[k + 1]); new.record(word: words[k], after: words[k + 1])
            oldSave = min(oldSave, ms { old.saveSync() })
            newSave = min(newSave, ms { new.saveSync() })
        }

        // tra trên đường gợi ý
        old.isKnownWord = { _ in true }; new.isKnownWord = { _ in true }
        let prevs = (0..<2000).map { words[($0 * 13) % 600] }, p2s = (0..<2000).map { words[($0 * 17) % 200] }
        func bench(_ f: (Int) -> Void) -> Double {
            _ = ms { for j in 0..<500 { f(j) } }                   // làm ấm cache knownCache
            var best = Double.infinity
            for _ in 0..<3 { best = min(best, ms { for j in 0..<20_000 { f(j) } }) }
            return best * 1_000_000 / 20_000                        // ns / lần
        }
        let oldNext = bench { j in _ = old.nextWords(after: prevs[j % 2000], prev2: p2s[j % 2000], limit: 3) }
        let newNext = bench { j in _ = new.nextWords(after: prevs[j % 2000], prev2: p2s[j % 2000], limit: 3) }
        let oldCount = bench { j in _ = old.count(of: words[j % 2990]) }
        let newCount = bench { j in _ = new.count(of: words[j % 2990]) }
        let oldBig = bench { j in _ = old.bigramCount(prevs[j % 2000], words[(j * 7919) % 2990]) }
        let newBig = bench { j in _ = new.bigramCount(prevs[j % 2000], words[(j * 7919) % 2990]) }
        let oldTri = bench { j in _ = old.trigramCount(p2s[j % 2000], prevs[j % 2000], words[(j * 7919) % 2990]) }
        let newTri = bench { j in _ = new.trigramCount(p2s[j % 2000], prevs[j % 2000], words[(j * 7919) % 2990]) }
        let oldTop = bench { j in _ = old.topWords(limit: 3 + j % 2) }
        let newTop = bench { j in _ = new.topWords(limit: 3 + j % 2) }

        // Phiên học dồn (bảng dựng bằng record — dict Swift thật, không phải NSDictionary bridge từ plist)
        // Phiên học dồn (bảng dựng bằng record — dict Swift thật, không phải NSDictionary bridge từ plist)
        func learn(_ rec: (String, String?, String?) -> Void) {
            var rng = RNG(s: 2026)
            let vocab = Self.syllables(3400)
            var p1: String?, p2: String?
            for _ in 0..<40_000 {
                let w = rng.chance(0.6) ? vocab[rng.int(150)] : vocab[rng.int(vocab.count)]
                rec(w, p1, p2)
                if rng.chance(0.12) { p1 = nil; p2 = nil } else { p2 = p1; p1 = w }
            }
        }
        let sOldHeap = retained { let m = LegacyUserLangModel(appGroup: nil); learn { m.record(word: $0, after: $1, prev2: $2) }; return m }
        let sNewHeap = retained { let m = UserLangModel(appGroup: nil); learn { m.record(word: $0, after: $1, prev2: $2) }; return m }
        let sOld = LegacyUserLangModel(appGroup: nil), sNew = UserLangModel(appGroup: nil)
        learn { sOld.record(word: $0, after: $1, prev2: $2) }; learn { sNew.record(word: $0, after: $1, prev2: $2) }
        XCTAssertEqual(sOld.uni, sNew.uni); XCTAssertEqual(sOld.bi, sNew.bi); XCTAssertEqual(sOld.tri, sNew.tri)
        print("USERLM session uni=\(sNew.uniCount) bi=\(sNew.biPairCount) tri=\(sNew.triPairCount)")
        print(String(format: "USERLM session heap old=%.2fMB new=%.2fMB (%.0f%%)", Double(sOldHeap) / 1_048_576,
                     Double(sNewHeap) / 1_048_576, 100 * Double(sNewHeap) / Double(max(sOldHeap, 1))))
        XCTAssertLessThan(Double(sNewHeap), Double(sOldHeap) * 0.75)

        print(String(format: "USERLM loaded heap old=%.2fMB new=%.2fMB (%.0f%%)", Double(oldHeap) / 1_048_576,
                     Double(newHeap) / 1_048_576, 100 * Double(newHeap) / Double(max(oldHeap, 1))))
        print(String(format: "USERLM file old=%dKB new=%dKB", oldBytes / 1024, newBytes / 1024))
        print(String(format: "USERLM load old=%.1fms new=%.1fms  save old=%.1fms new=%.1fms", oldLoad, newLoad, oldSave, newSave))
        print(String(format: "USERLM nextWords old=%.0fns new=%.0fns  count old=%.0fns new=%.0fns  bigram old=%.0fns new=%.0fns  trigram old=%.0fns new=%.0fns  top old=%.0fns new=%.0fns",
                     oldNext, newNext, oldCount, newCount, oldBig, newBig, oldTri, newTri, oldTop, newTop))
        XCTAssertLessThan(newHeap, oldHeap / 2, "bảng gọn phải nhẹ hơn hẳn")
        XCTAssertLessThan(newNext, oldNext * 1.5 + 2000, "nextWords không được chậm đi đáng kể")
        XCTAssertLessThan(newCount, oldCount * 1.5 + 200)
        withExtendedLifetime((old, new)) {}
    }
}
